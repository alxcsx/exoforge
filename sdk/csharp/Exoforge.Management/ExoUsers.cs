using System;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace Exoforge.Management;

/// <summary>
/// User accounts of a cluster, managed through the <c>auth</c> service with the saved admin session.
/// A service account for a trusted game server is an ordinary account with the <c>service</c> role.
/// </summary>
public static class ExoUsers
{
    public static readonly string[] Roles = { "player", "studio", "service", "admin" };

    public static string NormalizeRole(string? role, string fallback = "player")
    {
        string value = string.IsNullOrWhiteSpace(role) ? fallback : role.Trim().ToLowerInvariant();
        if (!Roles.Contains(value))
        {
            throw new ArgumentException($"Unknown role '{role}'. Use one of: {string.Join(", ", Roles)}.");
        }

        return value;
    }

    /// <summary>The highest role a set of scopes amounts to (the server's own order), for a one-word listing.</summary>
    public static string RoleOf(string scopes)
    {
        var held = scopes.Split(',').Select(x => x.Trim()).ToArray();
        foreach (var role in new[] { "admin", "studio", "service", "player" })
        {
            if (held.Contains(role))
            {
                return role;
            }
        }

        return "guest";
    }

    public static JsonObject CreatePayload(string email, string password, string? name, string? role)
    {
        if (string.IsNullOrWhiteSpace(email) || !email.Contains('@'))
        {
            throw new ArgumentException("An email address is required.");
        }

        if (string.IsNullOrEmpty(password))
        {
            throw new ArgumentException("A password is required (--password).");
        }

        // The id is ours to choose: without one, the transport fills in the caller's own id and
        // register would update the admin's account instead of creating a new one.
        var payload = new JsonObject
        {
            ["user_id"] = $"usr_{Guid.NewGuid():N}"[..16],
            ["email"] = email.Trim(),
            ["password"] = password,
            ["scopes"] = new JsonArray(NormalizeRole(role)),
        };

        if (!string.IsNullOrWhiteSpace(name))
        {
            payload["name"] = name.Trim();
        }

        return payload;
    }

    public static JsonObject RolePayload(string userId, string? role)
    {
        if (string.IsNullOrWhiteSpace(role))
        {
            throw new ArgumentException($"A role is required (--role {string.Join("|", Roles)}).");
        }

        return new JsonObject { ["user_id"] = RequireId(userId), ["role"] = NormalizeRole(role) };
    }

    /// <summary>Only the id: the token carries the scopes the account has now.</summary>
    public static JsonObject UserPayload(string userId) => new() { ["user_id"] = RequireId(userId) };

    /// <summary>
    /// A token request. The term is what makes a service credential safe to hand out: it stops
    /// working without anyone having to remember to revoke it.
    /// </summary>
    public static JsonObject TokenPayload(string userId, int? expiresIn)
    {
        var payload = UserPayload(userId);
        if (expiresIn is > 0)
        {
            payload["expires_in"] = expiresIn.Value;
        }

        return payload;
    }

    public static JsonObject RevokePayload(string tokenId)
    {
        if (string.IsNullOrWhiteSpace(tokenId))
        {
            throw new ArgumentException("A token id is required (--revoke <token_id>).");
        }

        return new JsonObject { ["token_id"] = tokenId.Trim() };
    }

    /// <summary>
    /// Parses a term such as <c>30d</c>, <c>12h</c>, <c>90m</c> or <c>3600s</c> into seconds.
    /// A bare number is seconds, which is what the action's <c>expires_in</c> takes.
    /// </summary>
    public static int ParseExpiry(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("An expiry is required (--expires 30d).");
        }

        string text = value.Trim().ToLowerInvariant();
        long multiplier = text[^1] switch
        {
            'd' => 86_400,
            'h' => 3_600,
            'm' => 60,
            's' => 1,
            _ => 0,
        };

        string number = multiplier == 0 ? text : text[..^1];

        if (!long.TryParse(number, out long amount) || amount <= 0)
        {
            throw new ArgumentException($"Invalid expiry '{value}'. Use e.g. 30d, 12h, 90m or 3600s.");
        }

        long seconds = amount * Math.Max(multiplier, 1);
        if (seconds > int.MaxValue)
        {
            throw new ArgumentException($"Expiry '{value}' is too long.");
        }

        return (int)seconds;
    }

    /// <summary>The server filters on <c>search</c> (id or email); its contract names the parameter <c>query</c>.</summary>
    public static JsonObject ListPayload(string? search, int? limit)
    {
        var payload = new JsonObject();
        if (!string.IsNullOrWhiteSpace(search))
        {
            payload["search"] = search.Trim();
        }

        if (limit is > 0)
        {
            payload["limit"] = limit;
        }

        return payload;
    }

    public static Task<JsonElement> ListAsync(ExoDeployer deployer, string? search, int? limit, string? env, CancellationToken ct = default) =>
        deployer.CallActionAsync("auth", "list_users", ListPayload(search, limit), env, ct: ct);

    public static Task<JsonElement> CreateAsync(ExoDeployer deployer, string email, string password, string? name, string? role, string? env, CancellationToken ct = default) =>
        deployer.CallActionAsync("auth", "register", CreatePayload(email, password, name, role), env, ct: ct);

    public static Task<JsonElement> SetRoleAsync(ExoDeployer deployer, string userId, string? role, string? env, CancellationToken ct = default) =>
        deployer.CallActionAsync("auth", "update_user_roles", RolePayload(userId, role), env, ct: ct);

    public static Task<JsonElement> IssueTokenAsync(ExoDeployer deployer, string userId, int? expiresIn, string? env, CancellationToken ct = default) =>
        deployer.CallActionAsync("auth", "issue_token", TokenPayload(userId, expiresIn), env, ct: ct);

    /// <summary>The account's tokens: ids, kinds, creation, last use and expiry. Never the secrets.</summary>
    public static Task<JsonElement> ListTokensAsync(ExoDeployer deployer, string userId, string? env, CancellationToken ct = default) =>
        deployer.CallActionAsync("auth", "list_tokens", UserPayload(userId), env, ct: ct);

    public static Task<JsonElement> RevokeTokenAsync(ExoDeployer deployer, string tokenId, string? env, CancellationToken ct = default) =>
        deployer.CallActionAsync("auth", "revoke_token", RevokePayload(tokenId), env, ct: ct);

    public static Task<JsonElement> DeleteAsync(ExoDeployer deployer, string userId, string? env, CancellationToken ct = default) =>
        deployer.CallActionAsync("auth", "delete_user", UserPayload(userId), env, ct: ct);

    private static string RequireId(string userId) =>
        string.IsNullOrWhiteSpace(userId) ? throw new ArgumentException("A user id is required.") : userId.Trim();
}
