using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Exoforge.Client.Time;

/// <summary>
/// Represents a standardized LiveOps schedule or seasonal time window.
/// Provides client-side active window evaluation, countdown formatting, and progress tracking.
/// </summary>
public class ExoTimeWindow
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("start_at")]
    public string StartAtString { get; set; } = "";

    [JsonPropertyName("end_at")]
    public string EndAtString { get; set; } = "";

    [JsonPropertyName("recurrence")]
    public string Recurrence { get; set; } = "none";

    [JsonPropertyName("timezone")]
    public string Timezone { get; set; } = "Etc/UTC";

    [JsonPropertyName("status")]
    public string Status { get; set; } = "upcoming";

    [JsonPropertyName("is_active")]
    public bool IsActive { get; set; }

    [JsonPropertyName("remaining_seconds")]
    public long RemainingSeconds { get; set; }

    [JsonPropertyName("countdown_text")]
    public string CountdownText { get; set; } = "0s";

    [JsonPropertyName("progress")]
    public double Progress { get; set; }

    [JsonPropertyName("metadata")]
    public Dictionary<string, JsonElement> Metadata { get; set; } = new();

    [JsonIgnore]
    public DateTime? StartAtUtc
    {
        get => DateTime.TryParse(StartAtString, null, System.Globalization.DateTimeStyles.RoundtripKind, out var dt) ? dt.ToUniversalTime() : null;
        set => StartAtString = value?.ToUniversalTime().ToString("O") ?? "";
    }

    [JsonIgnore]
    public DateTime? EndAtUtc
    {
        get => DateTime.TryParse(EndAtString, null, System.Globalization.DateTimeStyles.RoundtripKind, out var dt) ? dt.ToUniversalTime() : null;
        set => EndAtString = value?.ToUniversalTime().ToString("O") ?? "";
    }

    /// <summary>
    /// Evaluates if this time window is currently active at the specified time (defaults to DateTime.UtcNow).
    /// </summary>
    public bool EvaluateIsActive(DateTime? nowUtc = null)
    {
        DateTime now = (nowUtc ?? DateTime.UtcNow).ToUniversalTime();
        if (StartAtUtc == null || EndAtUtc == null) return false;

        if (Recurrence == "none" || string.IsNullOrEmpty(Recurrence))
        {
            return now >= StartAtUtc.Value && now < EndAtUtc.Value;
        }

        if (Recurrence == "daily")
        {
            if (now < StartAtUtc.Value) return false;
            TimeSpan startTod = StartAtUtc.Value.TimeOfDay;
            TimeSpan endTod = EndAtUtc.Value.TimeOfDay;
            TimeSpan nowTod = now.TimeOfDay;

            if (endTod >= startTod)
            {
                return nowTod >= startTod && nowTod < endTod;
            }
            return nowTod >= startTod || nowTod < endTod;
        }

        return now >= StartAtUtc.Value && now < EndAtUtc.Value;
    }

    /// <summary>
    /// Computes the remaining duration formatted as a concise string (e.g., "1d 4h", "2h 15m", "45s").
    /// </summary>
    public static string FormatCountdown(long totalSeconds)
    {
        if (totalSeconds <= 0) return "0s";

        long days = totalSeconds / 86400;
        long remDay = totalSeconds % 86400;
        long hours = remDay / 3600;
        long remHour = remDay % 3600;
        long minutes = remHour / 60;
        long secs = remHour % 60;

        if (days > 0) return $"{days}d {hours}h";
        if (hours > 0) return $"{hours}h {minutes}m";
        if (minutes > 0) return $"{minutes}m {secs}s";
        return $"{secs}s";
    }

    /// <summary>
    /// Safely gets a typed value from the arbitrary metadata dictionary.
    /// </summary>
    public T? GetMetadataValue<T>(string key, T? defaultValue = default)
    {
        if (Metadata.TryGetValue(key, out var element))
        {
            try
            {
                return JsonSerializer.Deserialize<T>(element.GetRawText());
            }
            catch
            {
                return defaultValue;
            }
        }
        return defaultValue;
    }
}
