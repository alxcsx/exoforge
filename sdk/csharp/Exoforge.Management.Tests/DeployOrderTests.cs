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
