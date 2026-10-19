/**
 * Self-contained Addressable Asset Input Web Component for Exoforge Studio.
 * Renders inline form preview, value selection, and interactive modal picker.
 */

class ExoAddressableInput extends HTMLElement {
  constructor() {
    super();
    this.currentValue = '';
    this.assets = [];
    this.groups = ['all'];
    this.selectedGroup = 'all';
    this.searchQuery = '';
    this.isModalOpen = false;
    this.isLoading = false;
    this._hasFetched = false;
  }

  static get observedAttributes() {
    return ['value', 'readonly', 'name'];
  }

  connectedCallback() {
    this.currentValue = this.getAttribute('value') || '';
    this.render();
    this.fetchAssets();
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (oldValue === newValue) return;
    if (name === 'value') {
      this.currentValue = newValue || '';
      this.render();
    }
  }

  async fetchAssets() {
    if (this._hasFetched) return;
    this.isLoading = true;
    try {
      let res = null;
      if (window.Exoforge && typeof window.Exoforge.callAction === 'function') {
        res = await window.Exoforge.callAction('unity_addressables', 'list_assets', {});
      } else if (window.Exoforge && typeof window.Exoforge.dispatch === 'function') {
        const d = await window.Exoforge.dispatch('unity_addressables', 'list_assets', {});
        res = d && d.status === 'ok' ? d.data : d;
      } else {
        const metaEl = document.querySelector("meta[name='csrf-token']");
        const csrf = metaEl ? metaEl.getAttribute('content') : '';
        const resp = await fetch('/api/dispatch', {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'content-type': 'application/json', 'x-csrf-token': csrf },
          body: JSON.stringify({ service: 'unity_addressables', action: 'list_assets', payload: {} })
        });
        const data = await resp.json();
        res = data && data.status === 'ok' ? data.data : data;
      }

      this.assets = Array.isArray(res) && res.length > 0 ? res : [
        { address: 'Background_CyberGrid', group_name: 'Backgrounds', labels: 'background,1080p,latest', file_size: 3571 },
        { address: 'Background_NeonGarden', group_name: 'Backgrounds', labels: 'background,1080p,latest', file_size: 2627 },
        { address: 'Background_DeepSpace', group_name: 'Backgrounds', labels: 'background,1080p,latest', file_size: 15826 }
      ];
      const grpSet = new Set(['all']);
      this.assets.forEach(a => {
        const g = a.group_name || a.GroupName || 'Default';
        if (g) grpSet.add(g);
      });
      this.groups = Array.from(grpSet);
      this._hasFetched = true;
    } catch (err) {
      console.error('[exo-addressable-input] Failed to load assets:', err);
      this.assets = [
        { address: 'Background_CyberGrid', group_name: 'Backgrounds', labels: 'background,1080p,latest', file_size: 3571 },
        { address: 'Background_NeonGarden', group_name: 'Backgrounds', labels: 'background,1080p,latest', file_size: 2627 },
        { address: 'Background_DeepSpace', group_name: 'Backgrounds', labels: 'background,1080p,latest', file_size: 15826 }
      ];
      this.groups = ['all', 'Backgrounds'];
    } finally {
      this.isLoading = false;
      this.render();
    }
  }

  setValue(newVal) {
    this.currentValue = newVal;
    this.setAttribute('value', newVal);
    const hiddenInputs = [
      this.querySelector('input[type="hidden"]'),
      this.parentElement ? this.parentElement.querySelector(`input[name="${this.getAttribute('name')}"]`) : null
    ];
    hiddenInputs.forEach(input => {
      if (input) {
        input.value = newVal;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
    this.dispatchEvent(new CustomEvent('change', { detail: { value: newVal }, bubbles: true }));
    this.render();
  }

  openModal() {
    this.isModalOpen = true;
    this.searchQuery = '';
    this.selectedGroup = 'all';
    if (!this._hasFetched) {
      this.fetchAssets();
    }
    this.render();
  }

  closeModal() {
    this.isModalOpen = false;
    this.render();
  }

  formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  }

  render() {
    const name = this.getAttribute('name') || 'addressable';
    const readonly = this.hasAttribute('readonly');
    const selectedAsset = this.assets.find(a => (a.address || a.Address) === this.currentValue);
    const grp = selectedAsset ? (selectedAsset.group_name || selectedAsset.GroupName || 'Default') : 'Addressable';

    const previewUrl = selectedAsset && selectedAsset.preview_url
      ? selectedAsset.preview_url
      : (this.currentValue ? `/api/plugins/unity_addressables/assets/previews/${this.currentValue}.png` : '');

    // Filter assets for modal
    const query = (this.searchQuery || '').toLowerCase().trim();
    const filteredAssets = this.assets.filter(a => {
      const g = a.group_name || a.GroupName || 'Default';
      const addr = (a.address || a.Address || '').toLowerCase();
      const path = (a.asset_path || a.AssetPath || '').toLowerCase();
      const labels = (a.labels || a.Labels || '').toLowerCase();

      const matchGrp = this.selectedGroup === 'all' || g === this.selectedGroup;
      const matchQuery = !query || addr.includes(query) || path.includes(query) || labels.includes(query);
      return matchGrp && matchQuery;
    });

    this.innerHTML = `
      <div class="exo-addressable-input-wrapper space-y-2">
        <input type="hidden" name="${name}" value="${this.currentValue}" />

        <div class="p-3 bg-gray-50 border border-gray-200 rounded-xl space-y-2">
          ${this.currentValue ? `
            <div class="flex items-center justify-between gap-3 bg-white p-2.5 rounded-lg border border-gray-100 shadow-2xs">
              <div class="flex items-center gap-2.5 min-w-0">
                <div class="w-10 h-10 rounded-lg border border-gray-100 bg-gray-900 overflow-hidden shrink-0 flex items-center justify-center">
                  <img
                    src="${previewUrl}"
                    class="w-full h-full object-contain"
                    alt="Preview"
                    onerror="this.onerror=null;this.parentElement.innerHTML='<span class=\\'text-lg\\'>📦</span>';"
                  />
                </div>
                <div class="truncate">
                  <span class="font-mono text-xs font-bold text-violet-700 bg-violet-50 px-2 py-0.5 rounded border border-violet-100">${this.currentValue}</span>
                  <div class="text-[10px] text-gray-400 mt-0.5">${grp} · Addressable Asset</div>
                </div>
              </div>
              ${!readonly ? `
                <div class="flex items-center gap-1 shrink-0">
                  <button
                    type="button"
                    class="exo-change-btn text-[11px] font-bold text-gray-700 hover:text-gray-900 px-2.5 py-1 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors cursor-pointer"
                  >
                    Change
                  </button>
                  <button
                    type="button"
                    class="exo-clear-btn text-[11px] font-bold text-red-600 hover:text-red-800 px-2 py-1 bg-red-50 hover:bg-red-100 rounded-lg transition-colors cursor-pointer"
                  >
                    ✕
                  </button>
                </div>
              ` : ''}
            </div>
          ` : `
            <div class="flex items-center justify-between gap-3">
              <span class="text-xs text-gray-400 italic">No Addressable selected</span>
              ${!readonly ? `
                <button
                  type="button"
                  class="exo-select-btn px-3 py-1.5 text-xs font-bold text-violet-700 bg-violet-50 hover:bg-violet-100 border border-violet-200 rounded-xl transition-colors shadow-2xs flex items-center gap-1.5 cursor-pointer"
                >
                  <span>📦</span>
                  <span>Select Addressable</span>
                </button>
              ` : ''}
            </div>
          `}
        </div>

        ${this.isModalOpen ? `
          <div class="exo-modal-backdrop fixed inset-0 z-50 overflow-y-auto bg-black/40 backdrop-blur-sm flex items-center justify-center p-4">
            <div class="bg-white rounded-2xl max-w-2xl w-full p-6 shadow-2xl border border-gray-200 space-y-4" onclick="event.stopPropagation()">
              <div class="flex items-center justify-between border-b border-gray-100 pb-3">
                <div class="flex items-center gap-2">
                  <span class="text-xl">📦</span>
                  <div>
                    <h3 class="text-sm font-bold text-gray-900">Select Addressable Asset</h3>
                    <p class="text-xs text-gray-400">Choose from published Unity Addressable assets</p>
                  </div>
                </div>
                <button type="button" class="exo-modal-close text-gray-400 hover:text-gray-600 font-bold text-sm cursor-pointer p-1">✕</button>
              </div>

              <!-- Filter tabs & Search bar -->
              <div class="flex flex-col sm:flex-row items-center justify-between gap-3">
                <div class="flex items-center gap-1.5 overflow-x-auto w-full sm:w-auto">
                  ${this.groups.map(g => `
                    <button
                      type="button"
                      data-group="${g}"
                      class="exo-group-btn px-3 py-1 text-xs font-semibold rounded-lg border transition-colors shrink-0 cursor-pointer ${this.selectedGroup === g ? 'bg-violet-600 text-white border-violet-600' : 'bg-white text-gray-600 border-gray-200 hover:bg-gray-50'}"
                    >
                      🏷️ ${g}
                    </button>
                  `).join('')}
                </div>

                <div class="relative w-full sm:w-56">
                  <input
                    type="text"
                    placeholder="Search addressables..."
                    value="${this.searchQuery}"
                    class="exo-search-input w-full text-xs pl-7 pr-3 py-1.5 bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-violet-500 font-mono"
                  />
                  <span class="absolute left-2.5 top-2 text-xs text-gray-400 pointer-events-none">🔍</span>
                </div>
              </div>

              <!-- Assets grid -->
              <div class="max-h-80 overflow-y-auto p-1 grid grid-cols-2 sm:grid-cols-3 gap-3">
                ${filteredAssets.length === 0 ? `
                  <div class="col-span-full py-12 text-center text-xs text-gray-400">
                    ${this.isLoading ? 'Loading addressable assets...' : `No addressable assets found matching filter.`}
                  </div>
                ` : filteredAssets.map(ast => {
                  const addr = ast.address || ast.Address;
                  const gName = ast.group_name || ast.GroupName || 'Default';
                  const labels = ast.labels || ast.Labels || '';
                  const size = this.formatBytes(ast.file_size || ast.FileSize || 0);
                  const pUrl = ast.preview_url || `/api/plugins/unity_addressables/assets/previews/${addr}.png`;
                  return `
                    <div
                      data-address="${addr}"
                      class="exo-asset-card p-2.5 rounded-xl border border-gray-200 hover:border-violet-400 hover:bg-violet-50/30 cursor-pointer transition-all flex flex-col justify-between group bg-white shadow-2xs"
                    >
                      <div class="h-24 bg-gray-900 rounded-lg mb-2 flex items-center justify-center overflow-hidden border border-gray-100 p-1">
                        <img
                          src="${pUrl}"
                          class="max-h-full max-w-full object-contain"
                          alt="${addr}"
                          onerror="this.onerror=null;this.parentElement.innerHTML='<span class=\\'text-2xl\\'>📦</span>';"
                        />
                      </div>
                      <div>
                        <p class="text-xs font-bold text-gray-800 truncate" title="${addr}">${addr}</p>
                        <div class="flex items-center justify-between text-[10px] text-gray-400 mt-1">
                          <span class="px-1.5 py-0.5 rounded bg-gray-100 text-gray-600 truncate">${gName}</span>
                          <span class="text-[9px] text-gray-400">${size}</span>
                        </div>
                      </div>
                      <button
                        type="button"
                        class="mt-2 w-full py-1 text-[11px] font-bold text-violet-700 bg-violet-50 group-hover:bg-violet-600 group-hover:text-white rounded-lg transition-colors text-center cursor-pointer pointer-events-none"
                      >
                        Select
                      </button>
                    </div>
                  `;
                }).join('')}
              </div>

              <!-- Footer -->
              <div class="flex items-center justify-end pt-3 border-t border-gray-100">
                <button
                  type="button"
                  class="exo-modal-close px-4 py-1.5 text-xs font-semibold text-gray-600 bg-gray-100 hover:bg-gray-200 rounded-xl transition-colors cursor-pointer"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        ` : ''}
      </div>
    `;

    // Attach event listeners
    const changeBtn = this.querySelector('.exo-change-btn');
    if (changeBtn) changeBtn.onclick = () => this.openModal();

    const selectBtn = this.querySelector('.exo-select-btn');
    if (selectBtn) selectBtn.onclick = () => this.openModal();

    const clearBtn = this.querySelector('.exo-clear-btn');
    if (clearBtn) clearBtn.onclick = () => this.setValue('');

    const closeBtns = this.querySelectorAll('.exo-modal-close');
    closeBtns.forEach(btn => btn.onclick = () => this.closeModal());

    const backdrop = this.querySelector('.exo-modal-backdrop');
    if (backdrop) {
      backdrop.onclick = (e) => {
        if (e.target === backdrop) this.closeModal();
      };
    }

    const groupBtns = this.querySelectorAll('.exo-group-btn');
    groupBtns.forEach(btn => {
      btn.onclick = () => {
        this.selectedGroup = btn.getAttribute('data-group') || 'all';
        this.render();
      };
    });

    const searchInput = this.querySelector('.exo-search-input');
    if (searchInput) {
      searchInput.oninput = (e) => {
        this.searchQuery = e.target.value;
        this.render();
        const updatedInput = this.querySelector('.exo-search-input');
        if (updatedInput) {
          updatedInput.focus();
          updatedInput.setSelectionRange(updatedInput.value.length, updatedInput.value.length);
        }
      };
    }

    const cards = this.querySelectorAll('.exo-asset-card');
    cards.forEach(card => {
      card.onclick = () => {
        const addr = card.getAttribute('data-address');
        if (addr) {
          this.setValue(addr);
          this.closeModal();
        }
      };
    });
  }
}

if (!customElements.get('exo-addressable-input')) {
  customElements.define('exo-addressable-input', ExoAddressableInput);
}

export { ExoAddressableInput };
