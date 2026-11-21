# Typed stubs: nested types in manifest.json

Problem: generated stubs typed nested values as `JsonElement` (a `List<Item>` inside a returned record became `JsonElement Itens`).
The plugin generator reduced them to a bare `list`/`map`. Now it describes them and the stub generators use that.

## Manifest format (additive; every old key is unchanged)

Per action: `returns_shape` (whole return), `returns_shapes` (return fields), `params_shapes` (params).
Per event: `payload_shapes`. Per service: `types`. A key is written only when it adds something
(a list, dictionary, record or enum); a service of scalars has none of them.

Shape (JSON object, only applicable keys present):

    {"type": T, "nullable": true, "items": SHAPE, "values": SHAPE, "ref": "TypeKey", "choices": ["a","b"]}

- `T`: `string int integer float decimal boolean uuid datetime timespan binary json list map record`.
  `int` = 32-bit (Int16/Int32/Byte/SByte/UInt16), `integer` = 64-bit (Int64/UInt32/UInt64), `json` = dynamic
  (object, JsonElement, dynamic, a System/Microsoft type, a type with no public properties, depth > 16).
- `list`: List/IReadOnlyList/IList/IEnumerable/IReadOnlyCollection/ICollection/Collection/HashSet/ISet/
  ImmutableArray/ImmutableList/T[] (not byte[], which is `binary`); element in `items`.
- `map`: Dictionary/IDictionary/IReadOnlyDictionary/SortedDictionary/ConcurrentDictionary/ImmutableDictionary with a `string` key; value in `values`. Any other key type is `json`.
- `record`: `ref` is a key of the service's `types`.
- enum: `{"type":"string","choices":[snake_case member names]}`.
- `nullable`: `T?` (Nullable<T>) or an annotated reference type.

`types` (service level): `{"Item": {"fields": {"slot": SHAPE, "children": SHAPE}}}`. Field names are the wire names System.Text.Json uses: `[JsonPropertyName]` if present, else snake_case. Properties it omits are left out: no public getter, indexers, `[JsonIgnore]` without a condition or with `Always`. The same selection (own + inherited) feeds `returns`, event `payload` and `types`.
Only the types a service reaches (through its actions, events and other types) are written. Key = C# type name
(generic: name + argument names, `PageItem`); a clash with a different type prefixes the namespace's last part.
Cycles end at the `ref`.

Placed per service (not top level) because the server exports each service entry verbatim (core ExtensionRegistry
`manifest_services` + `sanitize_for_json`) and drops unknown top-level manifest fields with a warning. Elixir readers
only use `returns`/`params`/`payload` (dashboard, docs); nothing in core or the std extensions reads the new keys.
The loader atomizes values of keys named `type`, `name`, `returns`, `params`, `payload`, ... so shapes avoid `name`.

## Stub generation (Exoforge.Management ExoCodeGenerator)

- `ParseServices` reads the keys into `ParamModel.Shape`, `ActionContractModel.ReturnShape`, `ServiceContractModel.Types`.
- `StubTypes` resolves C# names: key as is (PascalCase); prefixed with the service name when it collides with another
  generated model, or when another service has the same key with a different shape; same shape = one class.
- C#: list -> `List<T>`, map -> `Dictionary<string, T>`, record -> class, nullable -> `T?`, uuid -> `Guid`,
  datetime -> `DateTimeOffset`, timespan -> `TimeSpan`, binary -> `byte[]`, enum -> `string`, json -> `JsonElement`.
- Used for request properties, response fields, event payloads, the Unity typed-argument overloads and return types,
  in both the plugin stubs (`Exoforge.Plugins.Generated`) and the Unity client. Nested classes only the Studio
  reaches sit under `#if UNITY_EDITOR` in the Unity client.
- A manifest without these keys generates exactly as before. A return with a rich `returns_shape` is emitted from `types`
  (no `...Response` class from `returns`).

## Limits

- Resource columns are not typed this way (a `List<Child>` column is still `list`/`JsonElement` in the stubs).
- Two services with the same type key share one class only when the whole structure under it (nested records, choices, cycles) is identical; otherwise the later one is prefixed with its service name.
- A nullable rich return keeps its `?` in the Unity client (`Task<Inv?>`, `Action<Inv?>`) and the plugin stubs.

Tests: `Exoforge.Plugin.Generator.Tests/TypedManifestTests.cs`, `Exoforge.Management.Tests/TypedStubsTests.cs`.
