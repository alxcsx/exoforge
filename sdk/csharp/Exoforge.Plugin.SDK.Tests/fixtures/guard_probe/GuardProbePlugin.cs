using Exoforge.Plugin.SDK;

namespace GuardProbe;

/// <summary>
/// The smallest real plugin the build pipeline will accept. The deployment guards fire before this
/// ever compiles, so it exists to make the fixture a plugin rather than a project that only looks
/// like one - and to give the runtime-contract test a publishable binary.
/// </summary>
[ExoService("guard_probe", Version = "1.0.0")]
public class GuardProbePlugin
{
    [ExoAction("ping", Mode = ActionMode.Sync)]
    public int Ping() => 42;

    public static void Main() => PluginHost.Run<GuardProbePlugin>();
}
