using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Text;

namespace Exoforge.Plugin.Generator;

/// <summary>
/// Generates a plugin's <c>manifest.json</c> and entry point from its own compilation.
///
/// This replaces the out-of-process ManifestGen tool: the generator already has the full semantic
/// model, so there is no separate <c>dotnet run</c> step, no second project, and none of the
/// child-process path handling that came with it.
/// </summary>
[Generator(LanguageNames.CSharp)]
public sealed class ExoforgePluginGenerator : IIncrementalGenerator
{
    private const string ServiceAttribute = "Exoforge.Plugin.SDK.ExoServiceAttribute";
    private const string ResourceAttribute = "Exoforge.Plugin.SDK.ExoResourceAttribute";
    private const string ActionAttribute = "Exoforge.Plugin.SDK.ExoActionAttribute";
    private const string EventAttribute = "Exoforge.Plugin.SDK.ExoEventAttribute";
    private const string ColumnAttribute = "Exoforge.Plugin.SDK.ExoColumnAttribute";
    private const string PrimaryKeyAttribute = "Exoforge.Plugin.SDK.PrimaryKeyAttribute";
    private const string InjectAttribute = "Exoforge.Plugin.SDK.InjectAttribute";
    private const string JsonContextBase = "System.Text.Json.Serialization.JsonSerializerContext";

    private static readonly DiagnosticDescriptor MultipleRoots = new(
        "EXO002",
        "A plugin declares services on more than one class",
        "'{0}' is the plugin root, but {1} also declare services. A plugin runs one instance - move those declarations onto the root, or split them into separate plugins.",
        "Exoforge",
        DiagnosticSeverity.Warning,
        isEnabledByDefault: true);

    private static readonly DiagnosticDescriptor ManifestWriteFailed = new(
        "EXO001",
        "Could not write the plugin manifest",
        "Could not write '{0}': {1}",
        "Exoforge",
        DiagnosticSeverity.Warning,
        isEnabledByDefault: true);

    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        var services = context.SyntaxProvider
            .ForAttributeWithMetadataName(
                ServiceAttribute,
                predicate: static (node, _) => node is ClassDeclarationSyntax or InterfaceDeclarationSyntax,
                transform: static (ctx, ct) => ExtractService(ctx, ct))
            .Where(static e => e is not null)
            .Select(static (e, _) => e!)
            .Collect();

        // Contracts declared in a referenced assembly - a shared contracts project - are invisible to
        // ForAttributeWithMetadataName, which only walks this compilation's syntax.
        var referenced = context.CompilationProvider.Select(static (compilation, ct) =>
            ExtractReferencedContracts(compilation, ct));

        var settings = context.AnalyzerConfigOptionsProvider.Select(static (provider, _) => new Settings(
            Option(provider.GlobalOptions, "build_property.ExoforgePluginType") ?? "native",
            Option(provider.GlobalOptions, "build_property.ExoforgeBuildStamp"),
            ResolveManifestPath(provider),
            Option(provider.GlobalOptions, "build_property.DesignTimeBuild") == "true"));

        context.RegisterSourceOutput(services.Combine(referenced).Combine(settings), static (spc, pair) =>
        {
            var ((local, external), build) = pair;
            Report(spc, local.AddRange(external), build);
        });
    }

    private static string? Option(AnalyzerConfigOptions options, string key)
    {
        return options.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value) ? value : null;
    }

    /// <summary>
    /// The manifest's full path. A relative one is resolved against the project, not the process.
    ///
    /// The compiler does not run from the project directory - it runs from the .NET SDK's Roslyn
    /// folder - so a bare <c>manifest.json</c> was written there instead. It succeeded, silently, in
    /// a directory nobody looks in, and the build then failed claiming the generator was missing.
    /// </summary>
    private static string? ResolveManifestPath(AnalyzerConfigOptionsProvider provider)
    {
        string? path = Option(provider.GlobalOptions, "build_property.ExoforgeManifestPath");
        if (path is null || Path.IsPathRooted(path)) return path;

        string? projectDir = Option(provider.GlobalOptions, "build_property.ProjectDir");

        return projectDir is null ? path : Path.GetFullPath(Path.Combine(projectDir, path));
    }

    /// <summary>Build settings that shape the manifest. Strings only, so the cache compares by value.</summary>
    internal sealed record Settings(string PluginType, string? BuildStamp, string? ManifestPath, bool DesignTime);

    /// <summary>
    /// One <c>[ExoService]</c> class, flattened to strings so the incremental cache can compare it
    /// by value. The service body is pre-rendered Elixir; only build-dependent fields are left out.
    /// </summary>
    internal sealed record ServiceEmit(
        string Id,
        string Version,
        string Provides,
        string Dependencies,
        string ServiceName,
        string? Category,
        string? Title,
        string? Icon,
        bool System,
        string RootClass,
        bool HasEntryPoint,
        string? JsonContextDisplayName,
        string DispatchCases,
        string EventHandler,
        string ContractInterface,
        string ContractBinding,
        List<ServiceModel> Models,
        List<string> InjectedProperties);

    // ---- service extraction ----

    private static ServiceEmit? ExtractService(GeneratorAttributeSyntaxContext ctx, CancellationToken ct) =>
        Extract(ctx.TargetSymbol as INamedTypeSymbol, ctx.Attributes, ctx.SemanticModel.Compilation, ct);

    /// <summary>
    /// Builds one service declaration. The declaration may come from this compilation or from a
    /// referenced contracts assembly; only the metadata is read, so both look the same here.
    /// </summary>
    private static ServiceEmit? Extract(
        INamedTypeSymbol? declared,
        ImmutableArray<AttributeData> serviceAttrs,
        Compilation compilation,
        CancellationToken ct)
    {
        if (declared is null || serviceAttrs.IsDefaultOrEmpty) return null;

        // A contract interface declares the service and the class implementing it is the plugin's
        // root. A class declares and implements it in one place.
        bool isContract = declared.TypeKind == TypeKind.Interface;
        var root = isContract ? FindImplementation(compilation, declared) : declared;
        if (root is null) return null;

        string id = (compilation.AssemblyName ?? "plugin").ToLowerInvariant();
        string pluginVersion = "0.1.0";
        var provides = new List<string>();

        foreach (var attr in serviceAttrs)
        {
            string name = PositionalString(attr, 0) ?? "";
            if (name.Length > 0 && !provides.Contains(name)) provides.Add(name);

            string? declaredVersion = NamedString(attr, "Version");
            if (!string.IsNullOrEmpty(declaredVersion)) pluginVersion = declaredVersion!;
        }

        // One service entry per [ExoService]. A plugin may provide several - an Elixir plugin does the
        // same with `provides: [ContractA, ContractB]` - and every action, event and resource is
        // attributed to one of them. Without an explicit Service it belongs to the first.
        var services = new List<ServiceModel>();

        foreach (var attr in serviceAttrs)
        {
            services.Add(new ServiceModel(
                PositionalString(attr, 0) ?? id,
                new List<ActionModel>(),
                new List<EventModel>(),
                new List<ResourceModel>(),
                NamedString(attr, "Category"),
                NamedString(attr, "Title"),
                NamedString(attr, "Icon"),
                NamedBool(attr, "System")));
        }

        ServiceModel ServiceFor(string? name)
        {
            if (!string.IsNullOrEmpty(name))
            {
                foreach (var candidate in services)
                {
                    if (candidate.Name == name) return candidate;
                }
            }

            return services[0];
        }

        var dispatches = new List<ActionDispatch>();

        foreach (var member in declared.GetMembers())
        {
            if (member is not IMethodSymbol method) continue;

            var actionAttr = FindAttribute(method.GetAttributes(), ActionAttribute);
            if (actionAttr is null) continue;

            string actionName = PositionalString(actionAttr, 0) ?? ToSnakeCase(method.Name);
            dispatches.Add(new ActionDispatch(actionName, method));

            var (returnsScalar, returnFields, returnsList, returnsType) = DescribeReturn(method.ReturnType);

            ServiceFor(NamedString(actionAttr, "Service")).Actions.Add(new ActionModel(
                actionName,
                ResolveActionMode(actionAttr, method.ReturnType),
                NamedString(actionAttr, "Scope") ?? "global",
                (NamedEnum(actionAttr, "Transport") ?? "auto").ToLowerInvariant(),
                method.Parameters.Select(p => new ParamModel(ToSnakeCase(p.Name), MapTypeToElixir(p.Type))).ToList(),
                returnsScalar,
                returnFields,
                returnsList,
                returnsType));
        }

        // Events: declared on the declaration itself and on its methods.
        foreach (var attr in declared.GetAttributes())
        {
            if (IsAttribute(attr, EventAttribute)) AddEvent(ServiceFor(NamedString(attr, "Service")), attr);
        }

        foreach (var member in declared.GetMembers())
        {
            if (member is not IMethodSymbol method) continue;

            foreach (var attr in method.GetAttributes())
            {
                if (IsAttribute(attr, EventAttribute)) AddEvent(ServiceFor(NamedString(attr, "Service")), attr);
            }
        }

        var primary = services[0];

        // Resources: from [ExoService(Resources = ...)] and from [ExoResource] on the declaring type -
        // both belong to the service that declared them. A standalone [ExoResource] record elsewhere
        // in the assembly belongs to the primary service.
        foreach (var attr in serviceAttrs)
        {
            var owner = ServiceFor(PositionalString(attr, 0));

            foreach (var resType in NamedTypeArray(attr, "Resources"))
            {
                AddResource(owner.Resources, ResourceFromType(resType, ActionNames(owner)));
            }
        }

        foreach (var attr in declared.GetAttributes())
        {
            if (!IsAttribute(attr, ResourceAttribute)) continue;

            var target = NamedType(attr, "ResourceType");
            if (target is not null)
            {
                AddResource(primary.Resources, ResourceFromType(target, ActionNames(primary)));
                continue;
            }

            var columns = ColumnsFor(declared, attr, out _);
            if (columns.Count == 0) continue;

            string resName = NamedString(attr, "Name") ?? PositionalString(attr, 0) ?? ToSnakeCase(declared.Name);
            AddResource(primary.Resources, new ResourceModel(
                resName,
                NamedString(attr, "Source") ?? resName,
                NamedString(attr, "PrimaryKey") ?? "id",
                NamedStringArray(attr, "DrawerTabs") ?? new[] { "overview" },
                ActionNames(primary),
                columns,
                declared.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat)));
        }

        foreach (var candidate in AllTypes(compilation.Assembly.GlobalNamespace))
        {
            if (SymbolEqualityComparer.Default.Equals(candidate, declared)) continue;
            if (candidate.GetAttributes().Any(a => IsAttribute(a, ServiceAttribute))) continue;

            var resAttr = FindAttribute(candidate.GetAttributes(), ResourceAttribute);
            if (resAttr is null) continue;

            AddResource(primary.Resources, ResourceFromType(candidate, ActionNames(primary)));
        }

        // Dependencies come from the root: it is the instance the host runs and wires. Only an
        // explicit service name counts - an unnamed [Inject] is a context capability, not a
        // plugin dependency.
        var dependencies = new List<string>();

        // Every [Inject] property, named, so the entry point can keep them from being trimmed.
        var injected = new List<string>();

        foreach (var member in root.GetMembers())
        {
            if (member is not IPropertySymbol property) continue;

            var inject = FindAttribute(property.GetAttributes(), InjectAttribute);
            if (inject is null) continue;

            injected.Add(property.Name);

            string? dep = PositionalString(inject, 0) ?? NamedString(inject, "ServiceName");
            if (!string.IsNullOrEmpty(dep) && !dependencies.Contains(dep!)) dependencies.Add(dep!);
        }

        string rootFq = root.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat);

        // A class is its own contract, so one is generated for it. A declared interface already is
        // the contract and is left alone.
        string contract = "";
        string binding = "";

        if (!isContract)
        {
            var contracts = new StringBuilder();
            var bindings = new StringBuilder();
            string? ns = declared.ContainingNamespace.IsGlobalNamespace ? null : declared.ContainingNamespace.ToDisplayString();

            foreach (var model in services)
            {
                string interfaceName = DispatchEmitter.InterfaceName(model.Name);

                var methods = dispatches
                    .Where(d => model.Actions.Any(a => a.Name == d.Name))
                    .Select(d => d.Method)
                    .ToList();

                contracts.Append(DispatchEmitter.Contract(interfaceName, methods));

                if (IsPartial(declared))
                {
                    bindings.Append(DispatchEmitter.ContractBinding(ns, declared.Name, interfaceName));
                }
            }

            contract = contracts.ToString();
            binding = bindings.ToString();
        }

        return new ServiceEmit(
            id,
            pluginVersion,
            string.Join(",", provides),
            string.Join(",", dependencies),
            primary.Name,
            primary.Category,
            primary.Title,
            primary.Icon,
            primary.System,
            rootFq,
            compilation.GetEntryPoint(ct) is not null,
            FindJsonContext(compilation),
            DispatchEmitter.Cases(rootFq, dispatches),
            DispatchEmitter.EventHandler(rootFq, FindEventHandler(root)),
            contract,
            binding,
            services,
            injected);
    }

    private static ImmutableArray<ServiceEmit> ExtractReferencedContracts(Compilation compilation, CancellationToken ct)
    {
        var builder = ImmutableArray.CreateBuilder<ServiceEmit>();

        foreach (var assembly in ContractAssemblies(compilation))
        {
            foreach (var type in AllTypes(assembly.GlobalNamespace))
            {
                if (type.TypeKind != TypeKind.Interface) continue;

                var attrs = type.GetAttributes()
                    .Where(a => IsAttribute(a, ServiceAttribute))
                    .ToImmutableArray();

                if (attrs.IsDefaultOrEmpty) continue;

                var emit = Extract(type, attrs, compilation, ct);
                if (emit is not null) builder.Add(emit);
            }
        }

        return builder.ToImmutable();
    }

    /// <summary>
    /// Assemblies that could declare a contract: anything referencing the plugin SDK. Walking every
    /// reference would traverse the whole framework for nothing.
    /// </summary>
    private static IEnumerable<IAssemblySymbol> ContractAssemblies(Compilation compilation)
    {
        foreach (var assembly in compilation.SourceModule.ReferencedAssemblySymbols)
        {
            if (assembly.Name == "Exoforge.Plugin.SDK") continue;

            var module = assembly.Modules.FirstOrDefault();
            if (module is null) continue;

            if (module.ReferencedAssemblySymbols.Any(r => r.Name == "Exoforge.Plugin.SDK"))
            {
                yield return assembly;
            }
        }
    }

    /// <summary>The class that implements a contract interface, and therefore runs as the plugin.</summary>
    private static INamedTypeSymbol? FindImplementation(Compilation compilation, INamedTypeSymbol contract)
    {
        foreach (var candidate in AllTypes(compilation.Assembly.GlobalNamespace))
        {
            if (candidate.TypeKind != TypeKind.Class || candidate.IsAbstract) continue;

            foreach (var implemented in candidate.AllInterfaces)
            {
                if (SymbolEqualityComparer.Default.Equals(implemented, contract)) return candidate;
            }
        }

        return null;
    }

    private static bool IsPartial(INamedTypeSymbol type)
    {
        foreach (var reference in type.DeclaringSyntaxReferences)
        {
            if (reference.GetSyntax() is TypeDeclarationSyntax declaration &&
                declaration.Modifiers.Any(m => m.IsKind(SyntaxKind.PartialKeyword)))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// The plugin's inbound event handler: <c>OnEvent(string, TPayload)</c> for any payload type, or
    /// <c>OnEvent(string)</c>. Optional.
    /// </summary>
    private static IMethodSymbol? FindEventHandler(INamedTypeSymbol type)
    {
        IMethodSymbol? single = null;

        foreach (var member in type.GetMembers("OnEvent"))
        {
            if (member is not IMethodSymbol method) continue;

            var parameters = method.Parameters;

            if (parameters.Length == 2 && parameters[0].Type.SpecialType == SpecialType.System_String) return method;

            if (parameters.Length == 1 && parameters[0].Type.SpecialType == SpecialType.System_String) single ??= method;
        }

        return single;
    }

    private static void AddResource(List<ResourceModel> resources, ResourceModel? resource)
    {
        if (resource is null) return;
        if (resources.Any(r => r.Name == resource.Name)) return;
        resources.Add(resource);
    }

    private static List<string> ActionNames(ServiceModel service) =>
        service.Actions.Select(a => a.Name).ToList();

    private static void AddEvent(ServiceModel service, AttributeData attr)
    {
        string name = PositionalString(attr, 0) ?? "";
        if (name.Length == 0 || service.Events.Any(e => e.Name == name)) return;

        var payloadType = NamedType(attr, "PayloadType") ?? PositionalType(attr, 1);
        var payload = new List<ParamModel>();

        if (payloadType is not null)
        {
            foreach (var member in payloadType.GetMembers())
            {
                if (member is IPropertySymbol property && property.DeclaredAccessibility == Accessibility.Public)
                {
                    payload.Add(new ParamModel(ToSnakeCase(property.Name), MapTypeToElixir(property.Type)));
                }
            }
        }

        service.Events.Add(new EventModel(
            name,
            NamedString(attr, "Topic"),
            NamedString(attr, "Scope") ?? "global",
            payload,
            payloadType?.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat)));
    }

    private static IEnumerable<INamedTypeSymbol> AllTypes(INamespaceSymbol root)
    {
        foreach (var member in root.GetMembers())
        {
            switch (member)
            {
                case INamespaceSymbol ns:
                    foreach (var nested in AllTypes(ns)) yield return nested;
                    break;
                case INamedTypeSymbol type:
                    foreach (var nested in AllTypes(type)) yield return nested;
                    yield return type;
                    break;
            }
        }
    }

    private static IEnumerable<INamedTypeSymbol> AllTypes(INamedTypeSymbol type)
    {
        foreach (var member in type.GetTypeMembers())
        {
            foreach (var nested in AllTypes(member)) yield return nested;
            yield return member;
        }
    }

    /// <summary>
    /// The plugin's own <see cref="System.Text.Json.Serialization.JsonSerializerContext"/>, if it has
    /// one. Generated service stubs declare their own and register it themselves.
    /// </summary>
    private static string? FindJsonContext(Compilation compilation)
    {
        foreach (var symbol in compilation.GetSymbolsWithName(static _ => true, SymbolFilter.Type))
        {
            if (symbol is not INamedTypeSymbol named) continue;

            for (var baseType = named.BaseType; baseType is not null; baseType = baseType.BaseType)
            {
                if (baseType.ToDisplayString() == JsonContextBase)
                {
                    return named.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat);
                }
            }
        }

        return null;
    }

    // ---- resource extraction ----

    private static ResourceModel? ResourceFromType(ITypeSymbol symbol, List<string> serviceActions)
    {
        if (symbol is not INamedTypeSymbol resourceType) return null;

        var resAttr = FindAttribute(resourceType.GetAttributes(), ResourceAttribute);

        string typeName = resourceType.Name;
        if (typeName.EndsWith("Resource", StringComparison.OrdinalIgnoreCase) && typeName.Length > 8)
        {
            typeName = typeName.Substring(0, typeName.Length - 8);
        }

        string resName = NamedString(resAttr, "Name") ?? PositionalString(resAttr, 0) ?? ToSnakeCase(typeName);

        var columns = ColumnsFor(resourceType, resAttr, out var primaryKey);
        if (string.IsNullOrEmpty(primaryKey))
        {
            var candidate = columns.FirstOrDefault(c =>
                c.Name == "id" || c.Name == resName + "_id" || c.Name.EndsWith("_id", StringComparison.Ordinal));

            primaryKey = candidate?.Name ?? (columns.Count > 0 ? columns[0].Name : "id");
        }

        return new ResourceModel(
            resName,
            NamedString(resAttr, "Source") ?? resName,
            primaryKey!,
            NamedStringArray(resAttr, "DrawerTabs") ?? new[] { "overview", "attributes" },
            serviceActions,
            columns,
            resourceType.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat));
    }

    private static List<ColumnModel> ColumnsFor(INamedTypeSymbol type, AttributeData? resourceAttr, out string? primaryKey)
    {
        var columns = new List<ColumnModel>();
        primaryKey = NamedString(resourceAttr, "PrimaryKey");

        foreach (var member in type.GetMembers())
        {
            if (member is not IPropertySymbol property) continue;
            if (property.DeclaredAccessibility != Accessibility.Public || property.IsStatic) continue;

            var colAttr = FindAttribute(property.GetAttributes(), ColumnAttribute);
            var pkAttr = FindAttribute(property.GetAttributes(), PrimaryKeyAttribute);

            bool isExplicitPk = pkAttr is not null || property.Name.Equals("Id", StringComparison.OrdinalIgnoreCase);

            // Without [ExoColumn] the property still counts when the record carries [ExoResource].
            if (colAttr is null && pkAttr is null && resourceAttr is null) continue;

            string colName = NamedString(colAttr, "Name") ?? PositionalString(colAttr, 0) ?? ToSnakeCase(property.Name);

            columns.Add(new ColumnModel(
                colName,
                NamedString(colAttr, "DataType") ?? MapTypeToElixir(property.Type),
                NamedString(colAttr, "Label") ?? ToTitleCase(colName),
                NamedBool(colAttr, "Sortable") || isExplicitPk,
                NamedBool(colAttr, "Filterable"),
                NamedBool(colAttr, "Badge"),
                NamedString(colAttr, "Role"),
                DefaultOf(property),
                ChoicesOf(property)));

            if (pkAttr is not null && string.IsNullOrEmpty(primaryKey)) primaryKey = colName;
        }

        return columns;
    }

    // ---- output ----

    private static void Report(SourceProductionContext spc, ImmutableArray<ServiceEmit> emits, Settings settings)
    {
        if (emits.IsDefaultOrEmpty) return;

        // Deterministic order: the compilation's member order is not guaranteed, and the manifest
        // must not differ between machines.
        var ordered = emits.OrderBy(e => e.ServiceName, StringComparer.Ordinal).ToImmutableArray();

        // One plugin runs one instance, so it has one root. Services declared on several classes
        // would leave the host no single object to run: the first root wins, and the rest are named.
        var roots = ordered.Select(e => e.RootClass).Distinct(StringComparer.Ordinal).ToList();
        string root = roots[0];
        var owned = ordered.Where(e => e.RootClass == root).ToImmutableArray();
        var primary = owned[0];

        if (roots.Count > 1)
        {
            spc.ReportDiagnostic(Diagnostic.Create(
                MultipleRoots, Location.None, root, string.Join(", ", roots.Skip(1))));
        }

        var cases = new StringBuilder();
        foreach (var emit in owned) cases.Append(emit.DispatchCases);

        spc.AddSource("ExoforgeDispatch.g.cs", SourceText.From(
            DispatchEmitter.Class(root, cases.ToString(), primary.EventHandler), Encoding.UTF8));

        var contracts = new StringBuilder();
        var bindings = new StringBuilder();

        foreach (var emit in ordered)
        {
            contracts.Append(emit.ContractInterface);
            bindings.Append(emit.ContractBinding);
        }

        if (contracts.Length > 0)
        {
            spc.AddSource("ExoforgeContracts.g.cs", SourceText.From(contracts.ToString(), Encoding.UTF8));
        }

        if (bindings.Length > 0)
        {
            spc.AddSource("ExoforgeContractBindings.g.cs", SourceText.From(bindings.ToString(), Encoding.UTF8));
        }

        if (!primary.HasEntryPoint)
        {
            spc.AddSource("ExoforgeEntryPoint.g.cs", SourceText.From(
                EntryPoint(primary, primary.JsonContextDisplayName ?? ""), Encoding.UTF8));
        }

        if (settings.ManifestPath is null || settings.DesignTime) return;

        var provides = new List<string>();
        var dependencies = new List<string>();

        foreach (var emit in ordered)
        {
            foreach (var name in emit.Provides.Split(',')) if (name.Length > 0 && !provides.Contains(name)) provides.Add(name);
            foreach (var name in emit.Dependencies.Split(',')) if (name.Length > 0 && !dependencies.Contains(name)) dependencies.Add(name);
        }

        // Sorted for the same reason the generated client is: a manifest that reorders itself between
        // builds is a diff that says nothing. The services are already ordered by name.
        provides.Sort(StringComparer.Ordinal);
        dependencies.Sort(StringComparer.Ordinal);

        // Every emit's services, not just the primary one's: a plugin whose services are declared on
        // several roots would otherwise ship a manifest that mentions only the first.
        var models = new List<ServiceModel>();
        foreach (var emit in ordered) models.AddRange(emit.Models);

        string final = ManifestEmitter.Finalize(
            ManifestEmitter.Manifest(
                primary.Id, provides, dependencies, models,
                primary.Category, primary.Title, primary.Icon, primary.System),
            primary.Id, primary.Version, settings.PluginType, settings.BuildStamp);

        // The plugin's own records need a JsonSerializerContext, and nothing can generate one *into* the
        // compile that needs it: a source generator's output is invisible to the System.Text.Json
        // generator, which is what fills in the context's members. A real file is visible to it - so
        // this is written like the manifest, and the compile after this one has it.
        string context = Context(primary.Id, models);

        try
        {
            var directory = Path.GetDirectoryName(settings.ManifestPath);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);

            WriteIfChanged(settings.ManifestPath, final);
            WriteIfChanged(Path.Combine(directory ?? ".", "src", "Generated", "ExoforgeJsonContext.g.cs"), context);

            // The Elixir manifest this replaced is now a stale copy of a different format. Left behind,
            // the server would find and evaluate it in preference to nothing, and the plugin would
            // deploy at whatever version it described.
            string previous = Path.ChangeExtension(settings.ManifestPath, ".exs");
            if (File.Exists(previous)) File.Delete(previous);
        }
        catch (Exception ex)
        {
            spc.ReportDiagnostic(Diagnostic.Create(ManifestWriteFailed, Location.None, settings.ManifestPath, ex.Message));
        }
    }

    /// <summary>
    /// Writes a file only when its content changed, so an untouched build does not look like a source
    /// edit to MSBuild - which would recompile the plugin every time.
    /// </summary>
    private static void WriteIfChanged(string path, string content)
    {
        string? directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);

        if (File.Exists(path) && File.ReadAllText(path) == content) return;

        File.WriteAllText(path, content, new UTF8Encoding(false));
    }

    /// <summary>
    /// The plugin's JSON context, as a file the System.Text.Json generator can see.
    ///
    /// Everything it needs is already in the attributes: a resource's record, an event's payload type,
    /// an action's return type. An anonymous object cannot be registered and is not the shape the SDK
    /// asks for anyway.
    /// </summary>
    private static string Context(string id, List<ServiceModel> models)
    {
        var types = new List<string>();

        foreach (var model in models)
        {
            foreach (var resource in model.Resources)
            {
                if (resource.TypeName is not null && !types.Contains(resource.TypeName)) types.Add(resource.TypeName);
            }

            foreach (var evt in model.Events)
            {
                if (evt.PayloadTypeName is not null && !types.Contains(evt.PayloadTypeName)) types.Add(evt.PayloadTypeName);
            }

            foreach (var action in model.Actions)
            {
                if (action.ReturnsType is not null && !types.Contains(action.ReturnsType)) types.Add(action.ReturnsType);
            }
        }

        types.Sort(StringComparer.Ordinal);

        var sb = new StringBuilder();
        sb.AppendLine("// <auto-generated>");
        sb.AppendLine("//     Generated by Exoforge.Plugin.Generator. Do not edit.");
        sb.AppendLine("// </auto-generated>");
        sb.AppendLine("#nullable enable");
        sb.AppendLine();
        sb.AppendLine("using System.Text.Json.Serialization;");
        sb.AppendLine();

        foreach (string type in types)
        {
            sb.AppendLine($"[JsonSerializable(typeof({type}))]");
        }

        sb.AppendLine($"public partial class ExoforgeJsonContext : JsonSerializerContext");
        sb.AppendLine("{");
        sb.AppendLine("}");
        return sb.ToString();
    }

    private static string EntryPoint(ServiceEmit emit, string context)
    {
        const string dispatch = "global::Exoforge.Generated.ExoforgeDispatch";

        // The three-argument Run needs a context. Without one the plugin falls back to the host's
        // reflection path, which is what it had before the generator existed.
        // The plugin's [Inject] properties are reached by reflection - the host assigns them - and an
        // annotation at a use site did not survive: the dataflow has to reach the call site, and the
        // call site is here, in the plugin's own assembly. They were trimmed and every injected
        // dependency was silently null. Naming the members keeps them unconditionally.
        //
        // By name, not by member kind: the SDK ships an internal polyfill of the kinds enum for
        // netstandard2.1, so a project that can see it - the generator's own tests, through
        // InternalsVisibleTo - sees the type twice.
        string injected = string.Concat(emit.InjectedProperties.Select(name =>
            $"        [global::System.Diagnostics.CodeAnalysis.DynamicDependency(\"{name}\", typeof({emit.RootClass}))]\n"));

        string run = context.Length == 0
            ? $"global::Exoforge.Plugin.SDK.PluginHost.RunInstance(new {emit.RootClass}(), new {dispatch}());"
            : $"global::Exoforge.Plugin.SDK.PluginHost.Run<{emit.RootClass}, {context}, {dispatch}>();";

        return $@"// <auto-generated>
//     Generated by Exoforge.Plugin.Generator. Do not edit.
// </auto-generated>
#nullable enable

namespace Exoforge.Generated
{{
    internal static class ExoforgeEntryPoint
    {{
{injected}        public static void Main() => {run}
    }}
}}
";
    }

    // ---- type mapping ----

    /// <summary>
    /// The fixed set a column's values come from, when its type is an enum.
    ///
    /// Declaring the enum is the whole declaration: `public CounterStatus Status` is a string column
    /// that accepts those names, and nothing has to be repeated in an attribute. An Elixir contract
    /// says the same thing with <c>column(:status, :string, choices: ~w(active retired))</c> - there is
    /// no enum type to read there, so the list is the declaration.
    /// </summary>
    private static List<string>? ChoicesOf(IPropertySymbol property)
    {
        if (property.Type is not INamedTypeSymbol { TypeKind: TypeKind.Enum } enumType) return null;

        var names = enumType.GetMembers()
            .OfType<IFieldSymbol>()
            .Where(field => field.IsConst)
            .Select(field => ToSnakeCase(field.Name))
            .ToList();

        return names.Count == 0 ? null : names;
    }

    /// <summary>
    /// A property's initializer, as the schema's default. A record that says `= "active"` has said it
    /// once; without this the store has no default, the form sends nothing, and the column is absent
    /// from every row written through the Studio.
    /// </summary>
    private static string? DefaultOf(IPropertySymbol property)
    {
        foreach (var reference in property.DeclaringSyntaxReferences)
        {
            if (reference.GetSyntax() is not PropertyDeclarationSyntax declaration) continue;
            if (declaration.Initializer?.Value is not { } value) continue;

            return value switch
            {
                LiteralExpressionSyntax literal when literal.Token.Value is string text => text,
                LiteralExpressionSyntax { Token.Value: not null } literal => literal.Token.ValueText,
                PrefixUnaryExpressionSyntax { Operand: LiteralExpressionSyntax operand } unary =>
                    unary.OperatorToken.Text + operand.Token.ValueText,
                // `= CounterStatus.Active` - the enum's own spelling, snake_cased like the choices.
                MemberAccessExpressionSyntax member => ToSnakeCase(member.Name.Identifier.Text),
                _ => null,
            };
        }

        return null;
    }

    private static string MapTypeToElixir(ITypeSymbol type)
    {
        if (type is INamedTypeSymbol named)
        {
            if (named.Name == "Task" && named.ContainingNamespace?.ToDisplayString() == "System.Threading.Tasks")
            {
                return named.TypeArguments.Length == 1 ? MapTypeToElixir(named.TypeArguments[0]) : "ok";
            }

            if (named.OriginalDefinition.SpecialType == SpecialType.System_Nullable_T && named.TypeArguments.Length == 1)
            {
                return MapTypeToElixir(named.TypeArguments[0]);
            }
        }

        switch (type.SpecialType)
        {
            case SpecialType.System_Void:
                return "ok";
            case SpecialType.System_Int32:
            case SpecialType.System_Int64:
            case SpecialType.System_Int16:
            case SpecialType.System_Byte:
            case SpecialType.System_UInt32:
            case SpecialType.System_UInt64:
                return "integer";
            case SpecialType.System_String:
            case SpecialType.System_Char:
                return "string";
            case SpecialType.System_Boolean:
                return "boolean";
            case SpecialType.System_Single:
            case SpecialType.System_Double:
            case SpecialType.System_Decimal:
                return "float";
        }

        // An enum is one of a fixed set of names, so it is a string with choices - not a map, which is
        // what it used to fall through to.
        if (type.TypeKind == TypeKind.Enum) return "string";

        string display = type.ToDisplayString();

        if (display == "System.DateTime" || display == "System.DateTimeOffset") return "datetime";
        if (display == "System.Guid") return "uuid";
        if (type is IArrayTypeSymbol { ElementType.SpecialType: SpecialType.System_Byte }) return "binary";

        return "map";
    }

    /// <summary>
    /// The action's return as the manifest describes it: a scalar type atom, a record's fields, or
    /// <c>:ok</c> for nothing - plus whether the whole thing is a list. Without the field shape a
    /// generated client can only offer <c>JsonElement</c>.
    /// </summary>
    private static (string? Scalar, List<ParamModel> Fields, bool IsList, string? TypeName) DescribeReturn(ITypeSymbol type)
    {
        if (type is INamedTypeSymbol named)
        {
            if (named.Name == "Task" && named.ContainingNamespace?.ToDisplayString() == "System.Threading.Tasks")
            {
                return named.TypeArguments.Length == 1 ? DescribeReturn(named.TypeArguments[0]) : ("ok", new List<ParamModel>(), false, null);
            }

            if (named.OriginalDefinition.SpecialType == SpecialType.System_Nullable_T && named.TypeArguments.Length == 1)
            {
                return DescribeReturn(named.TypeArguments[0]);
            }
        }

        // Checked before the list case: a byte array is binary, not a list of integers.
        if (type is IArrayTypeSymbol { ElementType.SpecialType: SpecialType.System_Byte }) return ("binary", new List<ParamModel>(), false, null);

        if (IsList(type, out var element))
        {
            var (scalar, innerFields, _, typeName) = DescribeReturn(element!);
            return (scalar, innerFields, true, typeName);
        }

        if (type.SpecialType != SpecialType.None || IsKnownScalar(type) || type.TypeKind == TypeKind.Enum)
        {
            return (MapTypeToElixir(type), new List<ParamModel>(), false, null);
        }

        // A record: its public properties are the response fields.
        var fields = new List<ParamModel>();

        foreach (var member in type.GetMembers())
        {
            if (member is IPropertySymbol property && property.DeclaredAccessibility == Accessibility.Public && !property.IsStatic)
            {
                fields.Add(new ParamModel(ToSnakeCase(property.Name), MapTypeToElixir(property.Type)));
            }
        }

        if (fields.Count == 0) return (MapTypeToElixir(type), fields, false, null);

        return (null, fields, false, type.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat));
    }

    private static bool IsList(ITypeSymbol type, out ITypeSymbol? element)
    {
        if (type is IArrayTypeSymbol array)
        {
            element = array.ElementType;
            return true;
        }

        if (type is INamedTypeSymbol named && named.TypeArguments.Length == 1 &&
            named.Name is "List" or "IReadOnlyList" or "IList" or "IEnumerable" or "IReadOnlyCollection" or "ICollection")
        {
            element = named.TypeArguments[0];
            return true;
        }

        element = null;
        return false;
    }

    private static bool IsKnownScalar(ITypeSymbol type)
    {
        return type.ToDisplayString() is
            "System.DateTime" or "System.DateTimeOffset" or "System.Guid" or "System.TimeSpan" or
            "System.Text.Json.JsonElement" or "System.Text.Json.Nodes.JsonNode";
    }

    private static string ResolveActionMode(AttributeData attr, ITypeSymbol returnType)
    {
        string? mode = NamedEnum(attr, "Mode");

        if (mode is null || mode == "Auto")
        {
            return IsTask(returnType) ? "async" : "sync";
        }

        return mode.ToLowerInvariant();
    }

    private static bool IsTask(ITypeSymbol type)
    {
        return type is INamedTypeSymbol named &&
               named.Name == "Task" &&
               named.ContainingNamespace?.ToDisplayString() == "System.Threading.Tasks";
    }

    private static string ToSnakeCase(string name)
    {
        var sb = new StringBuilder(name.Length + 4);

        for (int i = 0; i < name.Length; i++)
        {
            if (char.IsUpper(name[i]) && i > 0) sb.Append('_');
            sb.Append(char.ToLowerInvariant(name[i]));
        }

        return sb.ToString();
    }

    private static string ToTitleCase(string name)
    {
        var words = name.Split(new[] { '_' }, StringSplitOptions.RemoveEmptyEntries);

        for (int i = 0; i < words.Length; i++)
        {
            words[i] = words[i].Length == 1
                ? words[i].ToUpperInvariant()
                : char.ToUpperInvariant(words[i][0]) + words[i].Substring(1);
        }

        return string.Join(" ", words);
    }

    // ---- attribute readers ----

    private static bool IsAttribute(AttributeData attr, string metadataName)
    {
        return attr.AttributeClass?.ToDisplayString() == metadataName;
    }

    private static AttributeData? FindAttribute(IEnumerable<AttributeData> attributes, string metadataName)
    {
        return attributes.FirstOrDefault(a => IsAttribute(a, metadataName));
    }

    private static string? PositionalString(AttributeData? attr, int index)
    {
        if (attr is null || attr.ConstructorArguments.Length <= index) return null;
        return attr.ConstructorArguments[index].Value as string;
    }

    private static ITypeSymbol? PositionalType(AttributeData? attr, int index)
    {
        if (attr is null || attr.ConstructorArguments.Length <= index) return null;
        return attr.ConstructorArguments[index].Value as ITypeSymbol;
    }

    private static string? NamedString(AttributeData? attr, string name)
    {
        if (attr is null) return null;

        foreach (var arg in attr.NamedArguments)
        {
            if (arg.Key == name) return arg.Value.Value as string;
        }

        return null;
    }

    private static bool NamedBool(AttributeData? attr, string name)
    {
        if (attr is null) return false;

        foreach (var arg in attr.NamedArguments)
        {
            if (arg.Key == name) return arg.Value.Value is bool value && value;
        }

        return false;
    }

    private static ITypeSymbol? NamedType(AttributeData? attr, string name)
    {
        if (attr is null) return null;

        foreach (var arg in attr.NamedArguments)
        {
            if (arg.Key == name) return arg.Value.Value as ITypeSymbol;
        }

        return null;
    }

    private static string[]? NamedStringArray(AttributeData? attr, string name)
    {
        if (attr is null) return null;

        foreach (var arg in attr.NamedArguments)
        {
            if (arg.Key != name || arg.Value.Kind != TypedConstantKind.Array) continue;

            return arg.Value.Values.Select(v => v.Value as string ?? "").Where(s => s.Length > 0).ToArray();
        }

        return null;
    }

    private static IEnumerable<ITypeSymbol> NamedTypeArray(AttributeData? attr, string name)
    {
        if (attr is null) yield break;

        foreach (var arg in attr.NamedArguments)
        {
            if (arg.Key != name || arg.Value.Kind != TypedConstantKind.Array) continue;

            foreach (var value in arg.Value.Values)
            {
                if (value.Value is ITypeSymbol type) yield return type;
            }
        }
    }

    private static string? NamedEnum(AttributeData? attr, string name)
    {
        if (attr is null) return null;

        foreach (var arg in attr.NamedArguments)
        {
            if (arg.Key != name) continue;
            if (arg.Value.Type is not INamedTypeSymbol enumType) return null;

            foreach (var member in enumType.GetMembers())
            {
                if (member is IFieldSymbol field && Equals(field.ConstantValue, arg.Value.Value)) return field.Name;
            }
        }

        return null;
    }
}
