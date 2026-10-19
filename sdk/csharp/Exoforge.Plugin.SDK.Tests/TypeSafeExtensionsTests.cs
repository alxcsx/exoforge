using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

// Test entity with [ExoResource] and [PrimaryKey]
[ExoResource("custom_scores", PrimaryKey = "PlayerId")]
public record TestScore
{
    [PrimaryKey]
    public string PlayerId { get; init; } = "";
    public int Score { get; init; }
}

// Test entity using conventions (Table = test_item, PK = Id)
public record TestItem
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
}

// Test entity with {Type}Id convention
public record TestProduct
{
    public int TestProductId { get; init; }
    public decimal Price { get; init; }
}

// Test event with [ExoEvent]
[ExoEvent("player_scored", Topic = "gameplay:events")]
public record PlayerScoredEvent(string PlayerId, int Score);

// Test event with [ExoEvent] using inferred name and custom topic
[ExoEvent(Topic = "gameplay:player")]
public record PlayerRespawned(string PlayerId);

// Test event using convention (EventName = user_joined)
public record UserJoined(string UserId);

// Test request with [ExoAction]
[ExoAction("login", Service = "auth")]
public record LoginRequest(string Username, string Password);

public class TypeSafeExtensionsTests
{
    private class MockDatabase : IDatabase
    {
        public readonly Dictionary<(string table, string key), object> Storage = new();

        public T? Get<T>(string table, string key)
        {
            if (Storage.TryGetValue((table, key), out var val))
            {
                return (T)val;
            }
            return default;
        }

        public IReadOnlyList<T> All<T>(string table)
        {
            var list = new List<T>();
            foreach (var kvp in Storage)
            {
                if (kvp.Key.table == table)
                {
                    list.Add((T)kvp.Value);
                }
            }
            return list;
        }

        public void Put<T>(string table, string key, T value)
        {
            Storage[(table, key)] = value!;
        }

        public void Delete(string table, string key)
        {
            Storage.Remove((table, key));
        }

        public IReadOnlyList<T> Query<T>(string sql, params object?[] args) => new List<T>();
        public T? QuerySingle<T>(string sql, params object?[] args) => default;
        public int Execute(string sql, params object?[] args) => 0;
    }

    private class MockEventDispatcher : IEventDispatcher
    {
        public string? LastEvent;
        public object? LastPayload;
        public string? LastTopic;

        public Task EmitAsync<T>(string eventName, T payload, string? topic = null)
        {
            LastEvent = eventName;
            LastPayload = payload;
            LastTopic = topic;
            return Task.CompletedTask;
        }
    }

    private class MockActionDispatcher : IActionDispatcher
    {
        public string? LastService;
        public string? LastAction;
        public object? LastPayload;

        public Task<TResponse?> CallActionAsync<TResponse>(string service, string action, object payload)
        {
            LastService = service;
            LastAction = action;
            LastPayload = payload;
            return Task.FromResult<TResponse?>(default);
        }

        public TResponse? CallAction<TResponse>(string service, string action, object payload)
        {
            LastService = service;
            LastAction = action;
            LastPayload = payload;
            return default;
        }
    }

    [Fact]
    public void DatabaseExtensions_PutAndGet_WithExplicitResource_Works()
    {
        var db = new MockDatabase();
        var score = new TestScore { PlayerId = "player_42", Score = 1000 };

        db.Put(score);

        Assert.True(db.Storage.ContainsKey(("custom_scores", "player_42")));
        var retrieved = db.Get<TestScore>("player_42");
        Assert.NotNull(retrieved);
        Assert.Equal(1000, retrieved!.Score);
    }

    [Fact]
    public void DatabaseExtensions_ConventionTableAndId_Works()
    {
        var db = new MockDatabase();
        var item = new TestItem { Id = "item_1", Name = "Health Potion" };

        db.Put(item);

        Assert.True(db.Storage.ContainsKey(("test_item", "item_1")));
        var retrieved = db.Get<TestItem>("item_1");
        Assert.NotNull(retrieved);
        Assert.Equal("Health Potion", retrieved!.Name);

        var all = db.All<TestItem>();
        Assert.Single(all);

        db.Delete<TestItem>("item_1");
        Assert.Null(db.Get<TestItem>("item_1"));
    }

    [Fact]
    public void DatabaseExtensions_TypedTableAccessor_Works()
    {
        var db = new MockDatabase();
        var table = db.Table<TestProduct>();

        Assert.Equal("test_product", table.TableName);

        var prod = new TestProduct { TestProductId = 99, Price = 19.99m };
        table.Put(prod);

        var retrieved = table.Get(99);
        Assert.NotNull(retrieved);
        Assert.Equal(19.99m, retrieved!.Price);

        table.Delete(prod);
        Assert.Null(table.Get(99));
    }

    [Fact]
    public async Task EventDispatcherExtensions_EmitsWithAttributeMetadata()
    {
        var events = new MockEventDispatcher();
        var evt = new PlayerScoredEvent("p1", 500);

        await events.EmitAsync(evt);

        Assert.Equal("player_scored", events.LastEvent);
        Assert.Equal("gameplay:events", events.LastTopic);
        Assert.Same(evt, events.LastPayload);
    }

    [Fact]
    public async Task EventDispatcherExtensions_EmitsWithInferredNameAndCustomTopic()
    {
        var events = new MockEventDispatcher();
        var evt = new PlayerRespawned("p2");

        await events.EmitAsync(evt);

        Assert.Equal("player_respawned", events.LastEvent);
        Assert.Equal("gameplay:player", events.LastTopic);
        Assert.Same(evt, events.LastPayload);
    }

    [Fact]
    public async Task EventDispatcherExtensions_EmitsWithNamingConvention()
    {
        var events = new MockEventDispatcher();
        var evt = new UserJoined("u_99");

        await events.EmitAsync(evt);

        Assert.Equal("user_joined", events.LastEvent);
        Assert.Null(events.LastTopic);
    }

    [Fact]
    public void ActionDispatcherExtensions_CallsWithInferredServiceAndAction()
    {
        var actions = new MockActionDispatcher();
        var req = new LoginRequest("admin", "secret");

        actions.CallAction<LoginRequest, string>(req);

        Assert.Equal("auth", actions.LastService);
        Assert.Equal("login", actions.LastAction);
        Assert.Same(req, actions.LastPayload);
    }
}
