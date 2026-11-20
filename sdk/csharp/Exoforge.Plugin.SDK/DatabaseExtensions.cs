using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using System.Text;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Strongly-typed table repository for entity <typeparamref name="T"/>.
/// Encapsulates table name resolution and primary key extraction.
/// </summary>
public interface IDatabaseTable<T>
{
    /// <summary>The resolved SQL table name for <typeparamref name="T"/>.</summary>
    string TableName { get; }

    /// <summary>Reads an entity by primary key.</summary>
    T? Get(string id);

    /// <summary>Reads an entity by primary key (supports numeric/guid keys).</summary>
    T? Get(object id);

    /// <summary>Reads the first record in the table, or default if empty.</summary>
    T? First();

    /// <summary>Reads all entities in the table.</summary>
    IReadOnlyList<T> All();

    /// <summary>Puts (inserts or upserts) an entity, extracting the primary key automatically.</summary>
    void Put(T entity);

    /// <summary>Puts (inserts or upserts) an entity with an explicit primary key.</summary>
    void Put(string id, T entity);

    /// <summary>Deletes an entity by primary key.</summary>
    void Delete(string id);

    /// <summary>Deletes an entity by extracting its primary key.</summary>
    void Delete(T entity);

    /// <summary>Runs a query and maps rows to <typeparamref name="T"/>.</summary>
    IReadOnlyList<T> Query(string sql, params object?[] args);

    /// <summary>Runs a query and maps the first row to <typeparamref name="T"/>.</summary>
    T? QuerySingle(string sql, params object?[] args);
}

/// <summary>
/// Type-safe extension methods for <see cref="IDatabase"/> to reduce magic strings.
/// Resolves table names and primary keys using <see cref="ExoResourceAttribute"/>,
/// <see cref="ExoColumnAttribute.PrimaryKey"/>, or standard conventions.
/// </summary>
public static class DatabaseExtensions
{
    /// <summary>
    /// Reads the first record of type <typeparamref name="T"/> from its default table,
    /// or <c>default</c> if the table is empty. Particularly useful for singleton resources.
    /// </summary>
    public static T? First<T>(this IDatabase db)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        var all = db.All<T>(EntityMetadata<T>.TableName);
        return all.Count > 0 ? all[0] : default;
    }

    /// <summary>
    /// Reads the first or singleton record of type <typeparamref name="T"/> from its default table,
    /// or <c>default</c> if the table is empty. Alias for <see cref="First{T}(IDatabase)"/>.
    /// </summary>
    public static T? Get<T>(this IDatabase db) => db.First<T>();

    /// <summary>
    /// Reads a record of type <typeparamref name="T"/> by primary key from its default table.
    /// </summary>
    public static T? Get<T>(this IDatabase db, string id)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        return db.Get<T>(EntityMetadata<T>.TableName, id);
    }

    /// <summary>
    /// Reads a record of type <typeparamref name="T"/> by numeric or guid primary key.
    /// </summary>
    public static T? Get<T>(this IDatabase db, object id)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        if (id == null) throw new ArgumentNullException(nameof(id));
        return db.Get<T>(EntityMetadata<T>.TableName, id.ToString()!);
    }

    /// <summary>
    /// Reads all records of type <typeparamref name="T"/> from its default table.
    /// </summary>
    public static IReadOnlyList<T> All<T>(this IDatabase db)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        return db.All<T>(EntityMetadata<T>.TableName);
    }

    /// <summary>
    /// Writes or updates an entity, resolving the table name and primary key automatically.
    /// </summary>
    public static void Put<T>(this IDatabase db, T entity)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        string key = EntityMetadata<T>.GetKey(entity);
        db.Put(EntityMetadata<T>.TableName, key, entity);
    }

    /// <summary>
    /// Writes or updates an entity with an explicit primary key, resolving the table name automatically.
    /// </summary>
    public static void Put<T>(this IDatabase db, string key, T entity)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        db.Put(EntityMetadata<T>.TableName, key, entity);
    }

    /// <summary>
    /// Writes or updates an entity with an explicit primary key (numeric/guid), resolving the table name automatically.
    /// </summary>
    public static void Put<T>(this IDatabase db, object key, T entity)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        if (key == null) throw new ArgumentNullException(nameof(key));
        db.Put(EntityMetadata<T>.TableName, key.ToString()!, entity);
    }

    /// <summary>
    /// Deletes a record of type <typeparamref name="T"/> by primary key.
    /// </summary>
    public static void Delete<T>(this IDatabase db, string id)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        db.Delete(EntityMetadata<T>.TableName, id);
    }

    /// <summary>
    /// Deletes an entity by extracting its primary key automatically.
    /// </summary>
    public static void Delete<T>(this IDatabase db, T entity)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        string key = EntityMetadata<T>.GetKey(entity);
        db.Delete(EntityMetadata<T>.TableName, key);
    }

    /// <summary>
    /// Obtains a type-safe table accessor / repository for <typeparamref name="T"/>.
    /// </summary>
    public static IDatabaseTable<T> Table<T>(this IDatabase db)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        return new DatabaseTable<T>(db);
    }

    /// <summary>
    /// Resolves the SQL table name for entity type <typeparamref name="T"/>.
    /// </summary>
    public static string TableName<T>() => EntityMetadata<T>.TableName;

    /// <summary>
    /// For a resource that forks on breaking changes: copies the rows only an older generation has into the
    /// caller's generation. Call it from a studio action when a new generation should start as a copy.
    /// </summary>
    public static int DuplicateGeneration<T>(this IDatabase db) =>
        db is HostDatabase host ? host.DuplicateGeneration<T>() : throw new NotSupportedException("Generations need the host database.");

    /// <summary>
    /// Copies the named properties (the columns two generations share) from the older generation's row into the
    /// caller's generation row, for every row both have. Returns how many rows changed.
    /// </summary>
    public static int SyncGeneration<T>(this IDatabase db, params string[] properties) =>
        db is HostDatabase host ? host.SyncGeneration<T>(properties) : throw new NotSupportedException("Generations need the host database.");

    /// <summary>
    /// <c>Query&lt;T&gt;</c> that returns rows as stored: no row migration and no <c>client_outdated</c> check.
    /// For a hot path that must not pay for either.
    /// </summary>
    public static IReadOnlyList<T> QueryRaw<T>(this IDatabase db, string sql, params object?[] args)
    {
        using (RowMigrations.Suppress()) return db.Query<T>(sql, args);
    }

    /// <summary>
    /// Runs an interpolated SQL query, turning each interpolation into a positional parameter
    /// (<c>$1</c>, <c>$2</c>, ...) passed as arguments to <see cref="IDatabase.Query{T}"/>.
    /// Only the format string's literal segments become SQL text, so interpolated values are never
    /// concatenated into SQL. Format specifiers and alignment clauses (e.g. <c>{v:F2}</c>,
    /// <c>{v,-10}</c>) are ignored and raw values are passed as parameters.
    /// </summary>
    public static IReadOnlyList<T> QuerySql<T>(this IDatabase db, FormattableString sql)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        if (sql == null) throw new ArgumentNullException(nameof(sql));

        var (text, args) = Parameterize(sql);
        return db.Query<T>(text, args);
    }

    /// <summary>
    /// Runs an interpolated SQL statement (INSERT/UPDATE/DELETE), turning each interpolation into
    /// a positional parameter (<c>$1</c>, <c>$2</c>, ...) passed as arguments to
    /// <see cref="IDatabase.Execute"/>. Only the format string's literal segments become SQL text,
    /// so interpolated values are never concatenated into SQL. Format specifiers and alignment
    /// clauses (e.g. <c>{v:F2}</c>, <c>{v,-10}</c>) are ignored and raw values are passed as
    /// parameters.
    /// </summary>
    public static int ExecuteSql(this IDatabase db, FormattableString sql)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        if (sql == null) throw new ArgumentNullException(nameof(sql));

        var (text, args) = Parameterize(sql);
        return db.Execute(text, args);
    }

    /// <summary>
    /// Records an interpolated SQL statement (INSERT/UPDATE/DELETE) in <paramref name="tx"/>,
    /// turning each interpolation into a positional parameter (<c>$1</c>, <c>$2</c>, ...) passed as
    /// arguments to <see cref="ITransaction.Execute"/>. Only the format string's literal segments
    /// become SQL text, so interpolated values are never concatenated into SQL.
    /// </summary>
    public static void ExecuteSql(this ITransaction tx, FormattableString sql)
    {
        if (tx == null) throw new ArgumentNullException(nameof(tx));
        if (sql == null) throw new ArgumentNullException(nameof(sql));

        var (text, args) = Parameterize(sql);
        tx.Execute(text, args);
    }

    /// <summary>
    /// Records an entity write (upsert) in <paramref name="tx"/>, resolving the table name and primary key automatically.
    /// </summary>
    public static void Put<T>(this ITransaction tx, T entity)
    {
        if (tx == null) throw new ArgumentNullException(nameof(tx));
        string key = EntityMetadata<T>.GetKey(entity);
        tx.Put(EntityMetadata<T>.TableName, key, entity);
    }

    /// <summary>
    /// Records an entity write (upsert) with an explicit primary key in <paramref name="tx"/>, resolving the table name automatically.
    /// </summary>
    public static void Put<T>(this ITransaction tx, string key, T entity)
    {
        if (tx == null) throw new ArgumentNullException(nameof(tx));
        tx.Put(EntityMetadata<T>.TableName, key, entity);
    }

    /// <summary>
    /// Records an entity write (upsert) with an explicit numeric/guid primary key in <paramref name="tx"/>, resolving the table name automatically.
    /// </summary>
    public static void Put<T>(this ITransaction tx, object key, T entity)
    {
        if (tx == null) throw new ArgumentNullException(nameof(tx));
        if (key == null) throw new ArgumentNullException(nameof(key));
        tx.Put(EntityMetadata<T>.TableName, key.ToString()!, entity);
    }

    /// <summary>
    /// Records a delete of a record of type <typeparamref name="T"/> by primary key in <paramref name="tx"/>.
    /// </summary>
    public static void Delete<T>(this ITransaction tx, string id)
    {
        if (tx == null) throw new ArgumentNullException(nameof(tx));
        tx.Delete(EntityMetadata<T>.TableName, id);
    }

    /// <summary>
    /// Records a delete of an entity in <paramref name="tx"/> by extracting its primary key automatically.
    /// </summary>
    public static void Delete<T>(this ITransaction tx, T entity)
    {
        if (tx == null) throw new ArgumentNullException(nameof(tx));
        string key = EntityMetadata<T>.GetKey(entity);
        tx.Delete(EntityMetadata<T>.TableName, key);
    }

    /// <summary>
    /// Executes an ordered sequence of interpolated SQL write statements atomically in a single
    /// <c>db_batch</c> round trip. Each interpolation is turned into a positional parameter
    /// (<c>$1</c>, <c>$2</c>, ...) and never concatenated into SQL.
    /// </summary>
    public static void ExecuteBatch(this IDatabase db, IEnumerable<FormattableString> statements)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        if (statements == null) throw new ArgumentNullException(nameof(statements));

        var ops = new List<DbBatchOperation>();
        foreach (var stmt in statements)
        {
            if (stmt == null) throw new ArgumentException("Batch statements cannot contain null elements.", nameof(statements));
            ops.Add(DbBatchOperation.ExecuteSql(stmt));
        }

        db.ExecuteBatch(ops);
    }

    /// <summary>
    /// Executes an ordered sequence of parameterized SQL write statements (<c>Sql, Args</c>)
    /// atomically in a single <c>db_batch</c> round trip.
    /// </summary>
    public static void ExecuteBatch(this IDatabase db, IEnumerable<(string Sql, object?[]? Args)> statements)
    {
        if (db == null) throw new ArgumentNullException(nameof(db));
        if (statements == null) throw new ArgumentNullException(nameof(statements));

        var ops = new List<DbBatchOperation>();
        foreach (var (sql, args) in statements)
        {
            if (sql == null) throw new ArgumentException("Batch SQL statement cannot be null.", nameof(statements));
            ops.Add(DbBatchOperation.Execute(sql, args ?? Array.Empty<object?>()));
        }

        db.ExecuteBatch(ops);
    }

    internal static (string Sql, object?[] Args) Parameterize(FormattableString sql)
    {
        string format = sql.Format ?? throw new FormatException("SQL format string cannot be null.");
        object?[] rawArgs = sql.GetArguments();

        var sb = new StringBuilder(format.Length + rawArgs.Length * 2);
        List<object?>? boundArgs = null;

        int i = 0;
        int len = format.Length;

        while (i < len)
        {
            char c = format[i];
            if (c == '{')
            {
                if (i + 1 < len && format[i + 1] == '{')
                {
                    sb.Append('{');
                    i += 2;
                    continue;
                }

                i++; // skip '{'
                int indexStart = i;
                while (i < len && format[i] >= '0' && format[i] <= '9')
                {
                    i++;
                }

                if (i == indexStart || i >= len)
                {
                    throw new FormatException($"Invalid format item at position {indexStart - 1} in SQL format string.");
                }

                if (!int.TryParse(format.Substring(indexStart, i - indexStart), NumberStyles.None, CultureInfo.InvariantCulture, out int argIndex)
                    || argIndex < 0 || argIndex >= rawArgs.Length)
                {
                    throw new FormatException($"Format item index out of range at position {indexStart} in SQL format string.");
                }

                // Ignore optional alignment (,[-]<digits>) and format specifier (:...) until '}'
                while (i < len && format[i] == ' ') i++;

                if (i < len && format[i] == ',')
                {
                    i++;
                    while (i < len && format[i] == ' ') i++;
                    if (i < len && format[i] == '-') i++;
                    int alignStart = i;
                    while (i < len && format[i] >= '0' && format[i] <= '9') i++;
                    if (i == alignStart)
                    {
                        throw new FormatException($"Invalid alignment in format item at position {i} in SQL format string.");
                    }
                    while (i < len && format[i] == ' ') i++;
                }

                if (i < len && format[i] == ':')
                {
                    i++;
                    while (i < len && format[i] != '}') i++;
                }

                if (i >= len || format[i] != '}')
                {
                    throw new FormatException($"Unclosed or invalid format item near position {i} in SQL format string.");
                }

                i++; // skip '}'

                boundArgs ??= new List<object?>(rawArgs.Length);
                boundArgs.Add(rawArgs[argIndex]);
                sb.Append('$').Append(boundArgs.Count.ToString(CultureInfo.InvariantCulture));
            }
            else if (c == '}')
            {
                if (i + 1 < len && format[i + 1] == '}')
                {
                    sb.Append('}');
                    i += 2;
                    continue;
                }

                throw new FormatException($"Unescaped '}}' at position {i} in SQL format string.");
            }
            else
            {
                sb.Append(c);
                i++;
            }
        }

        return (sb.ToString(), boundArgs != null ? boundArgs.ToArray() : Array.Empty<object?>());
    }
}

internal class DatabaseTable<T> : IDatabaseTable<T>
{
    private readonly IDatabase _db;

    public string TableName => EntityMetadata<T>.TableName;

    public DatabaseTable(IDatabase db)
    {
        _db = db;
    }

    public T? Get(string id) => _db.Get<T>(TableName, id);

    public T? Get(object id)
    {
        if (id == null) throw new ArgumentNullException(nameof(id));
        return _db.Get<T>(TableName, id.ToString()!);
    }

    public T? First()
    {
        var all = _db.All<T>(TableName);
        return all.Count > 0 ? all[0] : default;
    }

    public IReadOnlyList<T> All() => _db.All<T>(TableName);

    public void Put(T entity)
    {
        string key = EntityMetadata<T>.GetKey(entity);
        _db.Put(TableName, key, entity);
    }

    public void Put(string id, T entity) => _db.Put(TableName, id, entity);

    public void Delete(string id) => _db.Delete(TableName, id);

    public void Delete(T entity)
    {
        string key = EntityMetadata<T>.GetKey(entity);
        _db.Delete(TableName, key);
    }

    public IReadOnlyList<T> Query(string sql, params object?[] args) => _db.Query<T>(sql, args);

    public T? QuerySingle(string sql, params object?[] args) => _db.QuerySingle<T>(sql, args);
}

internal static class EntityMetadata<T>
{
    public static readonly string TableName;
    public static readonly bool IsSingleton;
    private static readonly PropertyInfo? KeyProp;
    private static readonly FieldInfo? KeyField;

    static EntityMetadata()
    {
        var type = typeof(T);
        var singletonAttr = type.GetCustomAttribute<ExoSingletonResourceAttribute>();
        IsSingleton = singletonAttr != null;

        // 1. Resolve table name from [ExoResource] or convention
        var resAttr = (ExoResourceAttribute?)singletonAttr ?? type.GetCustomAttribute<ExoResourceAttribute>();
        if (resAttr != null && !string.IsNullOrWhiteSpace(resAttr.Source))
        {
            TableName = resAttr.Source!;
        }
        else if (resAttr != null && !string.IsNullOrWhiteSpace(resAttr.Name))
        {
            TableName = resAttr.Name!;
        }
        else
        {
            TableName = ExoNaming.ToSnakeCase(type.Name);
        }

        // 2. Discover primary key property
        // a) Look for [ExoColumn(PrimaryKey = true)]
        foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (prop.GetCustomAttribute<ExoColumnAttribute>()?.PrimaryKey == true)
            {
                KeyProp = prop;
                break;
            }
        }

        // b) Look for resAttr.PrimaryKey name
        if (KeyProp == null && resAttr != null && !string.IsNullOrWhiteSpace(resAttr.PrimaryKey))
        {
            KeyProp = type.GetProperty(resAttr.PrimaryKey, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase);
        }

        // c) Conventions: "Id", "Key", or $"{TypeName}Id"
        if (KeyProp == null)
        {
            KeyProp = type.GetProperty("Id", BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase)
                   ?? type.GetProperty("Key", BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase)
                   ?? type.GetProperty($"{type.Name}Id", BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase);
        }

        // d) Check fields if no property found
        if (KeyProp == null)
        {
            foreach (var field in type.GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                if (field.GetCustomAttribute<ExoColumnAttribute>()?.PrimaryKey == true)
                {
                    KeyField = field;
                    break;
                }
            }

            if (KeyField == null)
            {
                KeyField = type.GetField("Id", BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase)
                        ?? type.GetField("Key", BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase)
                        ?? type.GetField($"{type.Name}Id", BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase);
            }
        }
    }

    public static string GetKey(T entity)
    {
        if (entity == null) throw new ArgumentNullException(nameof(entity));

        object? val = null;
        if (KeyProp != null)
        {
            val = KeyProp.GetValue(entity);
        }
        else if (KeyField != null)
        {
            val = KeyField.GetValue(entity);
        }
        else if (IsSingleton)
        {
            return "singleton";
        }
        else
        {
            throw new InvalidOperationException(
                $"Cannot determine primary key for type '{typeof(T).FullName}'. " +
                $"Mark a property with [ExoColumn(PrimaryKey = true)], [ExoResource(PrimaryKey = \"...\")], or name it 'Id' or '{typeof(T).Name}Id'.");
        }

        if (val == null)
        {
            if (IsSingleton) return "singleton";
            throw new InvalidOperationException($"Primary key value for entity of type '{typeof(T).FullName}' is null.");
        }

        return val.ToString()!;
    }
}

/// <summary>
/// A single write operation (<c>execute</c>, <c>put</c>, or <c>delete</c>) in a batched atomic database transaction.
/// </summary>
public sealed class DbBatchOperation
{
    public string Action { get; }
    public string? Table { get; }
    public string? Key { get; }
    public object? Value { get; }
    public string? ValueJson { get; }
    public string? Sql { get; }
    public object?[]? Args { get; }

    internal DbBatchOperation(
        string action,
        string? table = null,
        string? key = null,
        object? value = null,
        string? valueJson = null,
        string? sql = null,
        object?[]? args = null)
    {
        Action = action;
        Table = table;
        Key = key;
        Value = value;
        ValueJson = valueJson;
        Sql = sql;
        Args = args;
    }

    /// <summary>Creates a parameterized SQL write operation (<c>$1, $2, ...</c>).</summary>
    public static DbBatchOperation Execute(string sql, params object?[] args)
    {
        if (sql == null) throw new ArgumentNullException(nameof(sql));
        return new DbBatchOperation("execute", sql: sql, args: args ?? Array.Empty<object?>());
    }

    /// <summary>Creates a parameterized SQL write operation from an interpolated string (<c>$1, $2, ...</c>).</summary>
    public static DbBatchOperation ExecuteSql(FormattableString sql)
    {
        if (sql == null) throw new ArgumentNullException(nameof(sql));
        var (text, args) = DatabaseExtensions.Parameterize(sql);
        return new DbBatchOperation("execute", sql: text, args: args);
    }

    /// <summary>Creates a key/value write (upsert) operation.</summary>
    public static DbBatchOperation Put<T>(string table, string key, T value)
    {
        if (table == null) throw new ArgumentNullException(nameof(table));
        if (key == null) throw new ArgumentNullException(nameof(key));
        return new DbBatchOperation("put", table: table, key: key, value: value, valueJson: PluginJson.Serialize(value));
    }

    /// <summary>Creates a key/value write (upsert) operation, resolving table name and primary key from <typeparamref name="T"/>.</summary>
    public static DbBatchOperation Put<T>(T entity)
    {
        string key = EntityMetadata<T>.GetKey(entity);
        return Put(EntityMetadata<T>.TableName, key, entity);
    }

    /// <summary>Creates a key/value write (upsert) operation with an explicit key, resolving table name from <typeparamref name="T"/>.</summary>
    public static DbBatchOperation Put<T>(string key, T entity) =>
        Put(EntityMetadata<T>.TableName, key, entity);

    /// <summary>Creates a key/value delete operation.</summary>
    public static DbBatchOperation Delete(string table, string key)
    {
        if (table == null) throw new ArgumentNullException(nameof(table));
        if (key == null) throw new ArgumentNullException(nameof(key));
        return new DbBatchOperation("delete", table: table, key: key);
    }

    /// <summary>Creates a key/value delete operation, resolving table name from <typeparamref name="T"/>.</summary>
    public static DbBatchOperation Delete<T>(string id) =>
        Delete(EntityMetadata<T>.TableName, id);

    /// <summary>Creates a key/value delete operation, resolving table name and primary key from <typeparamref name="T"/>.</summary>
    public static DbBatchOperation Delete<T>(T entity) =>
        Delete(EntityMetadata<T>.TableName, EntityMetadata<T>.GetKey(entity));
}

internal sealed class BatchTransactionRecorder : ITransaction
{
    private readonly List<DbBatchOperation> _operations = new();

    public IReadOnlyList<DbBatchOperation> Operations => _operations;

    public void Put<T>(string table, string key, T value) =>
        _operations.Add(DbBatchOperation.Put(table, key, value));

    public void Delete(string table, string key) =>
        _operations.Add(DbBatchOperation.Delete(table, key));

    public void Execute(string sql, params object?[] args) =>
        _operations.Add(DbBatchOperation.Execute(sql, args));
}
