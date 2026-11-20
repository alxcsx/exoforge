using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;

namespace Exoforge.Plugin.Generator;

/// <summary>One action's dispatch entry: the wire name and the method that serves it.</summary>
internal sealed record ActionDispatch(string Name, IMethodSymbol Method, long From = 0);

/// <summary>
/// Emits the compile-time action/event table and the contract interface for a service. The host calls
/// straight into the plugin's methods, so nothing reflects over them.
/// </summary>
internal static class DispatchEmitter
{
    /// <summary>The <c>case "x": … return true;</c> lines for one service declaration.</summary>
    public static string Cases(string rootClassFq, List<ActionDispatch> actions)
    {
        var sb = new StringBuilder();

        // One case per wire name. Revisions of an action (FromVersion) share it: the newest that the caller's
        // locked extension version reaches wins, and the oldest answers everyone below.
        foreach (var group in actions.GroupBy(a => a.Name))
        {
            var revisions = group.OrderByDescending(a => a.From).ToList();
            sb.AppendLine($"                case \"{group.Key}\":");

            for (int r = 0; r < revisions.Count; r++)
            {
                var action = revisions[r];
                string indent = "                    ";
                bool conditional = r < revisions.Count - 1;

                if (conditional)
                {
                    sb.AppendLine($"{indent}if (global::Exoforge.Plugin.SDK.ExoDispatch.CallerAtLeast({action.From}L))");
                    sb.AppendLine($"{indent}{{");
                }

                string pad = conditional ? indent + "    " : indent;
                string target = action.Method.IsStatic ? rootClassFq : "plugin";
                sb.AppendLine($"{pad}result = {target}.{action.Method.Name}(");

                var parameters = action.Method.Parameters;
                for (int i = 0; i < parameters.Length; i++)
                {
                    var parameter = parameters[i];
                    string type = parameter.Type.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat);
                    string wireName = ExoforgePluginGenerator.ToSnakeCase(parameter.Name);
                    string fallback = FormatDefault(parameter);
                    string comma = i < parameters.Length - 1 ? "," : "";

                    sb.AppendLine($"{pad}    global::Exoforge.Plugin.SDK.ExoDispatch.Get<{type}>(payload, \"{wireName}\", {fallback}){comma}");
                }

                sb.AppendLine($"{pad});");
                sb.AppendLine($"{pad}return true;");
                if (conditional) sb.AppendLine($"{indent}}}");
            }

            sb.AppendLine();
        }

        return sb.ToString();
    }

    /// <summary>The <c>TryHandleEvent</c> body for the plugin root.</summary>
    public static string EventHandler(string rootClassFq, IMethodSymbol? handler)
    {
        if (handler is null) return "            return false;\n";

        var sb = new StringBuilder();
        sb.AppendLine($"            var plugin = ({rootClassFq})instance;");
        sb.AppendLine();

        if (handler.Parameters.Length == 2)
        {
            string payloadType = handler.Parameters[1].Type.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat);

            sb.AppendLine(payloadType == "global::System.Text.Json.JsonElement"
                ? "            plugin.OnEvent(name, payload);"
                : $"            plugin.OnEvent(name, global::Exoforge.Plugin.SDK.ExoDispatch.Convert<{payloadType}>(payload));");
        }
        else
        {
            sb.AppendLine("            plugin.OnEvent(name);");
        }

        sb.AppendLine("            return true;");
        return sb.ToString();
    }

    /// <summary>The <c>TryRunSeed</c> body for the plugin root.</summary>
    public static string SeedHandler(string rootClassFq, IMethodSymbol? handler)
    {
        if (handler is null) return "            result = null;\n            return false;\n";

        var sb = new StringBuilder();
        string target = handler.IsStatic ? rootClassFq : "plugin";
        sb.AppendLine($"            var plugin = ({rootClassFq})instance;");
        sb.AppendLine();

        if (handler.ReturnsVoid)
        {
            sb.AppendLine($"            {target}.{handler.Name}();");
            sb.AppendLine("            result = null;");
        }
        else
        {
            sb.AppendLine($"            result = {target}.{handler.Name}();");
        }

        sb.AppendLine("            return true;");
        return sb.ToString();
    }

    /// <summary>The dispatch class, assembled from every service declaration the root carries.</summary>
    public static string Class(string rootClassFq, string cases, string eventHandler, string? seedHandler = null)
    {
        var sb = new StringBuilder();
        sb.AppendLine("// <auto-generated>");
        sb.AppendLine("//     Generated by Exoforge.Plugin.Generator. Do not edit.");
        sb.AppendLine("// </auto-generated>");
        sb.AppendLine("#nullable enable");
        sb.AppendLine();
        sb.AppendLine("namespace Exoforge.Generated");
        sb.AppendLine("{");
        sb.AppendLine("    internal sealed class ExoforgeDispatch : global::Exoforge.Plugin.SDK.IExoforgeDispatch");
        sb.AppendLine("    {");
        sb.AppendLine("        public bool TryInvoke(object instance, string action, global::System.Text.Json.JsonElement payload, out object? result)");
        sb.AppendLine("        {");
        sb.AppendLine($"            var plugin = ({rootClassFq})instance;");
        sb.AppendLine();
        sb.AppendLine("            switch (action)");
        sb.AppendLine("            {");
        sb.Append(cases);
        sb.AppendLine("                default:");
        sb.AppendLine("                    result = null;");
        sb.AppendLine("                    return false;");
        sb.AppendLine("            }");
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public bool TryHandleEvent(object instance, string name, global::System.Text.Json.JsonElement payload)");
        sb.AppendLine("        {");
        sb.Append(eventHandler);
        sb.AppendLine("        }");
        sb.AppendLine();
        sb.AppendLine("        public bool TryRunSeed(object instance, out object? result)");
        sb.AppendLine("        {");
        sb.Append(seedHandler ?? "            result = null;\n            return false;\n");
        sb.AppendLine("        }");
        sb.AppendLine("    }");
        sb.AppendLine("}");
        return sb.ToString();
    }

    /// <summary>
    /// The contract interface for a class-declared service, so the service's API exists as a named
    /// type. It carries <c>[ExoAction]</c> so promoting it to a shared contracts project is just
    /// "move this interface, put <c>[ExoService]</c> on it, drop it from the class".
    /// </summary>
    public static string Contract(string interfaceName, List<IMethodSymbol> actions)
    {
        var sb = new StringBuilder();
        sb.AppendLine("// <auto-generated>");
        sb.AppendLine("//     Generated by Exoforge.Plugin.Generator. Do not edit.");
        sb.AppendLine("// </auto-generated>");
        sb.AppendLine("#nullable enable");
        sb.AppendLine();
        sb.AppendLine("namespace Exoforge.Generated.Contracts");
        sb.AppendLine("{");
        sb.AppendLine("    /// <summary>The contract of a service this plugin declares. Implemented by its service class.</summary>");
        sb.AppendLine($"    public interface {interfaceName}");
        sb.AppendLine("    {");

        foreach (var action in actions)
        {
            sb.AppendLine("        [global::Exoforge.Plugin.SDK.ExoAction]");
            sb.AppendLine($"        {Signature(action)};");
            sb.AppendLine();
        }

        sb.AppendLine("    }");
        sb.AppendLine("}");
        return sb.ToString();
    }

    /// <summary>
    /// A partial declaration adding the generated contract to the service class, so the class
    /// formally implements its own contract. Only valid when the class is declared <c>partial</c>.
    /// </summary>
    public static string ContractBinding(string? namespaceName, string className, string interfaceName)
    {
        // The partial has to sit in the class's own namespace, or it would declare a different type.
        string ns = string.IsNullOrEmpty(namespaceName) ? "" : $"namespace {namespaceName}\n{{\n";

        return $@"// <auto-generated>
//     Generated by Exoforge.Plugin.Generator. Do not edit.
// </auto-generated>
#nullable enable

{ns}    partial class {className} : global::Exoforge.Generated.Contracts.{interfaceName}
    {{
    }}
{(string.IsNullOrEmpty(namespaceName) ? "" : "}\n")}";
    }

    /// <summary>The service name as an interface name: <c>snake_leaderboard</c> → <c>ISnakeLeaderboard</c>.</summary>
    public static string InterfaceName(string serviceName)
    {
        var sb = new StringBuilder("I");
        bool upper = true;

        foreach (char c in serviceName)
        {
            if (c == '_' || c == '.' || c == '-')
            {
                upper = true;
                continue;
            }

            sb.Append(upper ? char.ToUpperInvariant(c) : c);
            upper = false;
        }

        return sb.ToString();
    }

    private static string Signature(IMethodSymbol method)
    {
        string returnType = method.ReturnType.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat);
        string parameters = string.Join(", ", method.Parameters.Select(p =>
            $"{p.Type.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat)} {EscapeIdentifier(p.Name)}"));

        return $"{returnType} {method.Name}({parameters})";
    }

    private static string EscapeIdentifier(string name)
    {
        return SyntaxFacts.GetKeywordKind(name) != SyntaxKind.None ? "@" + name : name;
    }

    /// <summary>
    /// The argument's default, as C# source. Only the shapes a default can actually take are
    /// handled; anything else falls back to <c>default</c>, which is what the host's reflection path
    /// would produce for a value type anyway.
    /// </summary>
    private static string FormatDefault(IParameterSymbol parameter)
    {
        if (!parameter.HasExplicitDefaultValue) return "default!";

        object? value = parameter.ExplicitDefaultValue;

        return value switch
        {
            null => "default!",
            string text => SymbolDisplay.FormatLiteral(text, quote: true),
            bool flag => flag ? "true" : "false",
            char character => SymbolDisplay.FormatLiteral(character, quote: true),
            double d => d.ToString("R", CultureInfo.InvariantCulture),
            float f => f.ToString("R", CultureInfo.InvariantCulture) + "f",
            decimal m => m.ToString(CultureInfo.InvariantCulture) + "m",
            long l => l.ToString(CultureInfo.InvariantCulture) + "L",
            _ => Convert.ToString(value, CultureInfo.InvariantCulture) ?? "default!",
        };
    }
}
