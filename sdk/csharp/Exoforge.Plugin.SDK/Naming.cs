using System.Text;

namespace Exoforge.Plugin.SDK;

/// <summary>
/// Naming conventions shared by the manifest generator and the native dispatcher. Both must agree
/// on the default action name so the host can route a manifest action to the C# method.
/// </summary>
public static class ExoNaming
{
    /// <summary>Converts a C# member name to the snake_case name used on the wire (<c>SubmitScore</c> → <c>submit_score</c>).</summary>
    public static string ToSnakeCase(string name)
    {
        var sb = new StringBuilder(name.Length + 4);

        for (int i = 0; i < name.Length; i++)
        {
            if (char.IsUpper(name[i]) && i > 0)
            {
                sb.Append('_');
            }

            sb.Append(char.ToLowerInvariant(name[i]));
        }

        return sb.ToString();
    }
}
