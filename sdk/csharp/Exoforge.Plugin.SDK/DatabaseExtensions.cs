using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Linq.Expressions;
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

    /// <summary>Starts a parameterized query filtered by <paramref name="predicate"/>.</summary>
    IDatabaseQuery<T> Where(Expression<Func<T, bool>> predicate);
    IDatabaseQuery<T> Include<TReference>(Expression<Func<T, TReference?>> navigation);

    /// <summary>Starts a query ordered by <paramref name="keySelector"/>.</summary>
    IDatabaseQuery<T> OrderBy<TKey>(Expression<Func<T, TKey>> keySelector);

    /// <summary>Returns the number of rows in this table.</summary>
    long Count();

    /// <summary>Returns whether this table contains at least one row.</summary>
    bool Exists();

    /// <summary>Returns the first row matching <paramref name="predicate"/>, if any.</summary>
    T? FindBy(Expression<Func<T, bool>> predicate);

    /// <summary>Loads a foreign-key target for <paramref name="entity"/>. The key member must have an <see cref="ExoColumnAttribute"/> with References or ReferencesType.</summary>
    TReference? Include<TReference>(T entity, Expression<Func<T, object?>> foreignKey);
}

/// <summary>A composable, parameterized query over a typed database table.</summary>
public interface IDatabaseQuery<T>
{
    IDatabaseQuery<T> Where(Expression<Func<T, bool>> predicate);
    IDatabaseQuery<T> Include<TReference>(Expression<Func<T, TReference?>> navigation);
    IDatabaseQuery<T> OrderBy<TKey>(Expression<Func<T, TKey>> keySelector);
    IDatabaseQuery<T> OrderByDescending<TKey>(Expression<Func<T, TKey>> keySelector);
    IDatabaseQuery<T> Take(int count);
    IDatabaseQuery<T> Skip(int count);
    IReadOnlyList<T> ToList();
    T? First();
    long Count();
    bool Exists();
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

    public IDatabaseQuery<T> Where(Expression<Func<T, bool>> predicate) =>
        new DatabaseQuery<T>(_db).Where(predicate);

    public IDatabaseQuery<T> Include<TReference>(Expression<Func<T, TReference?>> navigation) =>
        new DatabaseQuery<T>(_db).Include(navigation);

    public IDatabaseQuery<T> OrderBy<TKey>(Expression<Func<T, TKey>> keySelector) =>
        new DatabaseQuery<T>(_db).OrderBy(keySelector);

    public long Count() => new DatabaseQuery<T>(_db).Count();

    public bool Exists() => new DatabaseQuery<T>(_db).Exists();

    public T? FindBy(Expression<Func<T, bool>> predicate) => Where(predicate).First();

    public TReference? Include<TReference>(T entity, Expression<Func<T, object?>> foreignKey)
    {
        if (entity == null) throw new ArgumentNullException(nameof(entity));
        if (foreignKey == null) throw new ArgumentNullException(nameof(foreignKey));
        var member = SqlExpression.Member(foreignKey.Body);
        var column = member.GetCustomAttribute<ExoColumnAttribute>();
        if (column == null || (!column.ForeignKey && column.ReferencesType == null && string.IsNullOrWhiteSpace(column.References)))
            throw new InvalidOperationException($"'{typeof(T).Name}.{member.Name}' is not declared as a foreign key.");
        if (column.ReferencesType != null && column.ReferencesType != typeof(TReference))
            throw new InvalidOperationException($"'{typeof(T).Name}.{member.Name}' references '{column.ReferencesType.Name}', not '{typeof(TReference).Name}'.");
        if (!string.IsNullOrWhiteSpace(column.References))
        {
            var table = column.References!.Split('.')[0];
            if (!string.Equals(table, EntityMetadata<TReference>.TableName, StringComparison.Ordinal))
                throw new InvalidOperationException($"'{typeof(T).Name}.{member.Name}' references table '{table}', not '{EntityMetadata<TReference>.TableName}'.");
        }
        var key = foreignKey.Compile()(entity);
        if (key == null) throw new InvalidOperationException($"'{typeof(T).Name}.{member.Name}' is null and cannot be included.");
        if (_db is HostDatabase host)
            return host.Include<TReference>(TableName, SqlExpression.Column(member), key) ?? throw new InvalidOperationException($"Included '{typeof(TReference).Name}' for '{typeof(T).Name}.{member.Name}' was not returned by the host.");
        return _db.Get<TReference>(EntityMetadata<TReference>.TableName, key.ToString()!) ?? throw new InvalidOperationException($"Included '{typeof(TReference).Name}' for '{typeof(T).Name}.{member.Name}' was not found.");
    }
}

internal sealed class DatabaseQuery<T> : IDatabaseQuery<T>
{
    private readonly IDatabase _db;
    private readonly IReadOnlyList<string> _where;
    private readonly IReadOnlyList<object?> _args;
    private readonly string? _order;
    private readonly int? _take;
    private readonly int? _skip;
    private readonly IReadOnlyList<IncludeSpec> _includes;

    public DatabaseQuery(IDatabase db) : this(db, Array.Empty<string>(), Array.Empty<object?>(), null, null, null, Array.Empty<IncludeSpec>()) { }
    private DatabaseQuery(IDatabase db, IReadOnlyList<string> where, IReadOnlyList<object?> args, string? order, int? take, int? skip, IReadOnlyList<IncludeSpec> includes)
        => (_db, _where, _args, _order, _take, _skip, _includes) = (db, where, args, order, take, skip, includes);

    public IDatabaseQuery<T> Where(Expression<Func<T, bool>> predicate)
    {
        if (predicate == null) throw new ArgumentNullException(nameof(predicate));
        var args = _args.ToList();
        var where = _where.Append(SqlExpression.Translate(predicate.Body, args)).ToArray();
        return new DatabaseQuery<T>(_db, where, args, _order, _take, _skip, _includes);
    }

    public IDatabaseQuery<T> Include<TReference>(Expression<Func<T, TReference?>> navigation)
    {
        if (navigation == null) throw new ArgumentNullException(nameof(navigation));
        var property = SqlExpression.Member(navigation.Body) as PropertyInfo
            ?? throw new InvalidOperationException("Include requires a navigation property.");
        var spec = IncludeSpec.Create<TReference>(property);
        return new DatabaseQuery<T>(_db, _where, _args, _order, _take, _skip, _includes.Append(spec).ToArray());
    }

    public IDatabaseQuery<T> OrderBy<TKey>(Expression<Func<T, TKey>> keySelector) => SetOrder(keySelector, false);
    public IDatabaseQuery<T> OrderByDescending<TKey>(Expression<Func<T, TKey>> keySelector) => SetOrder(keySelector, true);
    public IDatabaseQuery<T> Take(int count) { if (count < 0) throw new ArgumentOutOfRangeException(nameof(count)); return new DatabaseQuery<T>(_db, _where, _args, _order, count, _skip, _includes); }
    public IDatabaseQuery<T> Skip(int count) { if (count < 0) throw new ArgumentOutOfRangeException(nameof(count)); return new DatabaseQuery<T>(_db, _where, _args, _order, _take, count, _includes); }
    public IReadOnlyList<T> ToList() => _includes.Count == 0 ? _db.Query<T>(Sql("*"), _args.ToArray()) : _db is HostDatabase host ? host.QueryWithIncludes<T>(Sql("*"), _args.ToArray(), _includes) : throw new NotSupportedException("Include requires HostDatabase so the host can enforce foreign-key permissions.");
    public T? First() { var rows = Take(1).ToList(); return rows.Count == 0 ? default : rows[0]; }
    public long Count()
    {
        // Count the query's result set, including its requested window.  Counting directly from
        // the table used to ignore Take/Skip.
        var rows = _db.Query<DatabaseCount>($"SELECT COUNT(*) AS value FROM ({Sql("*", page: true)}) AS \"__exo_count\"", _args.ToArray());
        return rows.Count == 0 ? 0 : rows[0].Value;
    }
    public bool Exists() => Take(1).ToList().Count != 0;

    private IDatabaseQuery<T> SetOrder<TKey>(Expression<Func<T, TKey>> keySelector, bool descending)
    {
        if (keySelector == null) throw new ArgumentNullException(nameof(keySelector));
        var order = SqlExpression.Column(SqlExpression.Member(keySelector.Body)) + (descending ? " DESC" : " ASC");
        return new DatabaseQuery<T>(_db, _where, _args, order, _take, _skip, _includes);
    }

    private string Sql(string select, bool page = true)
    {
        var sql = $"SELECT {select} FROM {SqlExpression.Quote(EntityMetadata<T>.TableName)}";
        if (_where.Count > 0) sql += " WHERE " + string.Join(" AND ", _where);
        if (_order != null && page) sql += " ORDER BY " + _order;
        if (_take is int take && page) sql += " LIMIT " + take.ToString(CultureInfo.InvariantCulture);
        else if (_skip is not null && page) sql += " LIMIT -1";
        if (_skip is int skip && page) sql += " OFFSET " + skip.ToString(CultureInfo.InvariantCulture);
        return sql;
    }

    private sealed class DatabaseCount { public long Value { get; set; } }
}

internal sealed class IncludeSpec
{
    public string Column { get; }
    public PropertyInfo? Navigation { get; }
    public Type ReferenceType { get; }
    public IncludeSpec(string column, PropertyInfo? navigation, Type referenceType) => (Column, Navigation, ReferenceType) = (column, navigation, referenceType);
    public static IncludeSpec Create<TReference>(PropertyInfo navigation)
    {
        var pairing = navigation.GetCustomAttribute<ExoNavigationAttribute>();
        if (!navigation.CanWrite || navigation.PropertyType != typeof(TReference) || pairing is null)
            throw new InvalidOperationException($"'{navigation.DeclaringType?.Name}.{navigation.Name}' must be a settable property of the referenced record type, marked [ExoNavigation(nameof(ForeignKeyProperty))].");
        var fk = navigation.DeclaringType!.GetProperty(pairing.ForeignKeyProperty, BindingFlags.Public | BindingFlags.Instance);
        var column = fk?.GetCustomAttribute<ExoColumnAttribute>();
        if (fk is null || column is null || (!column.ForeignKey && column.ReferencesType is null && string.IsNullOrWhiteSpace(column.References)))
            throw new InvalidOperationException($"Navigation '{navigation.DeclaringType.Name}.{navigation.Name}' names '{pairing.ForeignKeyProperty}', which is missing or is not a declared [ExoColumn(ForeignKey = true)] column.");
        if (column.ReferencesType is not null && column.ReferencesType != typeof(TReference))
            throw new InvalidOperationException($"Navigation '{navigation.DeclaringType.Name}.{navigation.Name}' targets '{typeof(TReference).Name}', but FK '{fk.Name}' references '{column.ReferencesType.Name}'.");
        return new IncludeSpec(SqlExpression.Column(fk), navigation, typeof(TReference));
    }
}

internal static class SqlExpression
{
    public static string Translate(Expression expression, List<object?> args)
    {
        expression = Strip(expression);
        if (expression is BinaryExpression binary)
        {
            if (binary.NodeType == ExpressionType.AndAlso || binary.NodeType == ExpressionType.OrElse)
                return $"({Translate(binary.Left, args)} {(binary.NodeType == ExpressionType.AndAlso ? "AND" : "OR")} {Translate(binary.Right, args)})";
            var op = binary.NodeType switch { ExpressionType.Equal => "=", ExpressionType.NotEqual => "<>", ExpressionType.LessThan => "<", ExpressionType.LessThanOrEqual => "<=", ExpressionType.GreaterThan => ">", ExpressionType.GreaterThanOrEqual => ">=", _ => null };
            if (op == null) throw Unsupported(expression);
            var leftMember = TryMember(binary.Left);
            var rightMember = TryMember(binary.Right);
            if (leftMember != null && rightMember == null) return Compare(Column(leftMember), op, Value(binary.Right), args);
            if (rightMember != null && leftMember == null) return Compare(Column(rightMember), Reverse(op), Value(binary.Left), args);
            throw Unsupported(expression);
        }
        if (expression is UnaryExpression { NodeType: ExpressionType.Not } not)
            return $"(NOT {Translate(not.Operand, args)})";
        if (TryMember(expression) is MemberInfo member && IsBoolean(member)) return Column(member) + " = TRUE";
        if (expression is ConstantExpression { Value: bool value }) return value ? "TRUE" : "FALSE";
        throw Unsupported(expression);
    }

    public static MemberInfo Member(Expression expression) => TryMember(expression) ?? throw Unsupported(expression);
    public static string Column(MemberInfo member) => Quote(member.GetCustomAttribute<ExoColumnAttribute>()?.Name ?? ExoNaming.ToSnakeCase(member.Name));
    public static string Quote(string identifier) => "\"" + identifier.Replace("\"", "\"\"") + "\"";
    private static string Compare(string column, string op, object? value, List<object?> args)
    {
        if (value == null) return column + (op == "=" ? " IS NULL" : op == "<>" ? " IS NOT NULL" : throw new InvalidOperationException("Only equality comparisons support null."));
        args.Add(value); return column + " " + op + " $" + args.Count.ToString(CultureInfo.InvariantCulture);
    }
    private static string Reverse(string op) => op switch { "<" => ">", ">" => "<", "<=" => ">=", ">=" => "<=", _ => op };
    private static MemberInfo? TryMember(Expression expression)
    {
        expression = Strip(expression);
        return expression is MemberExpression member && member.Expression is ParameterExpression ? member.Member : null;
    }
    private static object? Value(Expression expression) => Expression.Lambda(Strip(expression)).Compile().DynamicInvoke();
    private static Expression Strip(Expression expression) { while (expression.NodeType is ExpressionType.Convert or ExpressionType.ConvertChecked) expression = ((UnaryExpression)expression).Operand; return expression; }
    private static bool IsBoolean(MemberInfo member) => member switch { PropertyInfo p => Nullable.GetUnderlyingType(p.PropertyType) == null && p.PropertyType == typeof(bool), FieldInfo f => Nullable.GetUnderlyingType(f.FieldType) == null && f.FieldType == typeof(bool), _ => false };
    private static NotSupportedException Unsupported(Expression expression) => new($"The expression '{expression}' cannot be translated to SQL.");
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
