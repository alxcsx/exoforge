using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Exoforge.Plugin.SDK;
using Exoforge.Plugins.Generated;

namespace Exoforge.Plugins.UnityAddressables;

[ExoService("unity_addressables", Version = "1.0.0",
    Category = "Game Content", Title = "Unity Addressables", Icon = "📦",
    DashboardElement = "exo-unity-addressables", DashboardEntry = "addressables-studio.js")]
[ExoInputType("addressable_ref", Element = "exo-addressable-input", Entry = "addressable-input.js")]
public class UnityAddressablesPlugin
{
    public const string AssetsTable = "addressable_assets";
    public const string ReleasesTable = "addressable_releases";

    [ExoAction]
    public AddressablesStats GetStats()
    {
        var assets = Exo.Database.All<AddressableAssetRecord>() ?? Array.Empty<AddressableAssetRecord>();
        var releases = Exo.Database.All<AddressableReleaseRecord>() ?? Array.Empty<AddressableReleaseRecord>();

        var latestRelease = releases.OrderByDescending(r => r.BuildNumber).ThenByDescending(r => r.CreatedAt).FirstOrDefault();
        var bundles = assets.Select(a => a.BundleName).Where(b => !string.IsNullOrEmpty(b)).Distinct().Count();
        long totalSize = assets.Sum(a => a.FileSize);

        return new AddressablesStats
        {
            TotalAssets = assets.Count,
            TotalBundles = bundles,
            TotalSizeBytes = totalSize,
            ActiveBadge = latestRelease?.Badge ?? "latest",
            ActiveBadges = latestRelease?.Badges ?? (latestRelease != null ? new List<string> { latestRelease.Badge } : new List<string> { "latest" }),
            ActiveVersion = latestRelease?.Version ?? (releases.Count > 0 ? "1" : "none"),
            ActiveBuildNumber = latestRelease?.BuildNumber ?? (releases.Count > 0 ? 1 : 0)
        };
    }

    [ExoAction]
    public List<AddressableAssetRecord> ListAssets(string? group = null, string? label = null, string? search = null, string? tag = null)
    {
        var assets = Exo.Database.All<AddressableAssetRecord>() ?? Array.Empty<AddressableAssetRecord>();

        var query = assets.AsEnumerable();

        if (!string.IsNullOrWhiteSpace(group) && group != "all")
        {
            query = query.Where(a => string.Equals(a.GroupName, group, StringComparison.OrdinalIgnoreCase));
        }

        if (!string.IsNullOrWhiteSpace(label))
        {
            query = query.Where(a => a.Labels.Contains(label, StringComparison.OrdinalIgnoreCase));
        }

        if (!string.IsNullOrWhiteSpace(tag) && tag != "all")
        {
            query = query.Where(a => a.Labels.Contains(tag, StringComparison.OrdinalIgnoreCase));
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(a =>
                a.Address.Contains(search, StringComparison.OrdinalIgnoreCase) ||
                a.AssetPath.Contains(search, StringComparison.OrdinalIgnoreCase) ||
                a.GroupName.Contains(search, StringComparison.OrdinalIgnoreCase) ||
                a.Labels.Contains(search, StringComparison.OrdinalIgnoreCase));
        }

        return query.OrderBy(a => a.Address).ToList();
    }

    [ExoAction]
    public AddressableAssetRecord? GetAsset(string address)
    {
        if (string.IsNullOrEmpty(address)) return null;
        return Exo.Database.Get<AddressableAssetRecord>(address);
    }

    [ExoAction]
    public List<AddressableReleaseRecord> ListReleases()
    {
        var releases = Exo.Database.All<AddressableReleaseRecord>() ?? Array.Empty<AddressableReleaseRecord>();
        return releases.OrderByDescending(r => r.BuildNumber).ThenByDescending(r => r.CreatedAt).ToList();
    }

    [ExoAction]
    public AddressablesManifestDto? GetManifest(string tag = "latest")
    {
        var releases = Exo.Database.All<AddressableReleaseRecord>() ?? Array.Empty<AddressableReleaseRecord>();
        var targetBadge = string.IsNullOrWhiteSpace(tag) ? "latest" : tag.Trim().ToLowerInvariant();

        var release = releases.FirstOrDefault(r => r.Badges != null && r.Badges.Any(b => b.ToLowerInvariant() == targetBadge))
                      ?? releases.FirstOrDefault(r => (r.Badge ?? "").ToLowerInvariant() == targetBadge)
                      ?? releases.OrderByDescending(r => r.BuildNumber).ThenByDescending(r => r.CreatedAt).FirstOrDefault();

        if (release == null) return null;

        var allAssets = Exo.Database.All<AddressableAssetRecord>() ?? Array.Empty<AddressableAssetRecord>();
        var assets = allAssets.OrderBy(a => a.Address).ToList();

        if (releases.Count > 1)
        {
            var relAssets = assets.Where(a => a.ReleaseVersion == release.Version).ToList();
            if (relAssets.Count > 0) assets = relAssets;
        }

        return new AddressablesManifestDto
        {
            Version = release.Version,
            Tag = release.Badge,
            CatalogHash = release.CatalogHash,
            CatalogJson = release.CatalogJson,
            RemoteLoadPath = "/api/files/addressables",
            Assets = assets
        };
    }

    [ExoAction]
    public Result<AddressableReleaseRecord> PublishRelease(
        string? version = null,
        string? badge = "latest",
        string? catalogHash = null,
        string? catalogJson = null,
        List<AddressableAssetDto>? assets = null,
        string? uploader = null,
        List<string>? badges = null)
    {
        var existingReleases = Exo.Database.All<AddressableReleaseRecord>() ?? Array.Empty<AddressableReleaseRecord>();

        // 1. Incremental Counter: compute next build number automatically
        int nextBuildNumber = 1;
        if (existingReleases.Count > 0)
        {
            int maxBuild = existingReleases.Select(r =>
            {
                if (r.BuildNumber > 0) return r.BuildNumber;
                if (int.TryParse(r.Version.TrimStart('v', 'V'), out int n)) return n;
                return 0;
            }).DefaultIfEmpty(0).Max();
            nextBuildNumber = maxBuild + 1;
        }

        string resolvedVersion = string.IsNullOrWhiteSpace(version) ? nextBuildNumber.ToString() : version.Trim();
        long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        // 2. Identifier of user who uploaded the build
        string safeUploader = !string.IsNullOrWhiteSpace(uploader) ? uploader.Trim() : "developer";

        // 3. Multiple tags/badges
        var badgeList = new List<string>();
        if (badges != null && badges.Count > 0)
        {
            badgeList.AddRange(badges);
        }
        if (!string.IsNullOrWhiteSpace(badge))
        {
            badgeList.AddRange(badge.Split(',', StringSplitOptions.RemoveEmptyEntries));
        }
        badgeList = badgeList.Select(b => b.Trim().ToLowerInvariant()).Where(b => !string.IsNullOrEmpty(b)).Distinct().ToList();
        if (badgeList.Count == 0) badgeList.Add("latest");
        string primaryBadge = badgeList[0];

        // Exclusive channel badges (latest, production, staging) uniquely point to this new build
        var exclusiveChannels = new HashSet<string> { "latest", "production", "staging" };
        var incomingExclusives = badgeList.Where(b => exclusiveChannels.Contains(b)).ToList();

        if (incomingExclusives.Count > 0 && existingReleases.Count > 0)
        {
            foreach (var oldRel in existingReleases)
            {
                var oldBadges = (oldRel.Badges ?? new List<string> { oldRel.Badge })
                    .Where(b => !incomingExclusives.Contains(b.ToLowerInvariant()))
                    .ToList();
                if (oldBadges.Count == 0) oldBadges.Add("archived");
                if (!oldBadges.SequenceEqual(oldRel.Badges ?? new List<string> { oldRel.Badge }))
                {
                    var updatedOld = oldRel with { Badges = oldBadges, Badge = oldBadges[0] };
                    Exo.Database.Put(updatedOld);
                }
            }
        }

        var assetList = assets ?? new List<AddressableAssetDto>();
        long totalSize = 0;
        var distinctBundles = new HashSet<string>();

        foreach (var dto in assetList)
        {
            if (string.IsNullOrWhiteSpace(dto.Address)) continue;

            string previewUrl = dto.PreviewUrl ?? "";

            // If client supplied base64 preview, save to assets/previews
            if (!string.IsNullOrEmpty(dto.Base64Preview))
            {
                var saveRes = SavePreviewFile(dto.Address, dto.Base64Preview);
                if (saveRes.IsSuccess)
                {
                    previewUrl = saveRes.Value ?? "";
                }
            }

            var record = new AddressableAssetRecord
            {
                Address = dto.Address,
                ReleaseVersion = resolvedVersion,
                AssetPath = dto.AssetPath ?? "",
                GroupName = !string.IsNullOrWhiteSpace(dto.GroupName) ? dto.GroupName : "Default",
                Labels = dto.Labels ?? "",
                BundleName = dto.BundleName ?? "",
                FileSize = dto.FileSize,
                Hash = dto.Hash ?? "",
                PreviewUrl = previewUrl,
                Status = "published",
                UpdatedAt = now
            };

            Exo.Database.Put(record);
            totalSize += dto.FileSize;
            if (!string.IsNullOrEmpty(dto.BundleName))
            {
                distinctBundles.Add(dto.BundleName);
            }
        }

        var release = new AddressableReleaseRecord
        {
            BuildNumber = nextBuildNumber,
            Version = resolvedVersion,
            Uploader = safeUploader,
            Badge = primaryBadge,
            Badges = badgeList,
            CatalogHash = catalogHash ?? Guid.NewGuid().ToString("N").Substring(0, 16),
            CatalogJson = catalogJson,
            BundleCount = distinctBundles.Count,
            TotalSize = totalSize,
            CreatedAt = now
        };

        Exo.Database.Put(release);
        Exo.Logger.Info($"[unity_addressables] Published build #{nextBuildNumber} (v{resolvedVersion}) by {safeUploader} with badges: {string.Join(", ", badgeList)} ({assetList.Count} assets)");

        return Result<AddressableReleaseRecord>.Ok(release);
    }

    [ExoAction]
    public Result<AddressableReleaseRecord> PromoteRelease(string version, string targetBadge)
    {
        if (string.IsNullOrWhiteSpace(version) || string.IsNullOrWhiteSpace(targetBadge))
        {
            return Result<AddressableReleaseRecord>.Fail("Version and target badge are required");
        }

        var releases = Exo.Database.All<AddressableReleaseRecord>() ?? Array.Empty<AddressableReleaseRecord>();
        var existing = releases.FirstOrDefault(r => r.Version == version || r.BuildNumber.ToString() == version);
        if (existing == null)
        {
            return Result<AddressableReleaseRecord>.Fail($"Release '{version}' not found");
        }

        var incomingBadges = targetBadge.Split(',', StringSplitOptions.RemoveEmptyEntries)
                                        .Select(t => t.Trim().ToLowerInvariant())
                                        .Where(t => !string.IsNullOrEmpty(t))
                                        .ToList();

        // Exclusive channel badges (latest, production, staging) uniquely point to this build
        var exclusiveChannels = new HashSet<string> { "latest", "production", "staging" };
        var incomingExclusives = incomingBadges.Where(b => exclusiveChannels.Contains(b)).ToList();

        if (incomingExclusives.Count > 0)
        {
            foreach (var other in releases.Where(r => r.Version != existing.Version))
            {
                var otherBadges = (other.Badges ?? new List<string> { other.Badge })
                    .Where(b => !incomingExclusives.Contains(b.ToLowerInvariant()))
                    .ToList();
                if (otherBadges.Count == 0) otherBadges.Add("archived");
                var updatedOther = other with { Badges = otherBadges, Badge = otherBadges[0] };
                Exo.Database.Put(updatedOther);
            }
        }

        var currentBadges = existing.Badges ?? new List<string> { existing.Badge };
        var mergedBadges = incomingBadges.Concat(currentBadges).Distinct().ToList();

        var updated = existing with { Badges = mergedBadges, Badge = mergedBadges[0] };
        Exo.Database.Put(updated);
        Exo.Logger.Info($"[unity_addressables] Promoted Build #{existing.BuildNumber} (v{existing.Version}) with badges: {string.Join(", ", mergedBadges)}");

        return Result<AddressableReleaseRecord>.Ok(updated);
    }

    [ExoAction]
    public Result<string> UploadBundle(string filename, string base64Data, string? subfolder = "bundles")
    {
        if (string.IsNullOrWhiteSpace(filename) || string.IsNullOrWhiteSpace(base64Data))
        {
            return Result<string>.Fail("Filename and base64Data are required");
        }

        try
        {
            var cleanName = Path.GetFileName(filename);
            var metadata = new
            {
                tag = "addressables",
                tags = new[] { "addressables" },
                subfolder = subfolder ?? "bundles"
            };

            var req = new FileBucketUploadFileRequest
            {
                Bucket = JsonSerializer.SerializeToElement("addressables"),
                Filename = cleanName,
                Content = JsonSerializer.SerializeToElement(base64Data),
                Metadata = JsonSerializer.SerializeToElement(metadata)
            };

            var res = Exo.FileBucket.UploadFileAsync(req).GetAwaiter().GetResult();
            if (res?.File.ValueKind == JsonValueKind.Object && res.File.TryGetProperty("url", out var urlProp))
            {
                string fileUrl = urlProp.GetString() ?? "";
                Exo.Logger.Info($"[unity_addressables] Uploaded bundle {cleanName} to file_bucket ({fileUrl})");
                return Result<string>.Ok(fileUrl);
            }

            string relativeUrl = $"/api/files/addressables/{cleanName}";
            Exo.Logger.Info($"[unity_addressables] Uploaded bundle {cleanName} to file_bucket");
            return Result<string>.Ok(relativeUrl);
        }
        catch (Exception ex)
        {
            Exo.Logger.Error($"[unity_addressables] Failed to upload bundle: {ex.Message}");
            return Result<string>.Fail(ex.Message);
        }
    }

    [ExoAction]
    public Result<string> UploadPreview(string address, string base64Image)
    {
        if (string.IsNullOrWhiteSpace(address) || string.IsNullOrWhiteSpace(base64Image))
        {
            return Result<string>.Fail("Address and base64Image are required");
        }

        var saveRes = SavePreviewFile(address, base64Image);
        if (!saveRes.IsSuccess) return saveRes;

        string url = saveRes.Value ?? "";
        var existing = Exo.Database.Get<AddressableAssetRecord>(address);
        if (existing != null)
        {
            Exo.Database.Put(existing with { PreviewUrl = url, UpdatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds() });
        }

        return Result<string>.Ok(url);
    }

    private Result<string> SavePreviewFile(string address, string base64)
    {
        try
        {
            // Strip data:image/...;base64, header if present
            int commaIdx = base64.IndexOf(',');
            string raw = commaIdx >= 0 ? base64.Substring(commaIdx + 1) : base64;

            string safeName = SanitizeFileName(address) + ".png";
            var metadata = new
            {
                tag = "addressables",
                tags = new[] { "addressables" },
                type = "preview",
                address
            };

            var req = new FileBucketUploadFileRequest
            {
                Bucket = JsonSerializer.SerializeToElement("addressables"),
                Filename = safeName,
                Content = JsonSerializer.SerializeToElement(raw),
                ContentType = JsonSerializer.SerializeToElement("image/png"),
                Metadata = JsonSerializer.SerializeToElement(metadata)
            };

            var res = Exo.FileBucket.UploadFileAsync(req).GetAwaiter().GetResult();
            if (res?.File.ValueKind == JsonValueKind.Object && res.File.TryGetProperty("url", out var urlProp))
            {
                string fileUrl = urlProp.GetString() ?? "";
                return Result<string>.Ok(fileUrl);
            }

            return Result<string>.Ok($"/api/files/addressables/{safeName}");
        }
        catch (Exception ex)
        {
            return Result<string>.Fail(ex.Message);
        }
    }

    private static string SanitizeFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var chars = name.Select(c => invalid.Contains(c) ? '_' : c).ToArray();
        return new string(chars);
    }
}
