using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace Exoforge.Plugin.SDK
{
    public static class ExoJsonExtensions
    {
        public static T? As<T>(this JsonElement element)
        {
            if (element.ValueKind == JsonValueKind.Undefined || element.ValueKind == JsonValueKind.Null)
                return default;
            return PluginJson.Deserialize<T>(element.GetRawText());
        }

        public static bool TryAs<T>(this JsonElement element, out T? value)
        {
            value = default;
            if (element.ValueKind == JsonValueKind.Undefined || element.ValueKind == JsonValueKind.Null)
                return false;
            try { value = PluginJson.Deserialize<T>(element.GetRawText()); return true; }
            catch { return false; }
        }

        public static List<T> AsList<T>(this JsonElement element)
        {
            if (element.ValueKind != JsonValueKind.Array) return new List<T>();
            var list = new List<T>();
            foreach (var item in element.EnumerateArray())
            {
                if (item.ValueKind == JsonValueKind.Null || item.ValueKind == JsonValueKind.Undefined) continue;
                var v = item.As<T>();
                if (v is not null) list.Add(v);
            }
            return list;
        }

        public static Dictionary<string, T> AsDictionary<T>(this JsonElement element)
        {
            var dict = new Dictionary<string, T>(StringComparer.Ordinal);
            if (element.ValueKind != JsonValueKind.Object) return dict;
            foreach (var prop in element.EnumerateObject())
            {
                if (prop.Value.ValueKind == JsonValueKind.Null || prop.Value.ValueKind == JsonValueKind.Undefined) continue;
                var v = prop.Value.As<T>();
                if (v is not null) dict[prop.Name] = v;
            }
            return dict;
        }

        /// <summary>
        /// Follows a path such as <c>a.b[0].c</c> or <c>a.['odd key']</c> and returns the value, or null when any step is
        /// missing, has the wrong kind, or the final value is JSON null. Never throws.
        /// </summary>
        public static JsonElement? Path(this JsonElement element, string path)
        {
            var current = element;
            int i = 0;
            while (i < path.Length)
            {
                if (path[i] == '.') i++;                                   // a separator; a leading one is tolerated
                if (i >= path.Length) return null;

                if (path[i] == '[')
                {
                    int close = path.IndexOf(']', i);
                    if (close < 0) return null;
                    string inner = path.Substring(i + 1, close - i - 1);
                    i = close + 1;

                    if (inner.Length >= 2 && inner[0] == '\'' && inner[inner.Length - 1] == '\'')
                    {
                        if (!TryProperty(ref current, inner.Substring(1, inner.Length - 2))) return null;
                    }
                    else
                    {
                        // an index: digits only, so a negative or malformed one is simply not found
                        if (!int.TryParse(inner, NumberStyles.None, CultureInfo.InvariantCulture, out int index)) return null;
                        if (current.ValueKind != JsonValueKind.Array || index >= current.GetArrayLength()) return null;
                        current = current[index];
                    }
                }
                else
                {
                    int start = i;
                    while (i < path.Length && (char.IsLetterOrDigit(path[i]) || path[i] == '_' || path[i] == '-')) i++;
                    if (i == start || !TryProperty(ref current, path.Substring(start, i - start))) return null;
                }
            }

            return current.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null ? null : current;
        }

        private static bool TryProperty(ref JsonElement current, string name) =>
            current.ValueKind == JsonValueKind.Object && current.TryGetProperty(name, out current);

        public static string? GetString(this JsonElement element, string path)
        {
            var e = element.Path(path);
            if (e is null) return null;
            return e.Value.ValueKind switch
            {
                JsonValueKind.String => e.Value.GetString(),
                JsonValueKind.Number => e.Value.GetRawText(),
                JsonValueKind.True => "true",
                JsonValueKind.False => "false",
                _ => null
            };
        }

        public static long? GetLong(this JsonElement element, string path)
        {
            var e = element.Path(path);
            if (e is null) return null;
            if (e.Value.ValueKind == JsonValueKind.Number)
            {
                return e.Value.TryGetInt64(out var l) ? l : null;
            }
            if (e.Value.ValueKind == JsonValueKind.String)
            {
                var s = e.Value.GetString();
                return long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var ls) ? ls : null;
            }
            return null;
        }

        public static double? GetDouble(this JsonElement element, string path)
        {
            var e = element.Path(path);
            if (e is null) return null;
            if (e.Value.ValueKind == JsonValueKind.Number)
            {
                if (e.Value.TryGetDouble(out var d)) return d;
                return null;
            }
            if (e.Value.ValueKind == JsonValueKind.String)
            {
                var s = e.Value.GetString();
                if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var ds)) return ds;
                return null;
            }
            return null;
        }

        public static bool? GetBool(this JsonElement element, string path)
        {
            var e = element.Path(path);
            if (e is null) return null;
            if (e.Value.ValueKind == JsonValueKind.True) return true;
            if (e.Value.ValueKind == JsonValueKind.False) return false;
            if (e.Value.ValueKind == JsonValueKind.String)
            {
                var s = e.Value.GetString();
                if (bool.TryParse(s, out var b)) return b;
            }
            return null;
        }

        public static IEnumerable<JsonElement> Items(this JsonElement element)
        {
            if (element.ValueKind == JsonValueKind.Array) return element.EnumerateArray();
            if (element.ValueKind == JsonValueKind.Object) return element.EnumerateObject().Select(p => p.Value);
            return Array.Empty<JsonElement>();
        }

        public static string ToJson(this JsonElement element, bool indent = false)
        {
            if (element.ValueKind == JsonValueKind.Undefined) return "null";
            if (!indent) return element.GetRawText();
            using var doc = JsonDocument.Parse(element.GetRawText());
            using var ms = new MemoryStream();
            using (var writer = new Utf8JsonWriter(ms, new JsonWriterOptions { Indented = true }))
            {
                doc.RootElement.WriteTo(writer);
            }
            return Encoding.UTF8.GetString(ms.ToArray());
        }

        public static JsonElement FromObject(object? obj)
        {
            if (obj is null) return JsonDocument.Parse("null").RootElement.Clone();
            return JsonDocument.Parse(PluginJson.Serialize(obj)).RootElement.Clone();
        }
    }
}