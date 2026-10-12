import { html, render, useState, useEffect, useMemo } from './vendor/htm-preact-standalone.js';

function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

async function invokeAction(service, action, payload = {}) {
  if (window.Exoforge && typeof window.Exoforge.callAction === 'function') {
    return await window.Exoforge.callAction(service, action, payload);
  }
  if (window.Exoforge && typeof window.Exoforge.dispatch === 'function') {
    const res = await window.Exoforge.dispatch(service, action, payload);
    return res && res.status === 'ok' ? res.data : res;
  }
  const metaEl = document.querySelector("meta[name='csrf-token']");
  const csrf = metaEl ? metaEl.getAttribute("content") : "";
  const resp = await fetch("/api/dispatch", {
    method: "POST",
    headers: { "content-type": "application/json", "x-csrf-token": csrf },
    body: JSON.stringify({ service, action, payload })
  });
  const data = await resp.json();
  return data && data.status === 'ok' ? data.data : data;
}

function notify(msg) {
  if (window.Exoforge && typeof window.Exoforge.notifySuccess === 'function') {
    window.Exoforge.notifySuccess(msg);
  } else {
    console.log('[Notification]', msg);
  }
}

function getTagBadgeColor(tag) {
  const t = (tag || '').toLowerCase();
  if (t === 'latest') return 'bg-emerald-100 text-emerald-800 border-emerald-200';
  if (t === 'production' || t === 'prod') return 'bg-purple-100 text-purple-800 border-purple-200';
  if (t === 'staging') return 'bg-amber-100 text-amber-800 border-amber-200';
  if (t === 'archived') return 'bg-gray-100 text-gray-600 border-gray-200';
  return 'bg-blue-100 text-blue-800 border-blue-200';
}

function AddressablesStudioApp() {
  const [stats, setStats] = useState({
    total_assets: 0,
    total_bundles: 0,
    total_size_bytes: 0,
    active_badge: 'latest',
    active_badges: ['latest'],
    active_version: '1',
    active_build_number: 1
  });
  const [releases, setReleases] = useState([]);
  const [assets, setAssets] = useState([]);
  const [selectedAsset, setSelectedAsset] = useState(null);
  const [selectedTagFilter, setSelectedTagFilter] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [copiedKey, setCopiedKey] = useState(null);
  const [promoteModalRelease, setPromoteModalRelease] = useState(null);
  const [manifestModalTag, setManifestModalTag] = useState(null);
  const [manifestData, setManifestData] = useState(null);
  const [tagInput, setTagInput] = useState('production');
  const [selectedBadges, setSelectedBadges] = useState(['production']);
  const [expandedNodes, setExpandedNodes] = useState(new Set());

  const loadData = async () => {
    setLoading(true);
    try {
      const [statsRes, releasesRes, assetsRes] = await Promise.all([
        invokeAction('unity_addressables', 'get_stats', {}),
        invokeAction('unity_addressables', 'list_releases', {}),
        invokeAction('unity_addressables', 'list_assets', {})
      ]);

      if (statsRes) {
        setStats({
          total_assets: statsRes.total_assets || 0,
          total_bundles: statsRes.total_bundles || 0,
          total_size_bytes: statsRes.total_size_bytes || 0,
          active_badge: statsRes.active_badge || 'latest',
          active_badges: Array.isArray(statsRes.active_badges) ? statsRes.active_badges : [statsRes.active_badge || 'latest'],
          active_version: statsRes.active_version || '1',
          active_build_number: statsRes.active_build_number || 1
        });
      }

      const relList = Array.isArray(releasesRes) ? releasesRes : [];
      setReleases(relList);

      const astList = Array.isArray(assetsRes) ? assetsRes : [];
      setAssets(astList);

      if (astList.length > 0) {
        setSelectedAsset(prev => (prev ? astList.find(a => a.address === prev.address) || astList[0] : astList[0]));
      } else {
        setSelectedAsset(null);
      }

      // Initialize default expanded state
      const initialExpanded = new Set();
      relList.forEach(rel => {
        initialExpanded.add(`build:${rel.version}`);
      });
      astList.forEach(ast => {
        const buildVer = ast.release_version || (relList[0] ? relList[0].version : '1');
        const gName = ast.group_name || 'Default';
        initialExpanded.add(`group:${buildVer}:${gName}`);
      });
      setExpandedNodes(initialExpanded);
    } catch (err) {
      console.error('[unity_addressables] Failed to load data:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const toggleNode = (nodeKey) => {
    setExpandedNodes(prev => {
      const next = new Set(prev);
      if (next.has(nodeKey)) {
        next.delete(nodeKey);
      } else {
        next.add(nodeKey);
      }
      return next;
    });
  };

  const expandAll = () => {
    const all = new Set();
    releases.forEach(rel => {
      all.add(`build:${rel.version}`);
    });
    assets.forEach(ast => {
      const buildVer = ast.release_version || (releases[0] ? releases[0].version : '1');
      const gName = ast.group_name || 'Default';
      all.add(`group:${buildVer}:${gName}`);
    });
    setExpandedNodes(all);
  };

  const collapseAll = () => {
    setExpandedNodes(new Set());
  };

  // Distinct tags present across all published builds
  const availableBuildTags = useMemo(() => {
    const tags = new Set(['all']);
    releases.forEach(r => {
      if (Array.isArray(r.badges)) {
        r.badges.forEach(b => tags.add(b.toLowerCase()));
      } else if (r.badge) {
        tags.add(r.badge.toLowerCase());
      }
    });
    if (stats.active_badge && stats.active_badge !== 'none') {
      tags.add(stats.active_badge.toLowerCase());
    }
    return Array.from(tags);
  }, [releases, stats.active_badge]);

  // Compute hierarchical Tree structure: Builds -> Groups -> Assets
  const treeData = useMemo(() => {
    let targetReleases = releases;
    if (targetReleases.length === 0 && assets.length > 0) {
      targetReleases = [{
        build_number: 1,
        version: '1',
        uploader: 'developer',
        badge: 'latest',
        badges: ['latest'],
        bundle_count: stats.total_bundles || 1,
        total_size: stats.total_size_bytes || 0,
        created_at: Math.floor(Date.now() / 1000)
      }];
    }

    if (selectedTagFilter !== 'all') {
      targetReleases = targetReleases.filter(r => {
        const list = Array.isArray(r.badges) && r.badges.length > 0 ? r.badges : [r.badge];
        return list.some(b => (b || '').toLowerCase() === selectedTagFilter.toLowerCase());
      });
    }

    const query = searchQuery.toLowerCase().trim();

    return targetReleases.map(rel => {
      // Collect assets for this build
      const relAssets = assets.filter(a => {
        if (a.release_version && releases.length > 1) {
          return a.release_version === rel.version || a.release_version === String(rel.build_number);
        }
        return true;
      });

      // Group assets by group_name
      const groupsMap = new Map();
      relAssets.forEach(a => {
        const gName = a.group_name || 'Default';
        if (!groupsMap.has(gName)) {
          groupsMap.set(gName, []);
        }
        groupsMap.get(gName).push(a);
      });

      // Filter groups and assets by query
      const groups = Array.from(groupsMap.entries()).map(([gName, gAssets]) => {
        const filteredAssets = gAssets.filter(a => {
          if (!query) return true;
          return (
            (a.address && a.address.toLowerCase().includes(query)) ||
            (a.asset_path && a.asset_path.toLowerCase().includes(query)) ||
            (a.labels && a.labels.toLowerCase().includes(query)) ||
            (a.bundle_name && a.bundle_name.toLowerCase().includes(query)) ||
            gName.toLowerCase().includes(query)
          );
        });

        const totalGroupSize = filteredAssets.reduce((sum, a) => sum + (a.file_size || 0), 0);
        return {
          name: gName,
          key: `group:${rel.version}:${gName}`,
          assets: filteredAssets,
          totalSize: totalGroupSize
        };
      }).filter(g => g.assets.length > 0 || !query);

      const totalBuildAssets = groups.reduce((acc, g) => acc + g.assets.length, 0);

      // Collect badges array for build
      const buildBadges = Array.isArray(rel.badges) && rel.badges.length > 0 ? rel.badges : [rel.badge || 'latest'];

      return {
        release: rel,
        key: `build:${rel.version}`,
        badges: buildBadges,
        groups: groups,
        totalAssets: totalBuildAssets
      };
    }).filter(b => b.totalAssets > 0 || !query);
  }, [releases, assets, stats, selectedTagFilter, searchQuery]);

  const copyAddress = (key) => {
    navigator.clipboard.writeText(key);
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
    notify(`Copied "${key}" to clipboard`);
  };

  const openPromoteModal = (rel) => {
    setPromoteModalRelease(rel);
    const existing = Array.isArray(rel.badges) && rel.badges.length > 0 ? rel.badges : [rel.badge || 'latest'];
    setSelectedBadges(existing);
    setTagInput('');
  };

  const handlePromote = async () => {
    if (!promoteModalRelease) return;
    try {
      const merged = Array.from(new Set([...selectedBadges, ...(tagInput ? tagInput.split(',').map(s => s.trim()) : [])])).filter(Boolean);
      const targetBadgeStr = merged.join(',');

      const res = await invokeAction('unity_addressables', 'promote_release', {
        version: promoteModalRelease.version,
        target_badge: targetBadgeStr
      });
      if (res && res.is_success) {
        notify(`Updated badges for Build #${promoteModalRelease.build_number || promoteModalRelease.version}: ${targetBadgeStr}`);
        setPromoteModalRelease(null);
        await loadData();
      }
    } catch (err) {
      console.error('Failed to promote release:', err);
    }
  };

  const handleOpenManifest = async (tag) => {
    try {
      const res = await invokeAction('unity_addressables', 'get_manifest', { tag: tag || 'latest' });
      setManifestData(res);
      setManifestModalTag(tag || 'latest');
    } catch (err) {
      console.error('Failed to get manifest:', err);
    }
  };

  // Find release metadata for selected asset
  const selectedAssetRelease = useMemo(() => {
    if (!selectedAsset) return null;
    return releases.find(r => r.version === selectedAsset.release_version || String(r.build_number) === selectedAsset.release_version) || releases[0] || null;
  }, [selectedAsset, releases]);

  return html`
    <div className="space-y-6">
      <!-- Top Header Banner -->
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-3 border-b border-gray-100">
        <div>
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center text-xl shadow-xs">
              📦
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-xl font-bold text-gray-900 tracking-tight">Unity Addressables</h1>
                <span className="text-xs font-mono text-purple-700 bg-purple-50 border border-purple-200 px-2.5 py-0.5 rounded-full font-bold">
                  Build #${stats.active_build_number || stats.active_version}
                </span>
                <div className="flex items-center gap-1">
                  ${(stats.active_badges || [stats.active_badge]).map(bg => html`
                    <span key=${bg} className=${`px-2 py-0.5 rounded-full text-[10px] font-bold border uppercase tracking-wider ${getTagBadgeColor(bg)}`}>
                      ${bg}
                    </span>
                  `)}
                </div>
              </div>
              <p className="text-xs text-gray-500 mt-0.5">
                Cloud Content Delivery & Addressable Asset Catalog with Immutable Builds & Multi-channel Tags
              </p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick=${loadData}
            className="px-3 py-2 bg-white hover:bg-gray-50 text-gray-700 border border-gray-200 rounded-xl text-xs font-semibold shadow-xs flex items-center gap-1.5 transition-colors"
          >
            <span className=${loading ? 'animate-spin' : ''}>🔄</span> Refresh
          </button>
          <button
            onClick=${() => handleOpenManifest(stats.active_badge)}
            className="px-3 py-2 bg-white hover:bg-gray-50 text-purple-700 border border-purple-200 rounded-xl text-xs font-semibold shadow-xs flex items-center gap-1.5 transition-colors"
          >
            <span>📜</span> View Manifest
          </button>
          <button
            onClick=${() => {
              const activeRel = releases.find(r => r.version === stats.active_version) || releases[0];
              if (activeRel) openPromoteModal(activeRel);
            }}
            disabled=${releases.length === 0}
            className="px-4 py-2 bg-purple-600 hover:bg-purple-700 disabled:opacity-50 text-white rounded-xl text-xs font-semibold shadow-xs flex items-center gap-1.5 transition-colors"
          >
            <span>🏷️</span> Manage Tags
          </button>
        </div>
      </div>

      <!-- Quick Metrics Summary -->
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs">
          <div className="text-[11px] font-bold text-gray-400 uppercase tracking-wider">Build Counter</div>
          <div className="text-2xl font-bold text-gray-900 mt-1">#${releases.length > 0 ? (releases[0].build_number || releases.length) : (assets.length > 0 ? 1 : 0)}</div>
          <div className="text-[11px] text-gray-400 mt-0.5">Auto-incremented releases</div>
        </div>

        <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs">
          <div className="text-[11px] font-bold text-gray-400 uppercase tracking-wider">Total Assets</div>
          <div className="text-2xl font-bold text-gray-900 mt-1">${stats.total_assets}</div>
          <div className="text-[11px] text-gray-400 mt-0.5">Addressable entries</div>
        </div>

        <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs">
          <div className="text-[11px] font-bold text-gray-400 uppercase tracking-wider">Content Footprint</div>
          <div className="text-2xl font-bold text-gray-900 mt-1">${formatBytes(stats.total_size_bytes)}</div>
          <div className="text-[11px] text-gray-400 mt-0.5">AssetBundles size</div>
        </div>

        <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs">
          <div className="text-[11px] font-bold text-gray-400 uppercase tracking-wider">Active Channel Tags</div>
          <div className="flex items-center gap-1 mt-1.5 flex-wrap">
            ${(stats.active_badges || [stats.active_badge]).map(bg => html`
              <span key=${bg} className=${`px-2 py-0.5 rounded-full text-xs font-bold uppercase border ${getTagBadgeColor(bg)}`}>
                ${bg}
              </span>
            `)}
          </div>
          <div className="text-[11px] text-gray-400 mt-0.5">Serving runtime client</div>
        </div>
      </div>

      ${assets.length === 0 ? html`
        <!-- Empty State -->
        <div className="p-12 text-center bg-white rounded-2xl border border-gray-200/80 shadow-xs space-y-3">
          <div className="w-16 h-16 mx-auto rounded-2xl bg-purple-50 text-purple-600 flex items-center justify-center text-3xl shadow-inner">
            📦
          </div>
          <h2 className="text-base font-bold text-gray-900">No Addressables Published Yet</h2>
          <p className="text-xs text-gray-500 max-w-md mx-auto leading-relaxed">
            Addressables content is built and uploaded directly from the Unity Editor. Open <b>Window → Exoforge → Addressables</b> in Unity and click <b>"Build & Publish Addressables to Exoforge"</b> to deploy incremental builds.
          </p>
        </div>
      ` : html`
        <!-- Tree View & Inspector Explorer -->
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
          <!-- Left 2 Cols: Hierarchical Tree Content -->
          <div className="lg:col-span-2 bg-white rounded-2xl border border-gray-200/80 shadow-xs overflow-hidden flex flex-col">
            <!-- Tree Toolbar -->
            <div className="p-4 border-b border-gray-100 flex flex-col gap-3 bg-gray-50/60">
              <div className="flex flex-col sm:flex-row gap-3 justify-between items-center">
                <!-- Search Filter -->
                <div className="relative w-full sm:w-80">
                  <span className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-gray-400 text-xs">🔍</span>
                  <input
                    type="text"
                    placeholder="Search address keys, paths, groups…"
                    value=${searchQuery}
                    onInput=${(e) => setSearchQuery(e.target.value)}
                    className="w-full pl-8 pr-3 py-1.5 bg-white border border-gray-200 rounded-xl text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:border-purple-500"
                  />
                </div>

                <!-- Tree Expand/Collapse Controls -->
                <div className="flex items-center gap-1.5 w-full sm:w-auto justify-end">
                  <button
                    onClick=${expandAll}
                    title="Expand all tree branches"
                    className="px-2.5 py-1.5 bg-white hover:bg-gray-50 border border-gray-200 rounded-lg text-xs font-medium text-gray-600 transition-colors shadow-2xs"
                  >
                    Expand All
                  </button>
                  <button
                    onClick=${collapseAll}
                    title="Collapse all tree branches"
                    className="px-2.5 py-1.5 bg-white hover:bg-gray-50 border border-gray-200 rounded-lg text-xs font-medium text-gray-600 transition-colors shadow-2xs"
                  >
                    Collapse All
                  </button>
                </div>
              </div>

              <!-- Build Tags Filter Row -->
              <div className="flex items-center gap-2 overflow-x-auto pt-2 border-t border-gray-200/60">
                <span className="text-[11px] font-bold text-gray-400 uppercase tracking-wider whitespace-nowrap">
                  Filter by Build Tag:
                </span>
                <div className="flex items-center gap-1.5 flex-wrap">
                  ${availableBuildTags.map(tag => html`
                    <button
                      key=${tag}
                      onClick=${() => setSelectedTagFilter(tag)}
                      className=${`px-2.5 py-0.5 rounded-full text-xs font-semibold transition-all ${
                        selectedTagFilter === tag
                          ? 'bg-purple-600 text-white shadow-xs'
                          : 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
                      }`}
                    >
                      ${tag === 'all' ? 'All Builds' : tag}
                    </button>
                  `)}
                </div>
              </div>
            </div>

            <!-- Tree Structure View -->
            <div className="p-4 space-y-3 min-h-[460px]">
              ${treeData.length === 0 ? html`
                <div className="p-12 text-center text-gray-400 text-xs">
                  No published builds match the selected filter.
                </div>
              ` : treeData.map(b => {
                const isBuildExpanded = expandedNodes.has(b.key);
                return html`
                  <!-- BUILD NODE (Level 1) -->
                  <div key=${b.key} className="border border-gray-200 rounded-xl overflow-hidden bg-white shadow-2xs">
                    <!-- Build Header -->
                    <div
                      onClick=${() => toggleNode(b.key)}
                      className="p-3 bg-gray-50 hover:bg-purple-50/40 cursor-pointer flex items-center justify-between gap-3 border-b border-gray-100 transition-colors select-none"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <button
                          onClick=${(e) => { e.stopPropagation(); toggleNode(b.key); }}
                          className="w-5 h-5 flex items-center justify-center text-gray-400 hover:text-gray-700 text-xs font-mono"
                        >
                          ${isBuildExpanded ? '▼' : '▶'}
                        </button>
                        <span className="text-base">📦</span>
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="font-bold text-gray-900 text-sm">
                            Build #${b.release.build_number || b.release.version}
                          </span>

                          <!-- Uploader Identifier -->
                          <span className="text-[11px] text-gray-500 font-normal bg-gray-100 px-2 py-0.5 rounded-md flex items-center gap-1">
                            <span>👤</span>
                            <span className="font-semibold text-gray-700">${b.release.uploader || 'developer'}</span>
                          </span>

                          <!-- Multiple Build Badges/Tags -->
                          <div className="flex items-center gap-1">
                            ${b.badges.map(bg => html`
                              <span key=${bg} className=${`px-2 py-0.5 rounded-full text-[10px] font-bold uppercase border shadow-2xs ${getTagBadgeColor(bg)}`}>
                                ${bg}
                              </span>
                            `)}
                          </div>
                        </div>
                      </div>

                      <div className="flex items-center gap-3">
                        <span className="text-xs text-gray-500 font-medium hidden sm:inline">
                          ${b.totalAssets} asset${b.totalAssets === 1 ? '' : 's'} • ${b.release.bundle_count || 1} bundle • ${formatBytes(b.release.total_size)}
                        </span>
                        <div className="flex items-center gap-1.5" onClick=${(e) => e.stopPropagation()}>
                          <button
                            onClick=${() => openPromoteModal(b.release)}
                            title="Manage / Promote channel tags for this build"
                            className="px-2.5 py-1 bg-white hover:bg-purple-50 text-purple-700 border border-purple-200 rounded-lg text-xs font-semibold shadow-2xs transition-colors"
                          >
                            🏷️ Tags
                          </button>
                          <button
                            onClick=${() => handleOpenManifest(b.badges[0] || 'latest')}
                            title="View CCD catalog manifest"
                            className="px-2.5 py-1 bg-white hover:bg-gray-100 text-gray-700 border border-gray-200 rounded-lg text-xs font-semibold shadow-2xs transition-colors"
                          >
                            📜
                          </button>
                        </div>
                      </div>
                    </div>

                    <!-- Build Contents: Groups & Assets -->
                    ${isBuildExpanded && html`
                      <div className="p-3 space-y-3 bg-gray-50/20">
                        ${b.groups.map(group => {
                          const isGroupExpanded = expandedNodes.has(group.key);
                          return html`
                            <!-- GROUP / FOLDER NODE (Level 2) -->
                            <div key=${group.key} className="border border-gray-200/80 rounded-xl bg-white overflow-hidden ml-2 sm:ml-4">
                              <!-- Group Folder Header -->
                              <div
                                onClick=${() => toggleNode(group.key)}
                                className="px-3 py-2 bg-gray-50/80 hover:bg-gray-100/70 cursor-pointer flex items-center justify-between gap-2 border-b border-gray-100 transition-colors select-none"
                              >
                                <div className="flex items-center gap-2 min-w-0">
                                  <button
                                    onClick=${(e) => { e.stopPropagation(); toggleNode(group.key); }}
                                    className="w-4 h-4 flex items-center justify-center text-gray-400 hover:text-gray-700 text-[11px] font-mono"
                                  >
                                    ${isGroupExpanded ? '▼' : '▶'}
                                  </button>
                                  <span className="text-sm">${isGroupExpanded ? '📂' : '📁'}</span>
                                  <span className="text-xs font-bold text-gray-800">
                                    ${group.name}
                                  </span>
                                  <span className="px-1.5 py-0.2 rounded-full text-[10px] font-semibold bg-gray-200/70 text-gray-600">
                                    ${group.assets.length}
                                  </span>
                                </div>
                                <span className="text-[11px] font-mono text-gray-400">
                                  ${formatBytes(group.totalSize)}
                                </span>
                              </div>

                              <!-- Group Leaf Assets (Level 3) -->
                              ${isGroupExpanded && html`
                                <div className="divide-y divide-gray-100">
                                  ${group.assets.map(asset => {
                                    const isSelected = selectedAsset && selectedAsset.address === asset.address;
                                    const labelsList = (asset.labels || '').split(',').map(s => s.trim()).filter(Boolean);
                                    return html`
                                      <div
                                        key=${asset.address}
                                        onClick=${() => setSelectedAsset(asset)}
                                        className=${`p-2.5 flex items-center justify-between gap-3 cursor-pointer transition-colors ${
                                          isSelected
                                            ? 'bg-purple-50/80 border-l-4 border-purple-600 pl-2 font-medium'
                                            : 'hover:bg-gray-50/80'
                                        }`}
                                      >
                                        <div className="flex items-center gap-2.5 min-w-0">
                                          <!-- Thumbnail preview or file icon -->
                                          <div className="w-8 h-8 rounded-lg bg-gray-100 border border-gray-200 overflow-hidden flex items-center justify-center flex-shrink-0 shadow-2xs">
                                            ${asset.preview_url ? html`
                                              <img src=${asset.preview_url} alt="" className="w-full h-full object-cover" />
                                            ` : html`
                                              <span className="text-xs">📄</span>
                                            `}
                                          </div>

                                          <div className="min-w-0">
                                            <div className="flex items-center gap-1.5 flex-wrap">
                                              <span className="text-xs font-mono text-gray-900 font-bold truncate">
                                                ${asset.address}
                                              </span>
                                              <!-- Unity asset labels (e.g. 1080p, background) -->
                                              ${labelsList.map(lbl => html`
                                                <span key=${lbl} className="px-1.5 py-0.2 rounded text-[9px] bg-purple-50 text-purple-700 font-medium">
                                                  ${lbl}
                                                </span>
                                              `)}
                                            </div>
                                            <div className="text-[10px] text-gray-400 font-sans truncate max-w-sm mt-0.5">
                                              ${asset.asset_path}
                                            </div>
                                          </div>
                                        </div>

                                        <div className="flex items-center gap-2.5 flex-shrink-0">
                                          <span className="text-[11px] font-mono text-gray-400">
                                            ${formatBytes(asset.file_size)}
                                          </span>
                                          <button
                                            onClick=${(e) => { e.stopPropagation(); copyAddress(asset.address); }}
                                            title="Copy Address Key"
                                            className="px-2 py-1 bg-white hover:bg-gray-100 border border-gray-200 rounded-lg text-[10px] text-gray-600 font-medium transition-colors shadow-2xs"
                                          >
                                            ${copiedKey === asset.address ? '✓ Copied' : '📋 Copy'}
                                          </button>
                                        </div>
                                      </div>
                                    `;
                                  })}
                                </div>
                              `}
                            </div>
                          `;
                        })}
                      </div>
                    `}
                  </div>
                `;
              })}
            </div>
          </div>

          <!-- Right Col: Asset Inspector Drawer -->
          <div className="bg-white rounded-2xl border border-gray-200/80 shadow-xs p-5 space-y-5">
            <div className="flex items-center justify-between pb-3 border-b border-gray-100">
              <h3 className="text-xs font-bold text-gray-900 uppercase tracking-wider flex items-center gap-1.5">
                <span>🔍</span> Asset Inspector
              </h3>
              ${selectedAsset && html`
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-purple-100 text-purple-800">
                  ${selectedAsset.group_name || 'Default'}
                </span>
              `}
            </div>

            ${selectedAsset ? html`
              <div className="space-y-4">
                <!-- Visual Thumbnail Preview -->
                <div className="w-full aspect-video rounded-xl bg-gray-900 border border-gray-200 overflow-hidden relative flex items-center justify-center shadow-inner">
                  ${selectedAsset.preview_url ? html`
                    <img src=${selectedAsset.preview_url} alt="" className="w-full h-full object-contain" />
                  ` : html`
                    <div className="text-gray-500 text-sm">No preview thumbnail available</div>
                  `}
                  <div className="absolute bottom-2 right-2 bg-black/60 backdrop-blur-xs text-white text-[10px] font-mono px-2 py-0.5 rounded">
                    ${formatBytes(selectedAsset.file_size)}
                  </div>
                </div>

                <!-- Address Key & Copy Input -->
                <div>
                  <label className="text-[11px] font-bold text-gray-500 uppercase">Address Key</label>
                  <div className="flex items-center gap-1.5 mt-1">
                    <input
                      type="text"
                      readOnly
                      value=${selectedAsset.address}
                      className="w-full px-2.5 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-xs font-mono text-gray-900 font-bold"
                    />
                    <button
                      onClick=${() => copyAddress(selectedAsset.address)}
                      className="px-2.5 py-1.5 bg-purple-600 hover:bg-purple-700 text-white rounded-lg text-xs font-medium whitespace-nowrap shadow-2xs"
                    >
                      ${copiedKey === selectedAsset.address ? '✓ Copied' : 'Copy'}
                    </button>
                  </div>
                </div>

                <!-- Build Information & Uploader -->
                <div className="p-3 bg-gray-50 rounded-xl border border-gray-200/70 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-[11px] font-bold text-gray-500 uppercase">Published Build</span>
                    <span className="text-xs font-bold text-gray-900 font-mono">
                      Build #${selectedAssetRelease ? (selectedAssetRelease.build_number || selectedAssetRelease.version) : (selectedAsset.release_version || stats.active_build_number)}
                    </span>
                  </div>

                  <div className="flex items-center justify-between text-xs">
                    <span className="text-gray-500">Uploaded by</span>
                    <span className="font-semibold text-gray-800 flex items-center gap-1">
                      <span>👤</span> ${selectedAssetRelease ? (selectedAssetRelease.uploader || 'developer') : 'developer'}
                    </span>
                  </div>

                  <div className="flex items-center justify-between text-xs pt-1 border-t border-gray-200/50">
                    <span className="text-gray-500">Channel Tags</span>
                    <div className="flex items-center gap-1 flex-wrap justify-end">
                      ${(selectedAssetRelease ? (selectedAssetRelease.badges || [selectedAssetRelease.badge]) : (stats.active_badges || [stats.active_badge])).map(bg => html`
                        <span key=${bg} className=${`px-2 py-0.5 rounded-full text-[10px] font-bold uppercase border ${getTagBadgeColor(bg)}`}>
                          ${bg}
                        </span>
                      `)}
                    </div>
                  </div>
                </div>

                <!-- Metadata Details List -->
                <div className="space-y-2 text-xs border-t border-gray-100 pt-3">
                  <div className="flex justify-between py-1 border-b border-gray-50">
                    <span className="text-gray-500">Unity Project Path</span>
                    <span className="font-mono text-gray-800 text-[11px] text-right truncate max-w-[190px]" title=${selectedAsset.asset_path}>
                      ${selectedAsset.asset_path}
                    </span>
                  </div>

                  <div className="flex justify-between py-1 border-b border-gray-50">
                    <span className="text-gray-500">Asset Group</span>
                    <span className="font-semibold text-gray-800 text-xs">
                      ${selectedAsset.group_name}
                    </span>
                  </div>

                  <div className="flex justify-between py-1 border-b border-gray-50">
                    <span className="text-gray-500">AssetBundle Archive</span>
                    <span className="font-mono text-gray-800 text-[11px] text-right truncate max-w-[190px]">
                      ${selectedAsset.bundle_name || 'default.bundle'}
                    </span>
                  </div>

                  <div className="flex justify-between py-1 border-b border-gray-50">
                    <span className="text-gray-500">Checksum (Hash)</span>
                    <span className="font-mono text-gray-800 text-[11px]">
                      ${selectedAsset.hash || 'e3b0c44298fc1c14'}
                    </span>
                  </div>

                  <div className="flex justify-between py-1 border-b border-gray-50">
                    <span className="text-gray-500">Unity Labels</span>
                    <span className="text-purple-700 font-semibold text-[11px]">
                      ${selectedAsset.labels || 'none'}
                    </span>
                  </div>

                  <div className="flex justify-between py-1 border-b border-gray-50">
                    <span className="text-gray-500">Status</span>
                    <span className="text-emerald-700 font-semibold bg-emerald-50 px-2 py-0.5 rounded text-[10px]">
                      ${selectedAsset.status || 'published'}
                    </span>
                  </div>
                </div>

                <!-- Integration Tip -->
                <div className="p-3 bg-purple-50/70 rounded-xl border border-purple-100 text-[11px] text-purple-900 leading-relaxed">
                  💡 <b>Game Integration:</b> Reference this address in config models with:
                  <code className="block mt-1 p-1 bg-white/80 rounded font-mono text-[10px] text-purple-800 border border-purple-200">
                    [ExoColumn(InputType = ExoInput.AddressableRef)]
                  </code>
                </div>
              </div>
            ` : html`
              <div className="text-center py-16 text-gray-400 text-xs">
                Select an asset from the tree to inspect details.
              </div>
            `}
          </div>
        </div>
      `}

      <!-- Promote Release / Manage Multiple Badges Modal -->
      ${promoteModalRelease && html`
        <div className="fixed inset-0 bg-black/40 backdrop-blur-xs flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl border border-gray-200 shadow-xl max-w-md w-full p-6 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-base font-bold text-gray-900">Manage Channel Tags</h3>
                <p className="text-xs text-gray-500">Build #${promoteModalRelease.build_number || promoteModalRelease.version} (Uploaded by ${promoteModalRelease.uploader || 'developer'})</p>
              </div>
              <button onClick=${() => setPromoteModalRelease(null)} className="text-gray-400 hover:text-gray-600 text-lg leading-none">✕</button>
            </div>

            <p className="text-xs text-gray-600 leading-relaxed">
              In Exoforge CCD, builds can have <b>multiple channel tags</b> (e.g. <code>latest</code>, <code>production</code>, <code>staging</code>). Runtime clients querying a tag will receive the catalog from this build.
            </p>

            <div className="space-y-3">
              <label className="text-xs font-semibold text-gray-700">Select Active Channel Badges</label>
              <div className="grid grid-cols-3 gap-2">
                ${['latest', 'staging', 'production'].map(badgeName => {
                  const isChecked = selectedBadges.includes(badgeName);
                  return html`
                    <button
                      type="button"
                      key=${badgeName}
                      onClick=${() => {
                        setSelectedBadges(prev => isChecked ? prev.filter(b => b !== badgeName) : [...prev, badgeName]);
                      }}
                      className=${`px-3 py-2 rounded-xl text-xs font-bold border transition-all text-center uppercase ${
                        isChecked
                          ? `${getTagBadgeColor(badgeName)} shadow-xs`
                          : 'bg-white text-gray-500 border-gray-200 hover:bg-gray-50'
                      }`}
                    >
                      ${isChecked ? `✓ ${badgeName}` : badgeName}
                    </button>
                  `;
                })}
              </div>

              <div className="space-y-1">
                <label className="text-[11px] font-semibold text-gray-600">Custom / Additional Tags (comma-separated):</label>
                <input
                  type="text"
                  placeholder="e.g. holiday_event, v1.2_patch"
                  value=${tagInput}
                  onInput=${(e) => setTagInput(e.target.value)}
                  className="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-xl text-xs text-gray-800 focus:outline-none focus:border-purple-500 font-mono"
                />
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2">
              <button
                onClick=${() => setPromoteModalRelease(null)}
                className="px-4 py-2 border border-gray-200 hover:bg-gray-50 text-gray-700 rounded-xl text-xs font-semibold transition-colors"
              >
                Cancel
              </button>
              <button
                onClick=${handlePromote}
                className="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-xl text-xs font-semibold shadow-xs transition-colors"
              >
                Save Channel Tags
              </button>
            </div>
          </div>
        </div>
      `}

      <!-- View CCD Manifest Modal -->
      ${manifestModalTag && html`
        <div className="fixed inset-0 bg-black/40 backdrop-blur-xs flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl border border-gray-200 shadow-xl max-w-2xl w-full p-6 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-base font-bold text-gray-900">Addressables Catalog Manifest</h3>
                <p className="text-xs text-gray-500">CCD manifest payload queried by runtime clients for tag <b>${manifestModalTag}</b></p>
              </div>
              <button onClick=${() => setManifestModalTag(null)} className="text-gray-400 hover:text-gray-600 text-lg leading-none">✕</button>
            </div>

            <div className="bg-gray-900 rounded-xl p-4 overflow-auto max-h-96">
              <pre className="text-xs font-mono text-emerald-400 whitespace-pre-wrap">
                ${manifestData ? JSON.stringify(manifestData, null, 2) : 'No manifest published yet.'}
              </pre>
            </div>

            <div className="flex justify-between items-center pt-2">
              <span className="text-xs text-gray-500">
                Channel Tag: <b className="text-purple-700 font-mono">${manifestData ? manifestData.tag : manifestModalTag}</b>
              </span>
              <button
                onClick=${() => setManifestModalTag(null)}
                className="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-xl text-xs font-semibold"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      `}
    </div>
  `;
}

export function mount(container) {
  try {
    render(html`<${AddressablesStudioApp} />`, container);
  } catch (err) {
    console.error("[unity_addressables] Render error:", err);
    if (container) {
      container.innerHTML = `
        <div class="p-6 bg-red-50 border border-red-200 rounded-xl text-red-700">
          <h3 class="font-bold text-sm">Failed to render Addressables Control Panel</h3>
          <p class="text-xs mt-1 font-mono">${err && err.message ? err.message : String(err)}</p>
        </div>
      `;
    }
  }
}

class ExoUnityAddressables extends HTMLElement {
  connectedCallback() {
    mount(this);
  }
}

if (!customElements.get('exo-unity-addressables')) {
  customElements.define('exo-unity-addressables', ExoUnityAddressables);
}
