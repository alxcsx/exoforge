using System;
using System.Text.Json;

namespace Exoforge.Client.Unity
{

    /// <summary>
    /// Resolved Exoforge connection settings for one environment.
    ///
    /// Built at runtime from the workspace's <c>exoforge.json</c> (copied into
    /// <c>Resources/exoforge.json</c> by <b>Exoforge Studio ▸ Settings ▸ Generate / Relink Runtime Config</b>),
    /// so game code never hardcodes cluster URLs or tokens.
    /// </summary>
    [Serializable]
    public class ExoforgeRuntimeConfig
    {
        /// <summary>Resources name of the linked workspace config file.</summary>
        public const string ResourcePath = "exoforge";

        /// <summary>Active environment name (e.g. <c>local</c>, <c>staging</c>, <c>production</c>).</summary>
        public string Environment { get; private set; } = "local";

        /// <summary>WebSocket gateway endpoint.</summary>
        public string WsUrl { get; private set; } = "ws://127.0.0.1:4000/ws";

        /// <summary>HTTP REST gateway base address.</summary>
        public string HttpUrl { get; private set; } = "http://127.0.0.1:4001";

        /// <summary>Bootstrap token used when no session token is stored yet.</summary>
        public string Token { get; private set; } = "";

        /// <summary>
        /// Builds a config from an <c>exoforge.json</c> payload, selecting
        /// <paramref name="environment"/> (or the file's <c>default_environment</c>).
        /// </summary>
        public static ExoforgeRuntimeConfig FromWorkspaceJson(string json, string? environment = null)
        {
            var config = new ExoforgeRuntimeConfig();

            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            string env = environment ?? "";
            if (string.IsNullOrEmpty(env) && root.TryGetProperty("default_environment", out var defaultEnv))
            {
                env = defaultEnv.GetString() ?? "local";
            }

            config.Environment = string.IsNullOrEmpty(env) ? "local" : env;

            if (root.TryGetProperty("environments", out var environments) &&
                environments.ValueKind == JsonValueKind.Object &&
                environments.TryGetProperty(config.Environment, out var selected))
            {
                config.WsUrl = GetString(selected, "ws_url") ?? config.WsUrl;
                config.HttpUrl = GetString(selected, "http_url") ?? config.HttpUrl;
                config.Token = GetString(selected, "token") ?? config.Token;
            }

            return config;
        }

        private static string? GetString(JsonElement element, string property) =>
            element.TryGetProperty(property, out var value) ? value.GetString() : null;
    }
}
