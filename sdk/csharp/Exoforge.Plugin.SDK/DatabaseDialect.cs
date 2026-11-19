namespace Exoforge.Plugin.SDK;

/// <summary>
/// Database dialect advertised by the host in the protocol handshake.
/// </summary>
public enum DatabaseDialect
{
    Unknown,
    Postgres,
    Sqlite
}

/// <summary>
/// Exposes the active database dialect on <see cref="IDatabase"/> without altering the interface contract.
/// </summary>
public static class DatabaseDialectExtensions
{
    extension(IDatabase db)
    {
        /// <summary>
        /// The database dialect backing the current host session, or <see cref="InMemoryDatabase.Dialect"/> in unit tests.
        /// </summary>
        public DatabaseDialect Dialect => db is InMemoryDatabase mem ? mem.Dialect : HostBridge.DatabaseDialect;
    }
}
