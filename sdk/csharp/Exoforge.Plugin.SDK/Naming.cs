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
            char c = name[i];
            if (char.IsUpper(c) && i > 0)
            {
                char prev = name[i - 1];
                bool prevLower = char.IsLower(prev);
                bool nextLower = i + 1 < name.Length && char.IsLower(name[i + 1]);
                bool prevUpper = char.IsUpper(prev);
                if (prevLower || (prevUpper && nextLower))
                {
                    sb.Append('_');
                }
            }

            sb.Append(char.ToLowerInvariant(c));
        }

        return sb.ToString();
    }
}
