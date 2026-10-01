using System.Text.Json;
using System.Text.Json.Serialization;

namespace Exoforge.Client;

public class ExoMessage
{
    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;
}

public class ExoActionRequest : ExoMessage
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("service")]
    public string Service { get; set; } = string.Empty;

    [JsonPropertyName("action")]
    public string Action { get; set; } = string.Empty;

    [JsonPropertyName("payload")]
    public object? Payload { get; set; }

    public ExoActionRequest()
    {
        Type = "action";
    }
}

public class ExoActionResult : ExoMessage
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    [JsonPropertyName("data")]
    public JsonElement Data { get; set; }

    [JsonPropertyName("error")]
    public ExoErrorDetails? Error { get; set; }

    public bool IsSuccess => Status == "ok";
}

public class ExoErrorDetails
{
    [JsonPropertyName("code")]
    public string Code { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;
}

public class ExoSubscriptionRequest : ExoMessage
{
    [JsonPropertyName("topic")]
    public string Topic { get; set; } = string.Empty;

    public ExoSubscriptionRequest(string type, string topic)
    {
        Type = type;
        Topic = topic;
    }
}

public class ExoEventFrame : ExoMessage
{
    [JsonPropertyName("event")]
    public string Event { get; set; } = string.Empty;

    [JsonPropertyName("topic")]
    public string Topic { get; set; } = string.Empty;

    [JsonPropertyName("payload")]
    public JsonElement Payload { get; set; }

    /// <summary>
    /// Deserializes the payload to the specified strongly-typed model.
    /// </summary>
    public T? DeserializePayload<T>(JsonSerializerOptions? options = null)
    {
        return JsonSerializer.Deserialize<T>(Payload.GetRawText(), options);
    }
}
