using System;
using System.Text.Json;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Exception thrown when an isolated database operation fails on the remote cluster.
/// </summary>
public class ExoDatabaseException : Exception
{
    /// <summary>The name of the database table involved in the operation.</summary>
    public string Table { get; }

    /// <summary>The raw or parsed error returned from the cluster.</summary>
    public string ServerError { get; }

    /// <summary>
    /// Zero-based index of the operation that caused a <c>db_batch</c> transaction to fail and roll back,
    /// or <c>null</c> for single-operation failures.
    /// </summary>
    public int? FailedIndex { get; }

    /// <summary>Alias for <see cref="FailedIndex"/>.</summary>
    public int? Index => FailedIndex;

    public ExoDatabaseException(string table, string serverError)
        : this(table, serverError, failedIndex: null)
    {
    }

    public ExoDatabaseException(string table, string serverError, int? failedIndex)
        : base(FormatMessage(table, serverError, failedIndex))
    {
        Table = table ?? string.Empty;
        ServerError = serverError ?? string.Empty;
        FailedIndex = failedIndex;
    }

    public ExoDatabaseException(string table, string serverError, Exception innerException)
        : base($"Database operation failed on table '{table}': {serverError}", innerException)
    {
        Table = table ?? string.Empty;
        ServerError = serverError ?? string.Empty;
    }

    private static string FormatMessage(string? table, string? serverError, int? failedIndex) =>
        failedIndex.HasValue
            ? $"Database operation failed on table '{table}' at index {failedIndex.Value}: {serverError}"
            : $"Database operation failed on table '{table}': {serverError}";

    internal static void ThrowIfError(string table, string? raw)
    {
        if (string.IsNullOrEmpty(raw)) return;

        if (raw!.StartsWith("{", StringComparison.Ordinal) && raw.Contains("\"ok\":false"))
        {
            int? failedIndex = null;
            string? error = null;

            try
            {
                using var doc = JsonDocument.Parse(raw);
                var root = doc.RootElement;
                if (root.ValueKind != JsonValueKind.Object ||
                    !root.TryGetProperty("ok", out var okProp) ||
                    okProp.ValueKind != JsonValueKind.False)
                {
                    return;
                }

                if (root.TryGetProperty("index", out var rootIdx) &&
                    rootIdx.ValueKind == JsonValueKind.Number &&
                    rootIdx.TryGetInt32(out int rIdx))
                {
                    failedIndex = rIdx;
                }

                if (root.TryGetProperty("error", out var errProp))
                {
                    if (errProp.ValueKind == JsonValueKind.Object &&
                        errProp.TryGetProperty("index", out var errIdx) &&
                        errIdx.ValueKind == JsonValueKind.Number &&
                        errIdx.TryGetInt32(out int eIdx))
                    {
                        failedIndex = eIdx;
                    }

                    error = errProp.ValueKind == JsonValueKind.String
                        ? errProp.GetString()!
                        : errProp.GetRawText();
                }
                else
                {
                    error = raw;
                }
            }
            catch (JsonException)
            {
                return;
            }

            throw new ExoDatabaseException(table, error, failedIndex);
        }
    }
}
