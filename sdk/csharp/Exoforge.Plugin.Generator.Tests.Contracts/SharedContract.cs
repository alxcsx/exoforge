using Exoforge.Plugin.SDK;

namespace Exoforge.Plugin.Generator.Tests.Contracts;

/// <summary>
/// A contract that lives in its own assembly, the way a shared contracts package would. Nothing here
/// knows which plugin implements it.
/// </summary>
[ExoService("shared_contract", Category = "Test", Title = "Shared Contract", Icon = "🤝")]
public interface ISharedContract
{
    [ExoAction]
    string Greet(string name);
}
