using System;
using System.Collections.Generic;
using System.IO;
using Exoforge.Management;
using Xunit;

namespace Exoforge.Management.Tests;

public class ExoCodeGeneratorTests
{
    [Fact]
    public void ToPascalCase_SanitizesLeadingDigitsAndSpecialChars()
    {
        Assert.Equal("_1stPlace", ExoCodeGenerator.ToPascalCase("1st_place"));
        Assert.Equal("_247Support", ExoCodeGenerator.ToPascalCase("247-support"));
        Assert.Equal("AuthAdmin", ExoCodeGenerator.ToPascalCase("auth:admin"));
        Assert.Equal("SnakeLeaderboard", ExoCodeGenerator.ToPascalCase("snake-leaderboard"));
        Assert.Equal("UserProfile", ExoCodeGenerator.ToPascalCase("user.profile"));
        Assert.Equal("Unnamed", ExoCodeGenerator.ToPascalCase(""));
        Assert.Equal("Unnamed", ExoCodeGenerator.ToPascalCase("   "));
    }

    [Fact]
    public void SafePropertyName_DisambiguatesEnclosingClassName_CS0542()
    {
        var services = new List<ServiceContractModel>
        {
            new ServiceContractModel
            {
                Name = "score_service",
                Actions = new List<ActionContractModel>
                {
                    new ActionContractModel
                    {
                        Name = "submit",
                        ReturnFields = new List<ParamModel>
                        {
                            new ParamModel { Name = "score_service_submit_response", Type = "integer" }
                        }
                    }
                }
            }
        };

        string code = ExoCodeGenerator.Generate(services);
        // The class name will be ScoreServiceSubmitResponse, and the property must not be ScoreServiceSubmitResponse (CS0542)
        Assert.Contains("public long ScoreServiceSubmitResponseValue { get; set; }", code);
    }

    [Fact]
    public void ModelCollisionDisambiguation_DifferentFields_DisambiguatesClassNames()
    {
        var services = new List<ServiceContractModel>
        {
            new ServiceContractModel
            {
                Name = "service_a",
                Actions = new List<ActionContractModel>
                {
                    new ActionContractModel
                    {
                        Name = "get_status",
                        ReturnTypeName = "StatusResult",
                        ReturnFields = new List<ParamModel>
                        {
                            new ParamModel { Name = "online", Type = "bool" }
                        }
                    }
                }
            },
            new ServiceContractModel
            {
                Name = "service_b",
                Actions = new List<ActionContractModel>
                {
                    new ActionContractModel
                    {
                        Name = "get_status",
                        ReturnTypeName = "StatusResult",
                        ReturnFields = new List<ParamModel>
                        {
                            new ParamModel { Name = "code", Type = "integer" },
                            new ParamModel { Name = "message", Type = "string" }
                        }
                    }
                }
            }
        };

        string code = ExoCodeGenerator.Generate(services);
        // Service A gets StatusResult, Service B gets ServiceBStatusResult
        Assert.Contains("public class StatusResult", code);
        Assert.Contains("public class ServiceBStatusResult", code);
    }

    [Fact]
    public void GenerateToFile_CreatesExoforgeGeneratedAsmdef_InAssetsHierarchy()
    {
        string tempDir = Path.Combine(Path.GetTempPath(), "ExoforgeTest_" + Guid.NewGuid().ToString("N"), "Assets", "Exoforge", "Generated");
        Directory.CreateDirectory(tempDir);
        string outputFile = Path.Combine(tempDir, "ExoforgeServices.g.cs");

        try
        {
            string exportJson = "{\"export\":{\"plugins\":[{\"id\":\"test_svc\",\"name\":\"test_svc\",\"services\":[{\"name\":\"test_svc\",\"actions\":[]}]}]}}";
            bool changed = ExoCodeGenerator.GenerateToFile(exportJson, outputFile);

            Assert.True(changed);
            Assert.True(File.Exists(outputFile));

            string asmdefPath = Path.Combine(tempDir, "Exoforge.Generated.asmdef");
            Assert.True(File.Exists(asmdefPath));

            string asmdefContent = File.ReadAllText(asmdefPath);
            Assert.Contains("\"name\": \"Exoforge.Generated\"", asmdefContent);
            Assert.Contains("\"noEngineReferences\": true", asmdefContent);
        }
        finally
        {
            try { Directory.Delete(Path.GetFullPath(Path.Combine(tempDir, "..", "..", "..")), true); } catch { }
        }
    }

    [Fact]
    public void GenerateToFile_PreservesInUseStubs_WhenMissingFromRemoteExport()
    {
        string tempDir = Path.Combine(Path.GetTempPath(), "ExoforgeStubTest_" + Guid.NewGuid().ToString("N"));
        string assetsDir = Path.Combine(tempDir, "Assets");
        string genDir = Path.Combine(assetsDir, "Exoforge", "Generated");
        Directory.CreateDirectory(genDir);

        string outputFile = Path.Combine(genDir, "ExoforgeServices.g.cs");
        string gameScript = Path.Combine(assetsDir, "GameController.cs");

        try
        {
            // 1. Initial generation with snake_leaderboard
            string initialExport = "{\"export\":{\"plugins\":[{\"id\":\"snake_leaderboard\",\"name\":\"snake_leaderboard\",\"services\":[{\"name\":\"snake_leaderboard\",\"actions\":[{\"name\":\"get_scores\",\"params\":[],\"returns\":[{\"name\":\"top\",\"type\":\"integer\"}]}]}]}]}}";
            ExoCodeGenerator.GenerateToFile(initialExport, outputFile, codeSearchRoot: assetsDir);

            // 2. User writes a script referencing SnakeLeaderboard
            File.WriteAllText(gameScript, "using Exoforge.Client;\npublic class GameController { void Run(ExoClient c) { c.SnakeLeaderboard().GetScoresAsync(); } }");

            // 3. New export from remote server where snake_leaderboard is missing (e.g. only auth is present)
            string newExport = "{\"export\":{\"plugins\":[{\"id\":\"auth\",\"name\":\"auth\",\"services\":[{\"name\":\"auth\",\"actions\":[]}]}]}}";
            bool changed = ExoCodeGenerator.GenerateToFile(newExport, outputFile, codeSearchRoot: assetsDir);

            string updatedCode = File.ReadAllText(outputFile);
            // snake_leaderboard stub must still be preserved because GameController.cs references it!
            Assert.Contains("SnakeLeaderboardServiceClient", updatedCode);
            Assert.Contains("AuthServiceClient", updatedCode);
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { }
        }
    }
}
