using System;
using System.Collections.Generic;
using System.Reflection;

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
/// <see cref="PrimaryKeyAttribute"/>, or standard conventions.
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
        // a) Look for [PrimaryKey]
        foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (prop.GetCustomAttribute<PrimaryKeyAttribute>() != null)
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
                if (field.GetCustomAttribute<PrimaryKeyAttribute>() != null)
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
                $"Mark a property with [PrimaryKey], [ExoResource(PrimaryKey = \"...\")], or name it 'Id' or '{typeof(T).Name}Id'.");
        }

        if (val == null)
        {
            if (IsSingleton) return "singleton";
            throw new InvalidOperationException($"Primary key value for entity of type '{typeof(T).FullName}' is null.");
        }

        return val.ToString()!;
    }
}
