using System;

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

    public ExoDatabaseException(string table, string serverError)
        : base($"Database operation failed on table '{table}': {serverError}")
    {
        Table = table ?? string.Empty;
        ServerError = serverError ?? string.Empty;
    }

    public ExoDatabaseException(string table, string serverError, Exception innerException)
        : base($"Database operation failed on table '{table}': {serverError}", innerException)
    {
        Table = table ?? string.Empty;
        ServerError = serverError ?? string.Empty;
    }
}
