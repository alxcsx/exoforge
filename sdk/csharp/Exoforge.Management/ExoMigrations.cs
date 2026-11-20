using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Exoforge.Management;

/// <summary>
/// A studio's own SQL migrations for a table it keeps in line itself (<c>SchemaVersioningMode.Manual</c>): the files
/// of an extension's <c>migrations/</c> folder, named <c>0007_add_owner.sql</c>. The number is the version, they apply
/// in order, and the server records each one it has applied, so running them again does nothing.
/// </summary>
public static class ExoMigrations
{
    public sealed class Migration
    {
        public Migration(int version, string name, string[] statements)
        {
            Version = version;
            Name = name;
            Statements = statements;
        }

        public int Version { get; }
        public string Name { get; }
        public string[] Statements { get; }
    }

    private static readonly Regex FileName = new(@"^(?<v>\d+)_(?<n>[A-Za-z0-9_\-]+)\.sql$", RegexOptions.Compiled);

    public static IReadOnlyList<Migration> Load(string migrationsDir)
    {
        if (!Directory.Exists(migrationsDir))
        {
            throw new DirectoryNotFoundException($"No migrations folder at {migrationsDir}.");
        }

        var found = new List<Migration>();

        foreach (var path in Directory.GetFiles(migrationsDir, "*.sql"))
        {
            string file = Path.GetFileName(path);
            var match = FileName.Match(file);
            if (!match.Success)
            {
                throw new ArgumentException($"'{file}' is not a migration name. Write it as 0007_what_it_does.sql: the number is the version.");
            }

            var statements = Split(File.ReadAllText(path));
            if (statements.Length == 0)
            {
                throw new ArgumentException($"'{file}' has no statements.");
            }

            found.Add(new Migration(int.Parse(match.Groups["v"].Value), match.Groups["n"].Value, statements));
        }

        var duplicate = found.GroupBy(m => m.Version).FirstOrDefault(g => g.Count() > 1);
        if (duplicate is not null)
        {
            throw new ArgumentException($"Two migrations are version {duplicate.Key}. Each version is one file.");
        }

        return found.OrderBy(m => m.Version).ToList();
    }

    /// <summary>The payload of the server's <c>lldb.run_migrations</c> action.</summary>
    public static JsonObject ToPayload(string extensionId, IEnumerable<Migration> migrations) =>
        new()
        {
            ["namespace"] = extensionId,
            ["migrations"] = new JsonArray(migrations.Select(m => (JsonNode)new JsonObject
            {
                ["version"] = m.Version,
                ["name"] = m.Name,
                ["sql"] = new JsonArray(m.Statements.Select(s => (JsonNode)JsonValue.Create(s)!).ToArray())
            }).ToArray())
        };

    /// <summary>
    /// Splits a file into statements at the semicolons that end one: not those inside a quoted string or identifier,
    /// a comment, or a dollar-quoted body (<c>$$ ... $$</c>, as a function is written). Empty statements are dropped.
    /// </summary>
    public static string[] Split(string sql)
    {
        var statements = new List<string>();
        var current = new StringBuilder();
        int i = 0;

        while (i < sql.Length)
        {
            char c = sql[i];

            if (c == '-' && i + 1 < sql.Length && sql[i + 1] == '-')
            {
                int end = sql.IndexOf('\n', i);
                end = end < 0 ? sql.Length : end;
                current.Append(sql, i, end - i);
                i = end;
            }
            else if (c == '/' && i + 1 < sql.Length && sql[i + 1] == '*')
            {
                int end = sql.IndexOf("*/", i + 2, StringComparison.Ordinal);
                end = end < 0 ? sql.Length : end + 2;
                current.Append(sql, i, end - i);
                i = end;
            }
            else if (c == '\'' || c == '"')
            {
                int end = i + 1;
                while (end < sql.Length)
                {
                    // a doubled quote is a quote inside the string
                    if (sql[end] == c && end + 1 < sql.Length && sql[end + 1] == c) end += 2;
                    else if (sql[end] == c) { end++; break; }
                    else end++;
                }

                current.Append(sql, i, end - i);
                i = end;
            }
            else if (c == '$' && DollarTag(sql, i) is { } tag)
            {
                int close = sql.IndexOf(tag, i + tag.Length, StringComparison.Ordinal);
                int end = close < 0 ? sql.Length : close + tag.Length;
                current.Append(sql, i, end - i);
                i = end;
            }
            else if (c == ';')
            {
                Flush(statements, current);
                i++;
            }
            else
            {
                current.Append(c);
                i++;
            }
        }

        Flush(statements, current);
        return statements.ToArray();
    }

    // `$$` or `$name$` at position i, else null (`$1` is a parameter, not a quote).
    private static string? DollarTag(string sql, int i)
    {
        int j = i + 1;
        while (j < sql.Length && (char.IsLetterOrDigit(sql[j]) || sql[j] == '_')) j++;
        if (j >= sql.Length || sql[j] != '$') return null;
        if (j > i + 1 && char.IsDigit(sql[i + 1])) return null;
        return sql.Substring(i, j - i + 1);
    }

    private static void Flush(List<string> statements, StringBuilder current)
    {
        string text = current.ToString().Trim();
        current.Clear();

        // A chunk that is only comments is not a statement.
        string withoutComments = Regex.Replace(text, @"--[^\n]*|/\*.*?\*/", "", RegexOptions.Singleline).Trim();
        if (withoutComments.Length > 0) statements.Add(text);
    }
}
