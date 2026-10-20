using System;
using System.Collections.Generic;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.UnityAddressables;

[ExoResource("addressable_assets", PrimaryKey = "address", Source = "addressable_assets")]
public record AddressableAssetRecord
{
    [ExoColumn(Label = "Address", Sortable = true, Filterable = true)]
    public string Address { get; init; } = "";

    [ExoColumn(Label = "Build Version", Sortable = true, Filterable = true)]
    public string ReleaseVersion { get; init; } = "1.0.0";

    [ExoColumn(Label = "Asset Path")]
    public string AssetPath { get; init; } = "";

    [ExoColumn(Label = "Group", Sortable = true, Filterable = true, Badge = true)]
    public string GroupName { get; init; } = "Default";

    [ExoColumn(Label = "Labels", Badge = true)]
    public string Labels { get; init; } = "";

    [ExoColumn(Label = "Bundle")]
    public string BundleName { get; init; } = "";

    [ExoColumn(Label = "Size (Bytes)")]
    public long FileSize { get; init; }

    [ExoColumn(Label = "Hash")]
    public string Hash { get; init; } = "";

    [ExoColumn(Label = "Preview")]
    public string PreviewUrl { get; init; } = "";

    [ExoColumn(Label = "Status", Badge = true)]
    public string Status { get; init; } = "published";

    [ExoColumn(Label = "Updated At")]
    public long UpdatedAt { get; init; }
}

[ExoResource("addressable_releases", PrimaryKey = "version", Source = "addressable_releases")]
public record AddressableReleaseRecord
{
    [ExoColumn(Label = "Build #", Sortable = true)]
    public int BuildNumber { get; init; } = 1;

    [ExoColumn(Label = "Version", Sortable = true)]
    public string Version { get; init; } = "1";

    [ExoColumn(Label = "Uploader", Badge = true)]
    public string Uploader { get; init; } = "developer";

    [ExoColumn(Label = "Badge", Badge = true)]
    public string Badge { get; init; } = "latest";

    public List<string> Badges { get; init; } = new() { "latest" };

    [ExoColumn(Label = "Catalog Hash")]
    public string CatalogHash { get; init; } = "";

    [ExoColumn(Label = "Catalog JSON")]
    public string? CatalogJson { get; init; }

    [ExoColumn(Label = "Bundles Count")]
    public int BundleCount { get; init; }

    [ExoColumn(Label = "Total Size (Bytes)")]
    public long TotalSize { get; init; }

    [ExoColumn(Label = "Created At")]
    public long CreatedAt { get; init; }
}

public record AddressablesManifestDto
{
    public string Version { get; init; } = "";
    public string Tag { get; init; } = "latest";
    public string CatalogHash { get; init; } = "";
    public string? CatalogJson { get; init; }
    public string RemoteLoadPath { get; init; } = "";
    public List<AddressableAssetRecord> Assets { get; init; } = new();
}

public record AddressableAssetDto
{
    public string Address { get; init; } = "";
    public string? ReleaseVersion { get; init; }
    public string AssetPath { get; init; } = "";
    public string GroupName { get; init; } = "Default";
    public string? Labels { get; init; }
    public string? BundleName { get; init; }
    public long FileSize { get; init; }
    public string? Hash { get; init; }
    public string? PreviewUrl { get; init; }
    public string? Base64Preview { get; init; }
}

public record AddressablesStats
{
    public int TotalAssets { get; init; }
    public int TotalBundles { get; init; }
    public long TotalSizeBytes { get; init; }
    public string ActiveBadge { get; init; } = "latest";
    public List<string> ActiveBadges { get; init; } = new() { "latest" };
    public string ActiveVersion { get; init; } = "none";
    public int ActiveBuildNumber { get; init; } = 1;
}
