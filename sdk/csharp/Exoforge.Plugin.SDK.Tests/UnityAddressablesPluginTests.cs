using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Exoforge.Plugins.Generated;
using Exoforge.Plugins.UnityAddressables;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

public class UnityAddressablesPluginTests
{
    private class TestDatabase : IDatabase
    {
        public readonly Dictionary<(string table, string key), object> Storage = new();

        public T? Get<T>(string table, string key)
        {
            if (Storage.TryGetValue((table, key), out var val))
            {
                return (T)val;
            }
            return default;
        }

        public IReadOnlyList<T> All<T>(string table)
        {
            return Storage.Where(kvp => kvp.Key.table == table).Select(kvp => (T)kvp.Value).ToList();
        }

        public void Put<T>(string table, string key, T value)
        {
            Storage[(table, key)] = value!;
        }

        public void Delete(string table, string key)
        {
            Storage.Remove((table, key));
        }

        public IReadOnlyList<T> Query<T>(string sql, params object?[] args) => All<T>("");
        public T? QuerySingle<T>(string sql, params object?[] args) => default;
        public int Execute(string sql, params object?[] args) => 0;
    }

    [Fact]
    public void EmptyByDefault_WhenDatabaseEmpty()
    {
        var db = new TestDatabase();
        Exo.Reset();
        Exo.Database = db;
        var plugin = new UnityAddressablesPlugin();

        var stats = plugin.GetStats();

        Assert.Equal(0, stats.TotalAssets);
        Assert.Equal("latest", stats.ActiveBadge);
        Assert.Equal("none", stats.ActiveVersion);

        var assets = plugin.ListAssets();
        Assert.Empty(assets);

        var manifest = plugin.GetManifest("latest");
        Assert.Null(manifest);
    }

    [Fact]
    public void PublishRelease_AddsReleaseAndAssets_AndGetManifestWorks()
    {
        var db = new TestDatabase();
        Exo.Reset();
        Exo.Database = db;
        var plugin = new UnityAddressablesPlugin();

        var publishedAssets = new List<AddressableAssetDto>
        {
            new()
            {
                Address = "Background_CyberGrid",
                AssetPath = "Assets/SnakeGame/Backgrounds/Background_CyberGrid.png",
                GroupName = "Backgrounds",
                Labels = "background,cyberpunk,latest",
                BundleName = "backgrounds_assets_all.bundle",
                FileSize = 84320,
                Hash = "a1b2c3d4"
            },
            new()
            {
                Address = "Background_NeonGarden",
                AssetPath = "Assets/SnakeGame/Backgrounds/Background_NeonGarden.png",
                GroupName = "Backgrounds",
                Labels = "background,matrix,latest",
                BundleName = "backgrounds_assets_all.bundle",
                FileSize = 79450,
                Hash = "b2c3d4e5"
            }
        };

        var pubResult = plugin.PublishRelease("1.0.0", "latest", "catalog_hash_123", "{\"catalog\":true}", publishedAssets);
        Assert.True(pubResult.IsSuccess);
        Assert.NotNull(pubResult.Value);
        Assert.Equal("1.0.0", pubResult.Value!.Version);
        Assert.Equal("latest", pubResult.Value.Badge);

        var stats = plugin.GetStats();
        Assert.Equal(2, stats.TotalAssets);
        Assert.Equal("1.0.0", stats.ActiveVersion);
        Assert.Equal("latest", stats.ActiveBadge);

        // Test GetManifest by tag
        var manifest = plugin.GetManifest("latest");
        Assert.NotNull(manifest);
        Assert.Equal("1.0.0", manifest!.Version);
        Assert.Equal("latest", manifest.Tag);
        Assert.Equal("catalog_hash_123", manifest.CatalogHash);
        Assert.Equal(2, manifest.Assets.Count);

        // Test ListAssets with tag filter
        var tagged = plugin.ListAssets(tag: "latest");
        Assert.Equal(2, tagged.Count);

        var matrixOnly = plugin.ListAssets(search: "Neon");
        Assert.Single(matrixOnly);
        Assert.Equal("Background_NeonGarden", matrixOnly[0].Address);
    }

    [Fact]
    public void PromoteRelease_UpdatesBadge()
    {
        var db = new TestDatabase();
        Exo.Reset();
        Exo.Database = db;
        var plugin = new UnityAddressablesPlugin();

        plugin.PublishRelease("1.0.0", "latest", "hash1", null, new List<AddressableAssetDto>());

        var promoResult = plugin.PromoteRelease("1.0.0", "production");

        Assert.True(promoResult.IsSuccess);
        Assert.NotNull(promoResult.Value);
        Assert.Equal("production", promoResult.Value!.Badge);

        var stats = plugin.GetStats();
        Assert.Equal("production", stats.ActiveBadge);
    }

    private class TestActionDispatcher : IActionDispatcher
    {
        public Task<TResponse?> CallActionAsync<TResponse>(string service, string action, object payload)
            => Task.FromResult(CallAction<TResponse>(service, action, payload));

        public TResponse? CallAction<TResponse>(string service, string action, object payload)
        {
            if (service == "file_bucket" && action == "upload_file")
            {
                var json = System.Text.Json.JsonSerializer.Serialize(new
                {
                    file = new
                    {
                        id = "fl_test123",
                        bucket = "addressables",
                        filename = "test_assets.bundle",
                        url = "/api/files/addressables/fl_test123/test_assets.bundle"
                    }
                });
                return System.Text.Json.JsonSerializer.Deserialize<TResponse>(json);
            }
            return default;
        }
    }

    private class TestFileBucketService : IFileBucketService
    {
        public FileBucketUploadFileRequest? LastRequest { get; private set; }

        public Task<FileBucketUploadFileResponse?> UploadFileAsync(FileBucketUploadFileRequest request)
        {
            LastRequest = request;
            var fileJson = System.Text.Json.JsonSerializer.SerializeToElement(new
            {
                id = "fl_preview123",
                bucket = "addressables",
                filename = request.Filename,
                url = $"/api/files/addressables/fl_preview123/{request.Filename}"
            });

            return Task.FromResult<FileBucketUploadFileResponse?>(new FileBucketUploadFileResponse
            {
                File = fileJson
            });
        }

        public Task<FileBucketGetFileInfoResponse?> GetFileInfoAsync(FileBucketGetFileInfoRequest request) => Task.FromResult<FileBucketGetFileInfoResponse?>(null);
        public Task<FileBucketReadFileResponse?> ReadFileAsync(FileBucketReadFileRequest request) => Task.FromResult<FileBucketReadFileResponse?>(null);
        public Task<FileBucketListFilesResponse?> ListFilesAsync(FileBucketListFilesRequest request) => Task.FromResult<FileBucketListFilesResponse?>(null);
        public Task<FileBucketListBucketsResponse?> ListBucketsAsync(FileBucketListBucketsRequest request) => Task.FromResult<FileBucketListBucketsResponse?>(null);
        public Task<FileBucketListBucketsResponse?> ListBucketsAsync() => Task.FromResult<FileBucketListBucketsResponse?>(null);
        public Task<FileBucketUpdateFileResponse?> UpdateFileAsync(FileBucketUpdateFileRequest request) => Task.FromResult<FileBucketUpdateFileResponse?>(null);
        public Task<FileBucketDeleteFileResponse?> DeleteFileAsync(FileBucketDeleteFileRequest request) => Task.FromResult<FileBucketDeleteFileResponse?>(null);
    }

    [Fact]
    public void UploadBundle_UsesActionDispatcherFallback_WhenFileBucketNull()
    {
        var db = new TestDatabase();
        var actions = new TestActionDispatcher();
        Exo.Reset();
        Exo.Database = db;
        Exo.Actions = actions;
        var plugin = new UnityAddressablesPlugin();

        byte[] fakeData = System.Text.Encoding.UTF8.GetBytes("BUNDLE_DATA");
        string base64 = Convert.ToBase64String(fakeData);

        var uploadRes = plugin.UploadBundle("test_assets.bundle", base64, "bundles");

        Assert.True(uploadRes.IsSuccess);
        Assert.Equal("/api/files/addressables/fl_test123/test_assets.bundle", uploadRes.Value);
    }

    [Fact]
    public void UploadBundle_UsesFileBucketStub_WithAddressablesBucketAndTag()
    {
        var db = new TestDatabase();
        var fileBucket = new TestFileBucketService();
        Exo.Reset();
        Exo.Database = db;
        Exo.FileBucket = fileBucket;
        var plugin = new UnityAddressablesPlugin();

        byte[] fakeData = System.Text.Encoding.UTF8.GetBytes("BUNDLE_DATA");
        string base64 = Convert.ToBase64String(fakeData);

        var uploadRes = plugin.UploadBundle("test_assets.bundle", base64, "bundles");

        Assert.True(uploadRes.IsSuccess);
        Assert.Equal("/api/files/addressables/fl_preview123/test_assets.bundle", uploadRes.Value);
        Assert.NotNull(fileBucket.LastRequest);
        Assert.Equal("addressables", fileBucket.LastRequest!.Bucket.GetString());
        Assert.Equal("test_assets.bundle", fileBucket.LastRequest.Filename);
        Assert.Equal("addressables", fileBucket.LastRequest.Metadata.GetProperty("tag").GetString());
    }

    [Fact]
    public void UploadPreview_UsesFileBucketStub_AndUpdatesAssetRecord()
    {
        var db = new TestDatabase();
        var fileBucket = new TestFileBucketService();
        Exo.Reset();
        Exo.Database = db;
        Exo.FileBucket = fileBucket;
        var plugin = new UnityAddressablesPlugin();

        db.Put(UnityAddressablesPlugin.AssetsTable, "Cube_Asset", new AddressableAssetRecord
        {
            Address = "Cube_Asset",
            ReleaseVersion = "1.0.0"
        });

        string fakeImageBase64 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
        var previewRes = plugin.UploadPreview("Cube_Asset", fakeImageBase64);

        Assert.True(previewRes.IsSuccess);
        Assert.Equal("/api/files/addressables/fl_preview123/Cube_Asset.png", previewRes.Value);
        Assert.NotNull(fileBucket.LastRequest);
        Assert.Equal("addressables", fileBucket.LastRequest!.Bucket.GetString());
        Assert.Equal("Cube_Asset.png", fileBucket.LastRequest.Filename);
        Assert.Equal("image/png", fileBucket.LastRequest.ContentType.GetString());
        Assert.Equal("addressables", fileBucket.LastRequest.Metadata.GetProperty("tag").GetString());

        var updated = db.Get<AddressableAssetRecord>(UnityAddressablesPlugin.AssetsTable, "Cube_Asset");
        Assert.NotNull(updated);
        Assert.Equal(previewRes.Value, updated!.PreviewUrl);
    }
}
