using System.Linq;
using Xunit;

namespace Exoforge.Management.Tests;

public class DeployOrderTests
{
    private static DeployNode N(string name, string[] provides, params string[] deps) => new(name, provides, deps);

    [Fact]
    public void A_provider_is_ordered_before_the_extensions_that_call_it()
    {
        var nodes = new[]
        {
            N("achievements", new[] { "achievements" }, "wallet", "database"),
            N("shop", new[] { "shop" }, "wallet", "achievements"),
            N("wallet", new[] { "wallet" }, "database"),
        };

        var plan = ExoDeployOrder.Plan(nodes, new[] { "database" });

        Assert.Equal(new[] { "wallet", "achievements", "shop" }, plan.Order);
        Assert.True(plan.IsClean);
        Assert.Empty(ExoDeployOrder.Verify(plan.Order, nodes));
    }

    [Fact]
    public void Independent_extensions_keep_a_stable_name_order()
    {
        var plan = ExoDeployOrder.Plan(new[] { N("b", new[] { "b" }), N("a", new[] { "a" }), N("c", new[] { "c" }) });
        Assert.Equal(new[] { "a", "b", "c" }, plan.Order);
    }

    [Fact]
    public void A_service_nobody_provides_is_reported_only_when_the_server_list_is_known()
    {
        var nodes = new[] { N("shop", new[] { "shop" }, "payments") };

        Assert.True(ExoDeployOrder.Plan(nodes).IsClean);

        var plan = ExoDeployOrder.Plan(nodes, new[] { "database" });
        Assert.Single(plan.Problems);
        Assert.Contains("'payments'", plan.Problems[0]);
        Assert.Equal(new[] { "shop" }, plan.Order);
    }

    [Fact]
    public void A_circle_is_reported_and_every_extension_is_still_listed()
    {
        var nodes = new[] { N("a", new[] { "a" }, "b"), N("b", new[] { "b" }, "a"), N("c", new[] { "c" }) };

        var plan = ExoDeployOrder.Plan(nodes);

        Assert.Equal(new[] { "c", "a", "b" }, plan.Order);
        Assert.Contains(plan.Problems, p => p.Contains("circle"));
    }

    [Fact]
    public void Verify_flags_an_order_that_puts_a_caller_first()
    {
        var nodes = new[] { N("shop", new[] { "shop" }, "wallet"), N("wallet", new[] { "wallet" }) };

        var problems = ExoDeployOrder.Verify(new[] { "shop", "wallet" }, nodes);

        Assert.Single(problems);
        Assert.Contains("'shop' is deployed before 'wallet'", problems[0]);
    }

    [Fact]
    public void Nodes_are_read_from_the_manifests_and_a_missing_manifest_has_no_links()
    {
        string dir = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "exo_order_" + System.Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(System.IO.Path.Combine(dir, "shop"));
        System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "shop", "manifest.json"),
            "{\"provides\":[\"shop\"],\"dependencies\":[\"wallet\",\"database\"]}");
        try
        {
            var nodes = ExoDeployOrder.ReadNodes(dir, new[] { "shop", "fresh" });

            Assert.Equal(new[] { "wallet", "database" }, nodes[0].Dependencies);
            Assert.Empty(nodes[1].Dependencies);
        }
        finally { System.IO.Directory.Delete(dir, true); }
    }
}

public class SampleExtensionsTests
{
    private static string Ext(string root, string name, string provides, params string[] deps)
    {
        string dir = System.IO.Path.Combine(root, name);
        System.IO.Directory.CreateDirectory(dir);
        System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "manifest.json"),
            System.Text.Json.JsonSerializer.Serialize(new { provides = new[] { provides }, dependencies = deps }));
        return dir;
    }

    [Fact]
    public void Included_extensions_are_the_directory_minus_the_excluded_ones()
    {
        string root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "exo-incl-" + System.Guid.NewGuid().ToString("N"));
        try
        {
            Ext(System.IO.Path.Combine(root, "extensions"), "wallet", "wallet");
            Ext(System.IO.Path.Combine(root, "extensions"), "shop", "shop", "wallet");
            var ws = new ExoWorkspace(root, new ExoProjectConfig { ExcludedExtensions = new() { "shop" } });

            Assert.Equal(new[] { "wallet" }, ws.IncludedExtensions());
            Assert.True(ws.SetExcluded(new[] { "shop" }, false));
            Assert.Equal(new[] { "shop", "wallet" }, ws.IncludedExtensions());
            Assert.Null(ws.Config.ExcludedExtensions);
            Assert.DoesNotContain("excluded_extensions", System.IO.File.ReadAllText(ws.ConfigPath));
        }
        finally { System.IO.Directory.Delete(root, true); }
    }

    [Fact]
    public void Validation_reports_an_included_extension_that_needs_an_excluded_provider()
    {
        string root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "exo-sample-" + System.Guid.NewGuid().ToString("N"));
        try
        {
            Ext(root, "wallet", "wallet", "database");
            Ext(root, "daily_rewards", "daily_rewards", "wallet", "auth");
            Ext(root, "unrelated", "unrelated");
            var all = new[] { "wallet", "daily_rewards", "unrelated" };

            var problems = ExoDeployOrder.ValidateIncluded(root, all, new[] { "wallet" });
            Assert.Equal(new[] { "daily_rewards needs wallet, which is excluded" }, problems);

            Assert.Empty(ExoDeployOrder.ValidateIncluded(root, all, new[] { "wallet", "daily_rewards" }));
            Assert.Empty(ExoDeployOrder.ValidateIncluded(root, all, System.Array.Empty<string>()));
        }
        finally { System.IO.Directory.Delete(root, true); }
    }

    [Fact]
    public void Validation_falls_back_to_the_name_for_an_extension_not_built_yet()
    {
        string root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "exo-sample-" + System.Guid.NewGuid().ToString("N"));
        try
        {
            System.IO.Directory.CreateDirectory(System.IO.Path.Combine(root, "wallet"));
            Ext(root, "shop", "shop", "wallet");

            Assert.Single(ExoDeployOrder.ValidateIncluded(root, new[] { "wallet", "shop" }, new[] { "wallet" }));
        }
        finally { System.IO.Directory.Delete(root, true); }
    }

    [Fact]
    public void Config_round_trips_the_excluded_list_and_omits_it_when_empty()
    {
        var config = System.Text.Json.JsonSerializer.Deserialize<ExoProjectConfig>("{\"excluded_extensions\":[\"a\",\"b\"]}")!;
        Assert.Equal(new[] { "a", "b" }, config.ExcludedExtensions);
        Assert.DoesNotContain("excluded_extensions", System.Text.Json.JsonSerializer.Serialize(new ExoProjectConfig()));
    }
}
