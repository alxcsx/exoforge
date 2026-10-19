using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.UnityAddressables;

[ExoResource("addressable_assets", PrimaryKey = "address", Source = "addressable_assets")]
public record AddressableAssetRecord
{
    [JsonPropertyName("address")]
    [ExoColumn(Label = "Address", Sortable = true, Filterable = true)]
    public string Address { get; init; } = "";

    [JsonPropertyName("release_version")]
    [ExoColumn(Label = "Build Version", Sortable = true, Filterable = true)]
    public string ReleaseVersion { get; init; } = "1.0.0";

    [JsonPropertyName("asset_path")]
    [ExoColumn(Label = "Asset Path")]
    public string AssetPath { get; init; } = "";

    [JsonPropertyName("group_name")]
    [ExoColumn(Label = "Group", Sortable = true, Filterable = true, Badge = true)]
    public string GroupName { get; init; } = "Default";

    [JsonPropertyName("labels")]
    [ExoColumn(Label = "Labels", Badge = true)]
    public string Labels { get; init; } = "";

    [JsonPropertyName("bundle_name")]
    [ExoColumn(Label = "Bundle")]
    public string BundleName { get; init; } = "";

    [JsonPropertyName("file_size")]
    [ExoColumn(Label = "Size (Bytes)")]
    public long FileSize { get; init; }

    [JsonPropertyName("hash")]
    [ExoColumn(Label = "Hash")]
    public string Hash { get; init; } = "";

    [JsonPropertyName("preview_url")]
    [ExoColumn(Label = "Preview")]
    public string PreviewUrl { get; init; } = "";

    [JsonPropertyName("status")]
    [ExoColumn(Label = "Status", Badge = true)]
    public string Status { get; init; } = "published";

    [JsonPropertyName("updated_at")]
    [ExoColumn(Label = "Updated At")]
    public long UpdatedAt { get; init; }
}

[ExoResource("addressable_releases", PrimaryKey = "version", Source = "addressable_releases")]
public record AddressableReleaseRecord
{
    [JsonPropertyName("build_number")]
    [ExoColumn(Label = "Build #", Sortable = true)]
    public int BuildNumber { get; init; } = 1;

    [JsonPropertyName("version")]
    [ExoColumn(Label = "Version", Sortable = true)]
    public string Version { get; init; } = "1";

    [JsonPropertyName("uploader")]
    [ExoColumn(Label = "Uploader", Badge = true)]
    public string Uploader { get; init; } = "developer";

    [JsonPropertyName("badge")]
    [ExoColumn(Label = "Badge", Badge = true)]
    public string Badge { get; init; } = "latest";

    [JsonPropertyName("badges")]
    public List<string> Badges { get; init; } = new() { "latest" };

    [JsonPropertyName("catalog_hash")]
    [ExoColumn(Label = "Catalog Hash")]
    public string CatalogHash { get; init; } = "";

    [JsonPropertyName("catalog_json")]
    [ExoColumn(Label = "Catalog JSON")]
    public string? CatalogJson { get; init; }

    [JsonPropertyName("bundle_count")]
    [ExoColumn(Label = "Bundles Count")]
    public int BundleCount { get; init; }

    [JsonPropertyName("total_size")]
    [ExoColumn(Label = "Total Size (Bytes)")]
    public long TotalSize { get; init; }

    [JsonPropertyName("created_at")]
    [ExoColumn(Label = "Created At")]
    public long CreatedAt { get; init; }
}

public record AddressablesManifestDto
{
    [JsonPropertyName("version")]
    public string Version { get; init; } = "";

    [JsonPropertyName("tag")]
    public string Tag { get; init; } = "latest";

    [JsonPropertyName("catalog_hash")]
    public string CatalogHash { get; init; } = "";

    [JsonPropertyName("catalog_json")]
    public string? CatalogJson { get; init; }

    [JsonPropertyName("remote_load_path")]
    public string RemoteLoadPath { get; init; } = "";

    [JsonPropertyName("assets")]
    public List<AddressableAssetRecord> Assets { get; init; } = new();
}

public record AddressableAssetDto
{
    [JsonPropertyName("address")]
    public string Address { get; init; } = "";

    [JsonPropertyName("release_version")]
    public string? ReleaseVersion { get; init; }

    [JsonPropertyName("asset_path")]
    public string AssetPath { get; init; } = "";

    [JsonPropertyName("group_name")]
    public string GroupName { get; init; } = "Default";

    [JsonPropertyName("labels")]
    public string? Labels { get; init; }

    [JsonPropertyName("bundle_name")]
    public string? BundleName { get; init; }

    [JsonPropertyName("file_size")]
    public long FileSize { get; init; }

    [JsonPropertyName("hash")]
    public string? Hash { get; init; }

    [JsonPropertyName("preview_url")]
    public string? PreviewUrl { get; init; }

    [JsonPropertyName("base64_preview")]
    public string? Base64Preview { get; init; }
}

public record AddressablesStats
{
    [JsonPropertyName("total_assets")]
    public int TotalAssets { get; init; }

    [JsonPropertyName("total_bundles")]
    public int TotalBundles { get; init; }

    [JsonPropertyName("total_size_bytes")]
    public long TotalSizeBytes { get; init; }

    [JsonPropertyName("active_badge")]
    public string ActiveBadge { get; init; } = "latest";

    [JsonPropertyName("active_badges")]
    public List<string> ActiveBadges { get; init; } = new() { "latest" };

    [JsonPropertyName("active_version")]
    public string ActiveVersion { get; init; } = "none";

    [JsonPropertyName("active_build_number")]
    public int ActiveBuildNumber { get; init; } = 1;
}
