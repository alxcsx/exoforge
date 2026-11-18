using System;
using System.IO;
using System.Threading.Tasks;
using Exoforge.CLI;
using Exoforge.Management;
using Xunit;

namespace Exoforge.Management.Tests;

/// <summary>
/// The file the Studio offers to write. The interesting cases are the two "present" ones: the type is
/// internal, so a copy in another assembly does not satisfy this one, but a second copy in the same
/// assembly would be a duplicate type.
/// </summary>
public class ExoIsExternalInitTests : IDisposable
{
    private readonly string _root;

    public ExoIsExternalInitTests()
    {
        _root = Path.Combine(Path.GetTempPath(), $"exo_init_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(_root, "Assets"));
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    [Fact]
    public void Ensure_WritesTheGuardedPolyfill_WhenTheProjectHasNone()
    {
        bool created = ExoIsExternalInit.Ensure(_root, null, out string path);

        Assert.True(created);
        Assert.Equal(Path.Combine(_root, "Assets", "Exoforge", "IsExternalInit.cs"), path);
        string source = File.ReadAllText(path);
        Assert.StartsWith("#if !NET5_0_OR_GREATER", source);
        Assert.Contains("namespace System.Runtime.CompilerServices", source);
        Assert.Contains("internal static class IsExternalInit { }", source);
        Assert.DoesNotContain("public", source);
        Assert.Equal(path, ExoIsExternalInit.FindInProject(_root));
    }

    [Fact]
    public void Ensure_IsANoOp_WhenTheAssemblyAlreadyDeclaresTheType()
    {
        string assembly = Path.Combine(_root, "Assets", "Game");
        Directory.CreateDirectory(assembly);
        File.WriteAllText(Path.Combine(assembly, "Game.asmdef"), "{}");
        string record = Path.Combine(assembly, "Score.cs");
        File.WriteAllText(record, "public record Score(int Value);\n" + ExoIsExternalInit.Source);

        bool created = ExoIsExternalInit.Ensure(_root, "Assets/Game", out string path);

        Assert.False(created);
        Assert.Equal(record, path);
        Assert.False(File.Exists(Path.Combine(assembly, "IsExternalInit.cs")));
    }

    [Fact]
    public void Ensure_WritesACopy_WhenOnlyAnotherAssemblyDeclaresTheType()
    {
        string game = Path.Combine(_root, "Assets", "Game");
        Directory.CreateDirectory(game);
        File.WriteAllText(Path.Combine(game, "Game.asmdef"), "{}");
        File.WriteAllText(Path.Combine(game, "IsExternalInit.cs"), ExoIsExternalInit.Source);

        bool created = ExoIsExternalInit.Ensure(_root, "Assets/Tools", out string path);

        Assert.True(created);
        Assert.Equal(Path.Combine(_root, "Assets", "Tools", "IsExternalInit.cs"), path);
        Assert.True(File.Exists(path));
        Assert.Equal(Path.Combine(game, "IsExternalInit.cs"), ExoIsExternalInit.FindInAssembly(_root, "Assets/Game"));
        Assert.NotNull(ExoIsExternalInit.FindInProject(_root));
    }

    [Fact]
    public void FindInAssembly_DoesNotCrossIntoANestedAsmdef()
    {
        string game = Path.Combine(_root, "Assets", "Game");
        string nested = Path.Combine(game, "Editor");
        Directory.CreateDirectory(nested);
        File.WriteAllText(Path.Combine(game, "Game.asmdef"), "{}");
        File.WriteAllText(Path.Combine(nested, "Editor.asmdef"), "{}");
        File.WriteAllText(Path.Combine(nested, "IsExternalInit.cs"), ExoIsExternalInit.Source);

        Assert.NotNull(ExoIsExternalInit.FindInProject(_root));
        Assert.Null(ExoIsExternalInit.FindInAssembly(_root, "Assets/Game"));
        Assert.NotNull(ExoIsExternalInit.FindInAssembly(_root, "Assets/Game/Editor"));
    }

    [Fact]
    public void FindInProject_IgnoresACopyOutsideAssets()
    {
        string packages = Path.Combine(_root, "Packages", "com.exoforge.sdk");
        Directory.CreateDirectory(packages);
        File.WriteAllText(Path.Combine(packages, "IsExternalInit.cs"), ExoIsExternalInit.Source);

        Assert.Null(ExoIsExternalInit.FindInProject(_root));
    }

    [Fact]
    public async Task UnityRecordsCli_Asmdef_WritesIfMissing_AndIsIdempotent()
    {
        string game = Path.Combine(_root, "Assets", "Game");
        Directory.CreateDirectory(game);
        File.WriteAllText(Path.Combine(game, "Game.asmdef"), "{}");

        string firstOut = await RunCliAsync("unity", "records", "--asmdef", "Assets/Game", "--dir", _root);
        string initPath = Path.Combine(game, "IsExternalInit.cs");
        Assert.True(File.Exists(initPath));
        Assert.Contains("Wrote", firstOut);

        string secondOut = await RunCliAsync("unity", "records", "--asmdef", "Assets/Game", "--dir", _root);
        Assert.Contains("Skipped (already present)", secondOut);
    }

    [Fact]
    public async Task UnityRecordsCli_All_WritesOnlyAsmdefsWithRecordOrInit_AndIsIdempotent()
    {
        string withRecord = Path.Combine(_root, "Assets", "Game");
        string withInit = Path.Combine(_root, "Assets", "Game", "Editor");
        string withoutRecord = Path.Combine(_root, "Assets", "Plain");
        string alreadyHas = Path.Combine(_root, "Assets", "Existing");
        Directory.CreateDirectory(withRecord);
        Directory.CreateDirectory(withInit);
        Directory.CreateDirectory(withoutRecord);
        Directory.CreateDirectory(alreadyHas);

        File.WriteAllText(Path.Combine(withRecord, "Game.asmdef"), "{}");
        File.WriteAllText(Path.Combine(withRecord, "Score.cs"), "public record Score(int Value);\n");

        File.WriteAllText(Path.Combine(withInit, "Game.Editor.asmdef"), "{}");
        File.WriteAllText(Path.Combine(withInit, "Config.cs"), "public class Config { public int Max { get; init; } }\n");

        File.WriteAllText(Path.Combine(withoutRecord, "Plain.asmdef"), "{}");
        File.WriteAllText(Path.Combine(withoutRecord, "Helper.cs"), "public class Helper { int recordId; void Initialize() {} }\n");

        File.WriteAllText(Path.Combine(alreadyHas, "Existing.asmdef"), "{}");
        File.WriteAllText(Path.Combine(alreadyHas, "Model.cs"), "public record Model(string Id);\n");
        File.WriteAllText(Path.Combine(alreadyHas, "IsExternalInit.cs"), ExoIsExternalInit.Source);

        string firstOut = await RunCliAsync("unity", "records", "--all", "--dir", _root);

        Assert.True(File.Exists(Path.Combine(withRecord, "IsExternalInit.cs")));
        Assert.True(File.Exists(Path.Combine(withInit, "IsExternalInit.cs")));
        Assert.False(File.Exists(Path.Combine(withoutRecord, "IsExternalInit.cs")));
        Assert.Contains($"Wrote {Path.Combine(withRecord, "IsExternalInit.cs")}", firstOut);
        Assert.Contains($"Wrote {Path.Combine(withInit, "IsExternalInit.cs")}", firstOut);
        Assert.Contains("Skipped (no record/init): Assets/Plain", firstOut);
        Assert.Contains("Skipped (already present): Assets/Existing", firstOut);

        string secondOut = await RunCliAsync("unity", "records", "--all", "--dir", _root);
        Assert.DoesNotContain("Wrote", secondOut);
        Assert.Contains("Skipped (already present): Assets/Game", secondOut);
        Assert.Contains("Skipped (already present): Assets/Game/Editor", secondOut);
        Assert.Contains("Skipped (no record/init): Assets/Plain", secondOut);
        Assert.Contains("Skipped (already present): Assets/Existing", secondOut);
    }

    private static async Task<string> RunCliAsync(params string[] args)
    {
        var writer = new StringWriter();
        var previous = Console.Out;
        Console.SetOut(writer);
        try
        {
            int code = await Program.Main(args);
            Assert.Equal(0, code);
            return writer.ToString();
        }
        finally
        {
            Console.SetOut(previous);
        }
    }
}
