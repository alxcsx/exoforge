using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Exoforge.Generated;
using Exoforge.Plugin.Generator.Tests.Contracts;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.Generator.Tests;

/// <summary>
/// A declared contract: the interface owns the service name and the action metadata, and the class
/// implementing it is the plugin's root. This is the shape that can be shared with another project.
/// </summary>
[ExoService("contract_ping", Category = "Test", Title = "Contract Ping", Icon = "📡")]
public interface IContractPing
{
    [ExoAction]
    string Ping(string message);
}

/// <summary>
/// A plugin whose actions record what they were called with, so the dispatch is observable. It
/// declares services on itself and implements one declared contract, and it is <c>partial</c> so the
/// generator can add the contracts it declares as interfaces it implements.
/// </summary>
[ExoService("dispatch_sample", Version = "2.0.0", Category = "Test", Title = "Dispatch Sample", Icon = "🧪")]
[ExoService("dispatch_admin", Category = "Test", Title = "Dispatch Admin", Icon = "🛠️")]
public partial class DispatchSamplePlugin : IContractPing, ISharedContract
{
    public int LastLeft { get; private set; }
    public int LastRight { get; private set; }
    public string LastEcho { get; private set; } = "";
    public int LastDoubled { get; private set; }
    public int LastStored { get; private set; }
    public string LastEvent { get; private set; } = "";
    public string LastPing { get; private set; } = "";
    public string LastGreeting { get; private set; } = "";

    [ExoAction]
    public int Add(int left, int right = 10)
    {
        LastLeft = left;
        LastRight = right;
        return left + right;
    }

    [ExoAction("echo")]
    public string Echo(string value)
    {
        LastEcho = value;
        return value;
    }

    [ExoAction]
    public async Task<int> Doubled(int value)
    {
        await Task.Yield();
        LastDoubled = value;
        return value * 2;
    }

    [ExoAction]
    [ExoEvent("value_changed", typeof(ValueChanged), Topic = "test:events")]
    public int Store(int value)
    {
        LastStored = value;
        return value;
    }

    [ExoAction("wipe", Service = "dispatch_admin")]
    public bool Wipe() => true;

    [ExoWebhook("stripe_webhook")]
    public string HandleStripe(string body, Dictionary<string, string>? headers = null)
    {
        return $"handled:{body}:{(headers != null && headers.ContainsKey("sig") ? headers["sig"] : "")}";
    }

    [ExoAction]
    public List<ScoreRow> TopScores(int limit) => new();

    [ExoAction]
    public ScoreRow Best(string playerId) => new();

    public string Ping(string message)
    {
        LastPing = message;
        return "pong:" + message;
    }

    public string Greet(string name)
    {
        LastGreeting = name;
        return "hello " + name;
    }

    public void OnEvent(string name, ValueChanged payload) => LastEvent = $"{name}:{payload.Value}";
}

public record ValueChanged
{
    public int Value { get; init; }
}

/// <summary>A column's type is not the only place an enum reaches JSON.</summary>
public enum ScoreTier
{
    Bronze,
    Silver,
    Gold
}

public record ScoreRow
{
    public string PlayerId { get; init; } = "";
    public int Score { get; init; }
    public ScoreTier Tier { get; init; } = ScoreTier.Bronze;
}

/// <summary>
/// The generator emits <c>Exoforge.Generated.ExoforgeDispatch</c> for this assembly, and the host
/// uses it in place of reflecting over the plugin's methods.
/// </summary>
public class DispatchTests
{
    [Fact]
    public void Generated_dispatch_binds_arguments_applies_defaults_and_handles_events()
    {
        var plugin = new DispatchSamplePlugin();

        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"add\",\"payload\":{\"left\":5}}",
            "{\"type\":\"action\",\"id\":2,\"action\":\"echo\",\"payload\":{\"value\":\"hi\"}}",
            "{\"type\":\"action\",\"id\":3,\"action\":\"doubled\",\"payload\":{\"value\":21}}",
            "{\"type\":\"action\",\"id\":4,\"action\":\"store\",\"payload\":{\"value\":7}}",
            "{\"type\":\"event\",\"event\":\"value_changed\",\"payload\":{\"value\":7}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input, new ExoforgeDispatch());

        Assert.Equal(5, plugin.LastLeft);

        // `right` was absent from the payload, so the declared default applies.
        Assert.Equal(10, plugin.LastRight);
        Assert.Equal("hi", plugin.LastEcho);
        Assert.Equal(21, plugin.LastDoubled);
        Assert.Equal(7, plugin.LastStored);
        Assert.Equal("value_changed:7", plugin.LastEvent);
    }

    [Fact]
    public void Generated_dispatch_reports_an_unknown_action_rather_than_throwing()
    {
        var plugin = new DispatchSamplePlugin();

        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"not_an_action\",\"payload\":{}}",
            "{\"type\":\"action\",\"id\":2,\"action\":\"store\",\"payload\":{\"value\":3}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input, new ExoforgeDispatch());

        // The unknown action is skipped and the loop keeps going.
        Assert.Equal(3, plugin.LastStored);
    }

    /// <summary>
    /// Locates the manifest the generator wrote during this project's compile. Walking up rather
    /// than hard-coding a relative path keeps it working when the target framework or configuration
    /// changes.
    /// </summary>
    private static string ManifestPath()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
        {
            string candidate = Path.Combine(dir.FullName, "obj", "Exoforge", "manifest.json");
            if (File.Exists(candidate)) return candidate;
        }

        throw new FileNotFoundException("the generated manifest was not found above " + AppContext.BaseDirectory);
    }

    /// <summary>The generated manifest, parsed.</summary>
    private static JsonNode Manifest() => JsonNode.Parse(File.ReadAllText(ManifestPath()))!;

    /// <summary>One service by name.</summary>
    private static JsonNode Service(JsonNode manifest, string name) =>
        manifest["services"]!.AsArray().First(s => s!["name"]!.GetValue<string>() == name)!;

    private static string[] ActionNames(JsonNode service) =>
        service["actions"]!.AsArray().Select(a => a!["name"]!.GetValue<string>()).ToArray();

    /// <summary>
    /// A plugin may provide more than one service, the way an Elixir plugin does with
    /// <c>provides: [ContractA, ContractB]</c>. Each action is declared under the service it names.
    /// </summary>
    [Fact]
    public void A_plugin_can_provide_more_than_one_service()
    {
        JsonNode manifest = Manifest();

        string[] leaderboard = ActionNames(Service(manifest, "dispatch_sample"));
        string[] admin = ActionNames(Service(manifest, "dispatch_admin"));

        Assert.Contains("add", leaderboard);
        Assert.DoesNotContain("wipe", leaderboard);

        Assert.Contains("wipe", admin);
        Assert.DoesNotContain("add", admin);
    }

    /// <summary>
    /// A declared contract contributes a service entry from the interface, and its actions are served
    /// by the implementing class.
    /// </summary>
    [Fact]
    public void A_declared_contract_interface_contributes_a_service()
    {
        JsonNode ping = Service(Manifest(), "contract_ping");

        Assert.Contains("ping", ActionNames(ping));
        Assert.Equal("string", ping["actions"]!.AsArray()[0]!["params"]!["message"]!.GetValue<string>());
    }

    [Fact]
    public void The_dispatch_serves_an_action_declared_on_an_interface()
    {
        var plugin = new DispatchSamplePlugin();

        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"ping\",\"payload\":{\"message\":\"hi\"}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input, new ExoforgeDispatch());

        Assert.Equal("hi", plugin.LastPing);
    }

    /// <summary>
    /// A class that declares a service is its own contract, so the generator emits one and - because
    /// the class is partial - makes the class implement it. Compiling this is the assertion.
    /// </summary>
    [Fact]
    public void A_class_declared_service_gets_a_generated_contract_it_implements()
    {
        var plugin = new DispatchSamplePlugin();

        Assert.IsAssignableFrom<Exoforge.Generated.Contracts.IDispatchSample>(plugin);
        Assert.IsAssignableFrom<Exoforge.Generated.Contracts.IDispatchAdmin>(plugin);
        Assert.IsAssignableFrom<IContractPing>(plugin);
    }

    /// <summary>
    /// A contract declared in a referenced assembly is discovered too - that is what makes a shared
    /// contracts package possible. Nothing in the plugin's own source names the service.
    /// </summary>
    [Fact]
    public void A_contract_from_a_referenced_assembly_contributes_a_service()
    {
        JsonNode shared = Service(Manifest(), "shared_contract");

        Assert.Contains("greet", ActionNames(shared));
        Assert.Equal("string", shared["actions"]!.AsArray()[0]!["params"]!["name"]!.GetValue<string>());
    }

    [Fact]
    public void The_dispatch_serves_an_action_from_a_referenced_contract()
    {
        var plugin = new DispatchSamplePlugin();

        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"greet\",\"payload\":{\"name\":\"Ada\"}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input, new ExoforgeDispatch());

        Assert.Equal("Ada", plugin.LastGreeting);
    }

    /// <summary>
    /// A record return is described by its fields, not collapsed to `:map`, so a generated client can
    /// offer a typed response instead of `JsonElement`. A list says so, and names the record so the
    /// client's model matches the plugin's own type.
    /// </summary>
    [Fact]
    public void A_record_return_carries_its_fields_and_type_name()
    {
        JsonNode manifest = Manifest();

        var actions = manifest["services"]!.AsArray()
            .SelectMany(s => s!["actions"]!.AsArray())
            .ToList();

        JsonNode listed = actions.First(a => a!["returns_list"]!.GetValue<bool>())!;

        // The type name is fully qualified so the generated JSON context can resolve it.
        Assert.StartsWith("global::", listed["returns_type"]!.GetValue<string>());
        Assert.EndsWith("ScoreRow", listed["returns_type"]!.GetValue<string>());

        // A record is described by its fields, not collapsed to a single type.
        Assert.Equal("string", listed["returns"]!["player_id"]!.GetValue<string>());
        Assert.Equal("integer", listed["returns"]!["score"]!.GetValue<string>());

        // A scalar stays a scalar.
        Assert.Contains(actions, a => a!["returns"]!.GetValue<string>() == "string");
    }

    [Fact]
    public void Manifest_Includes_Webhook_With_Webhook_Transport_And_Scope()
    {
        JsonNode manifest = Manifest();
        var actions = Service(manifest, "dispatch_sample")["actions"]!.AsArray();
        var webhook = actions.FirstOrDefault(a => a?["name"]?.GetValue<string>() == "stripe_webhook");

        Assert.NotNull(webhook);
        Assert.Equal("webhook", webhook!["transport"]?.GetValue<string>());
        Assert.Equal("webhook", webhook!["scope"]?.GetValue<string>());
    }

    [Fact]
    public void The_dispatch_serves_a_webhook()
    {
        var plugin = new DispatchSamplePlugin();

        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"stripe_webhook\",\"payload\":{\"body\":\"raw_data\",\"headers\":{\"sig\":\"xyz\"}}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input, new ExoforgeDispatch());
    }
}
