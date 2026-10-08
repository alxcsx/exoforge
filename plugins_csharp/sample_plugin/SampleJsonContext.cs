using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Exoforge.Plugins.SamplePlugin;

/// <summary>
/// The JSON metadata for this plugin's own records.
///
/// NativeAOT has no reflection-based serialiser, so a type that crosses the host boundary has to be
/// declared here. A generator cannot emit this file: a source generator's output is invisible to the
/// System.Text.Json generator, so a context added that way never gets its serializer options and does
/// not compile. It is a real file, written by hand or by `exo plugin stubs`.
/// </summary>
[JsonSerializable(typeof(Counter))]
[JsonSerializable(typeof(CounterChanged))]
[JsonSerializable(typeof(List<Counter>))]
public partial class SampleJsonContext : JsonSerializerContext
{
}
