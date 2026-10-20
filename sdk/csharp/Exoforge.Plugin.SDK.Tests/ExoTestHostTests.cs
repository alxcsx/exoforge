using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

public class TestPlayerProfile
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public int Score { get; set; }
}

public class SampleGameExtension
{
    public IDatabase? Database { get; set; }
    public ILogger? Logger { get; set; }
    public IEventDispatcher? Events { get; set; }
    public IActionDispatcher? Actions { get; set; }

    public void RecordScore(string playerId, int score)
    {
        Logger?.Info($"Recording score {score} for {playerId}");
        Database?.Put("scores", playerId, new TestPlayerProfile { Id = playerId, Score = score });
        _ = Events?.EmitAsync("score_updated", new { player_id = playerId, score = score }, "game:scores");
    }

    public async Task<string> FetchExternalTierAsync(string playerId)
    {
        var tier = await Actions!.CallActionAsync<string>("ranking", "get_tier", new { player_id = playerId });
        return tier ?? "bronze";
    }
}

public class ExoTestHostTests
{
    [Fact]
    public void TestHost_Provides_Zero_Config_Unit_Testing()
    {
        using var test = ExoTestHost.Start("snake_game");

        var extension = test.Create<SampleGameExtension>();
        Assert.NotNull(extension.Database);
        Assert.NotNull(extension.Logger);
        Assert.NotNull(extension.Events);
        Assert.NotNull(extension.Actions);

        extension.RecordScore("player_1", 100);

        // Assert Database KV
        var saved = test.Database.Get<TestPlayerProfile>("scores", "player_1");
        Assert.NotNull(saved);
        Assert.Equal("player_1", saved!.Id);
        Assert.Equal(100, saved.Score);

        // Assert Logger
        Assert.True(test.Logger.HasLogged("Recording score 100 for player_1"));

        // Assert Event Dispatcher
        Assert.True(test.Events.HasEmitted("score_updated", "game:scores"));
        Assert.Single(test.Events.EmittedEvents);
    }

    [Fact]
    public async Task TestHost_Mocks_External_Action_Calls()
    {
        using var test = ExoTestHost.Start("snake_game");

        test.Actions.Register("ranking", "get_tier", _ => "diamond");

        var extension = test.Create<SampleGameExtension>();
        string tier = await extension.FetchExternalTierAsync("player_99");

        Assert.Equal("diamond", tier);
        Assert.Single(test.Actions.Calls);
        Assert.Equal("ranking", test.Actions.Calls[0].Service);
        Assert.Equal("get_tier", test.Actions.Calls[0].Action);
    }

    [Fact]
    public void InMemoryDatabase_Supports_All_And_Delete()
    {
        var db = new InMemoryDatabase();
        db.Put("items", "item_1", new { name = "Sword" });
        db.Put("items", "item_2", new { name = "Shield" });
        db.Put("other", "x", new { name = "Other" });

        Assert.Equal(2, db.Count("items"));
        Assert.Equal(3, db.Entries.Count);

        db.Delete("items", "item_1");
        Assert.Null(db.Get<object>("items", "item_1"));
        Assert.Equal(1, db.Count("items"));

        db.Clear();
        Assert.Empty(db.Entries);
    }
}
