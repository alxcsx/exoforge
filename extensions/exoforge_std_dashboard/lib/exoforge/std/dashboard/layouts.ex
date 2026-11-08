defmodule Exoforge.Std.Dashboard.Layouts do
  @moduledoc """
  Root and application layout components for the Exoforge Game Producer & Designer Studio.
  Design tokens and Dark/Light theme engine for the Exoforge Studio shell.
  """
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="dark">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>EXOFORGE - Game Producer & Designer Studio</title>
        <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
        <link rel="alternate icon" href="/favicon.ico" />
        <script>
          (function() {
            try {
              var saved = localStorage.getItem('exo_theme') || 'dark';
              var root = document.documentElement;
              if (saved === 'light') {
                root.classList.remove('dark');
                root.classList.add('light');
              } else {
                root.classList.remove('light');
                root.classList.add('dark');
              }
            } catch (e) {}
          })();
        </script>
        <link rel="stylesheet" href="/vendor/exoforge-studio.css">
        <!-- Tailwind CSS, vendored locally: instant load, no network dependency, and no
             third-party script the page does not control (M33 Fix 36) -->
        <script src="/vendor/tailwind.js"></script>
        <script>
          if (typeof tailwind !== 'undefined') {
            tailwind.config = {
              darkMode: 'class',
              theme: {
                extend: {
                  colors: {
                    primary: {
                      50: '#f5f3ff',
                      100: '#ede9fe',
                      200: '#ddd6fe',
                      300: '#c4b5fd',
                      400: '#a78bfa',
                      500: '#8b5cf6',
                      600: '#7c3aed',
                      700: '#6d28d9',
                      800: '#5b21b6',
                      900: '#4c1d95',
                    },
                    status: {
                      healthy: '#10b981',
                      warning: '#f59e0b',
                      error: '#ef4444'
                    }
                  },
                  boxShadow: {
                    'mac': '0 20px 40px -15px rgba(0,0,0,0.12), 0 0 0 1px rgba(0,0,0,0.06)',
                    'card': 'var(--exo-shadow-card)'
                  }
                }
              }
            };
          }
        </script>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Inter", sans-serif;
          }
          .pulse-live {
            box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.6);
            animation: pulse-ring 2s infinite;
          }
          @keyframes pulse-ring {
            0% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.6); }
            70% { box-shadow: 0 0 0 7px rgba(16, 185, 129, 0); }
            100% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }
          }
          .custom-scrollbar::-webkit-scrollbar {
            width: 5px;
            height: 5px;
          }
          .custom-scrollbar::-webkit-scrollbar-track {
            background: transparent;
          }
          .custom-scrollbar::-webkit-scrollbar-thumb {
            background: rgba(139, 92, 246, 0.35);
            border-radius: 9999px;
          }
          .prof-tab-btn { justify-content: flex-start; text-align: left; }
          .prof-tab-btn .prof-tab-label { min-width: 0; display: flex; align-items: center; gap: 0.625rem; }
          .prof-tab-btn .prof-tab-badge { margin-left: auto; flex-shrink: 0; }
          @keyframes flowDash {
            to { stroke-dashoffset: -24; }
          }
          .animate-flow-dash {
            stroke-dasharray: 6 5;
            animation: flowDash 1.4s linear infinite;
          }
          .network-node {
            transition: transform 0.15s ease, filter 0.15s ease;
          }
          .network-node:hover {
            filter: drop-shadow(0 0 10px rgba(139, 92, 246, 0.45));
          }
        </style>
        <script defer src="/vendor/phoenix.js"></script>
        <script defer src="/vendor/phoenix_live_view.js"></script>
        <script>
          window.ExoforgeTheme = {
            get: function() {
              try {
                return localStorage.getItem('exo_theme') || 'dark';
              } catch (e) {
                return 'dark';
              }
            },
            set: function(mode) {
              var next = mode === 'light' ? 'light' : 'dark';
              try { localStorage.setItem('exo_theme', next); } catch (e) {}
              var root = document.documentElement;
              root.classList.remove('dark', 'light');
              root.classList.add(next);
              window.dispatchEvent(new CustomEvent('exoforge:theme', { detail: { theme: next } }));
              return next;
            },
            toggle: function() {
              var current = document.documentElement.classList.contains('light') ? 'light' : 'dark';
              return this.set(current === 'dark' ? 'light' : 'dark');
            }
          };

          // One-click Code Copier
          window.exoCopyCode = function(btn) {
            if (!btn) return;
            var container = btn.closest('.relative, .group') || btn.parentElement;
            var pre = container ? container.querySelector('pre') : null;
            if (!pre) return;
            var text = pre.innerText || pre.textContent;
            navigator.clipboard.writeText(text).then(function() {
              var textSpan = btn.querySelector('.copy-text');
              var iconSpan = btn.querySelector('.copy-icon');
              var prevText = textSpan ? textSpan.textContent : '';
              var prevIcon = iconSpan ? iconSpan.textContent : '';
              if (textSpan) textSpan.textContent = 'Copied!';
              if (iconSpan) iconSpan.textContent = '✓';
              btn.classList.add('text-emerald-400', 'border-emerald-500/50');
              setTimeout(function() {
                if (textSpan) textSpan.textContent = prevText || 'Copy';
                if (iconSpan) iconSpan.textContent = prevIcon || '📋';
                btn.classList.remove('text-emerald-400', 'border-emerald-500/50');
              }, 2000);
            });
          };

          // Interactive Graph Engine: Pan/Zoom, 1-Hop Spotlight, Progressive Disclosure & Tracing
          window.ExoGraphEngine = (function() {
            var state = {};

            function getGraph(id) {
              if (!state[id]) {
                state[id] = {
                  scale: 1.0,
                  tx: 0,
                  ty: 0,
                  isPanning: false,
                  startX: 0,
                  startY: 0,
                  selectedNode: null,
                  collapsedGroups: {},
                  traceStep: 0,
                  traceTimer: null
                };
              }
              return state[id];
            }

            function applyTransform(graphId) {
              var s = getGraph(graphId);
              var viewport = document.getElementById(graphId + "-viewport");
              if (viewport) {
                viewport.style.transform = "translate(" + s.tx + "px, " + s.ty + "px) scale(" + s.scale + ")";
                viewport.style.transformOrigin = "0 0";
              }
              var zoomBadge = document.getElementById(graphId + "-zoom-level");
              if (zoomBadge) {
                zoomBadge.textContent = Math.round(s.scale * 100) + "%";
              }
            }

            return {
              zoom: function(graphId, factor) {
                var s = getGraph(graphId);
                var newScale = Math.min(2.5, Math.max(0.4, s.scale * factor));
                s.scale = newScale;
                applyTransform(graphId);
              },
              reset: function(graphId) {
                var s = getGraph(graphId);
                var container = document.getElementById(graphId + "-container");
                if (container) {
                  var cw = container.clientWidth || 1080;
                  s.scale = Math.min(1.0, Math.max(0.4, (cw - 32) / 1080));
                  s.tx = Math.max(0, (cw - 1080 * s.scale) / 2);
                  s.ty = 16;
                } else {
                  s.scale = 1.0;
                  s.tx = 0;
                  s.ty = 0;
                }
                applyTransform(graphId);
              },
              fit: function(graphId) {
                var container = document.getElementById(graphId + "-container");
                var viewport = document.getElementById(graphId + "-viewport");
                if (!container || !viewport) return;
                var cw = container.clientWidth;
                var ch = container.clientHeight;
                var s = getGraph(graphId);
                s.scale = Math.min(1.0, Math.max(0.35, Math.min((cw - 32) / 1080, (ch - 32) / 850)));
                s.tx = Math.max(0, (cw - 1080 * s.scale) / 2);
                s.ty = 16;
                applyTransform(graphId);
              },
              initPanZoom: function(graphId) {
                var container = document.getElementById(graphId + "-container");
                if (!container || container.dataset.panInit === "true") return;
                container.dataset.panInit = "true";
                var s = getGraph(graphId);

                // Auto-center on initial load
                if (s.tx === 0 && s.ty === 0 && s.scale === 1.0) {
                  var cw = container.clientWidth || 1080;
                  s.scale = Math.min(1.0, Math.max(0.4, (cw - 32) / 1080));
                  s.tx = Math.max(0, (cw - 1080 * s.scale) / 2);
                  s.ty = 16;
                  applyTransform(graphId);
                }

                container.style.cursor = "grab";

                function onPointerDown(e) {
                  if (e.target.closest("[data-graph-node]") || e.target.closest("button") || e.target.closest(".graph-docked-drawer")) return;
                  s.isPanning = true;
                  s.hasMoved = false;
                  s.startX = e.clientX - s.tx;
                  s.startY = e.clientY - s.ty;
                  container.style.cursor = "grabbing";
                  var viewport = document.getElementById(graphId + "-viewport");
                  if (viewport) viewport.style.transition = "none";
                  if (e.pointerId && container.setPointerCapture) {
                    try { container.setPointerCapture(e.pointerId); } catch(_) {}
                  }
                  e.preventDefault();
                }

                function onPointerMove(e) {
                  if (!s.isPanning) return;
                  s.hasMoved = true;
                  s.tx = e.clientX - s.startX;
                  s.ty = e.clientY - s.startY;
                  applyTransform(graphId);
                }

                function onPointerUp(e) {
                  if (!s.isPanning) return;
                  s.isPanning = false;
                  container.style.cursor = "grab";
                  var viewport = document.getElementById(graphId + "-viewport");
                  if (viewport) viewport.style.transition = "";
                  if (e && e.pointerId && container.releasePointerCapture) {
                    try { container.releasePointerCapture(e.pointerId); } catch(_) {}
                  }
                }

                container.addEventListener("pointerdown", onPointerDown);
                container.addEventListener("pointermove", onPointerMove);
                container.addEventListener("pointerup", onPointerUp);
                container.addEventListener("pointercancel", onPointerUp);

                // Mouse fallbacks
                container.addEventListener("mousedown", onPointerDown);
                window.addEventListener("mousemove", onPointerMove);
                window.addEventListener("mouseup", onPointerUp);

                container.addEventListener("wheel", function(e) {
                  e.preventDefault();
                  var factor = e.deltaY < 0 ? 1.08 : 0.92;
                  var newScale = Math.min(2.5, Math.max(0.35, s.scale * factor));
                  s.scale = newScale;
                  applyTransform(graphId);
                }, { passive: false });
              },
              toggleGroup: function(groupId, graphId) {
                graphId = graphId || "arch-graph";
                var s = getGraph(graphId);
                var isCollapsed = !s.collapsedGroups[groupId];
                s.collapsedGroups[groupId] = isCollapsed;

                var groupEls = document.querySelectorAll("[data-group-id='" + groupId + "']");
                var macroBox = document.querySelector("[data-macro-box='" + groupId + "']");
                var toggleBtn = document.querySelector("[data-toggle-group='" + groupId + "']");

                groupEls.forEach(function(el) {
                  if (isCollapsed) {
                    el.classList.add("hidden");
                  } else {
                    el.classList.remove("hidden");
                  }
                });

                if (macroBox) {
                  if (isCollapsed) {
                    macroBox.classList.remove("hidden");
                  } else {
                    macroBox.classList.add("hidden");
                  }
                }

                if (toggleBtn) {
                  toggleBtn.textContent = isCollapsed ? "+ Expand" : "− Collapse";
                }
              },
              expandAll: function(graphId) {
                graphId = graphId || "arch-graph";
                var s = getGraph(graphId);
                s.collapsedGroups = {};
                document.querySelectorAll("[data-group-id]").forEach(function(el) {
                  el.classList.remove("hidden");
                });
                document.querySelectorAll("[data-macro-box]").forEach(function(el) {
                  el.classList.add("hidden");
                });
                document.querySelectorAll("[data-toggle-group]").forEach(function(btn) {
                  btn.textContent = "− Collapse";
                });
              },
              collapseAll: function(graphId) {
                graphId = graphId || "arch-graph";
                var s = getGraph(graphId);
                document.querySelectorAll("[data-toggle-group]").forEach(function(btn) {
                  var gid = btn.dataset.toggleGroup;
                  if (gid) {
                    s.collapsedGroups[gid] = true;
                    btn.textContent = "+ Expand";
                  }
                });
                document.querySelectorAll("[data-group-id]").forEach(function(el) {
                  el.classList.add("hidden");
                });
                document.querySelectorAll("[data-macro-box]").forEach(function(el) {
                  el.classList.remove("hidden");
                });
              },
              spotlightNode: function(nodeEl, graphId) {
                if (!nodeEl) return;
                graphId = graphId || "arch-graph";
                var s = getGraph(graphId);
                var nodeId = nodeEl.dataset.nodeId;
                s.selectedNode = nodeId;

                var nodes = document.querySelectorAll(".network-node, .uml-comp-node");
                var edges = document.querySelectorAll(".graph-edge");
                var upstreamIds = (nodeEl.dataset.nodeUpstream || "").split(",").filter(Boolean);
                var downstreamIds = (nodeEl.dataset.nodeDownstream || "").split(",").filter(Boolean);

                nodes.forEach(function(n) {
                  var nid = n.dataset.nodeId;
                  if (nid === nodeId) {
                    n.style.opacity = "1.0";
                    n.classList.add("ring-selected");
                  } else if (upstreamIds.indexOf(nid) !== -1) {
                    n.style.opacity = "1.0";
                    n.classList.add("ring-upstream");
                  } else if (downstreamIds.indexOf(nid) !== -1) {
                    n.style.opacity = "1.0";
                    n.classList.add("ring-downstream");
                  } else {
                    n.style.opacity = "0.18";
                    n.classList.remove("ring-selected", "ring-upstream", "ring-downstream");
                  }
                });

                edges.forEach(function(e) {
                  var from = e.dataset.edgeFrom;
                  var to = e.dataset.edgeTo;
                  if (from === nodeId || to === nodeId) {
                    e.style.opacity = "1.0";
                    e.setAttribute("stroke-width", "2.8");
                    e.setAttribute("stroke", from === nodeId ? "#10b981" : "#f59e0b");
                  } else {
                    e.style.opacity = "0.12";
                    e.setAttribute("stroke-width", "1.5");
                    e.setAttribute("stroke", "#475569");
                  }
                });

                window.ExoGraphEngine.openInspector(nodeEl);
              },
              clearSpotlight: function(graphId) {
                graphId = graphId || "arch-graph";
                var s = getGraph(graphId);
                s.selectedNode = null;
                document.querySelectorAll(".network-node, .uml-comp-node").forEach(function(n) {
                  n.style.opacity = "1.0";
                  n.classList.remove("ring-selected", "ring-upstream", "ring-downstream");
                });
                document.querySelectorAll(".graph-edge").forEach(function(e) {
                  e.style.opacity = "0.6";
                  e.setAttribute("stroke-width", "1.8");
                  e.setAttribute("stroke", "#64748b");
                });
                window.ExoGraphEngine.closeInspector();
              },
              openInspector: function(nodeEl) {
                var d = nodeEl.dataset;
                var drawers = document.querySelectorAll(".graph-docked-drawer");
                drawers.forEach(function(drawer) {
                  var titleEl = drawer.querySelector(".drawer-title");
                  var subEl = drawer.querySelector(".drawer-subtitle");
                  var badgeEl = drawer.querySelector(".drawer-badge");
                  var descEl = drawer.querySelector(".drawer-desc");
                  var pkgEl = drawer.querySelector(".drawer-package");
                  var protoEl = drawer.querySelector(".drawer-protocol");
                  var iconEl = drawer.querySelector(".drawer-icon");
                  var upList = drawer.querySelector(".drawer-upstream-list");
                  var downList = drawer.querySelector(".drawer-downstream-list");

                  if (titleEl) titleEl.textContent = d.nodeTitle || "";
                  if (subEl) subEl.textContent = d.nodeSubtitle || "";
                  if (badgeEl) badgeEl.textContent = d.nodeBadge || "";
                  if (descEl) descEl.textContent = d.nodeDesc || "";
                  if (pkgEl) pkgEl.textContent = d.nodePackage || "";
                  if (protoEl) protoEl.textContent = d.nodeProtocol || "";
                  if (iconEl) iconEl.textContent = d.nodeIcon || "🧩";

                  if (upList) {
                    var up = (d.nodeUpstream || "").split(",").filter(Boolean);
                    if (up.length === 0) {
                      upList.innerHTML = '<span class="text-slate-500 italic text-[11px]">None (Root layer)</span>';
                    } else {
                      upList.innerHTML = up.map(function(item) {
                        return '<span class="px-2 py-0.5 rounded-lg bg-amber-400/15 text-amber-300 border border-amber-400/30 font-mono text-[10px]">' + item + '</span>';
                      }).join(' ');
                    }
                  }

                  if (downList) {
                    var down = (d.nodeDownstream || "").split(",").filter(Boolean);
                    if (down.length === 0) {
                      downList.innerHTML = '<span class="text-slate-500 italic text-[11px]">None (Terminal endpoint)</span>';
                    } else {
                      downList.innerHTML = down.map(function(item) {
                        return '<span class="px-2 py-0.5 rounded-lg bg-emerald-400/15 text-emerald-300 border border-emerald-400/30 font-mono text-[10px]">' + item + '</span>';
                      }).join(' ');
                    }
                  }

                  drawer.classList.remove("translate-x-full", "hidden");
                });
              },
              closeInspector: function() {
                document.querySelectorAll(".graph-docked-drawer").forEach(function(drawer) {
                  drawer.classList.add("translate-x-full");
                });
              },
              stepWorkflow: function(stepIndex, workflowType) {
                workflowType = workflowType || "action";
                var prefix = workflowType === "event" ? "ev_" : "wf_";
                var stepCards = document.querySelectorAll("[data-workflow-type='" + workflowType + "']");
                var total = stepCards.length;
                if (stepIndex < 1) stepIndex = 1;
                if (stepIndex > total) stepIndex = total;

                // Update counter
                var counter = document.getElementById("trace-step-counter");
                if (counter) counter.textContent = "Step " + stepIndex + " of " + total;

                // Highlight active step card and open accordion
                stepCards.forEach(function(card, idx) {
                  var current = idx + 1;
                  var details = card.closest("details");
                  if (current === stepIndex) {
                    card.classList.add("ring-2", "ring-violet-500", "bg-violet-50/30");
                    if (details) details.open = true;
                    card.scrollIntoView({ behavior: "smooth", block: "nearest" });
                  } else {
                    card.classList.remove("ring-2", "ring-violet-500", "bg-violet-50/30");
                  }
                });

                // Highlight corresponding node on graph
                var activeCard = document.querySelector("[data-workflow-type='" + workflowType + "'][data-step-num='" + stepIndex + "']");
                if (activeCard && activeCard.dataset.actorNode) {
                  var actorNode = document.querySelector("[data-node-id='" + activeCard.dataset.actorNode + "']");
                  if (actorNode) {
                    window.ExoGraphEngine.spotlightNode(actorNode);
                  }
                }
              }
            };
          })();

          window.exoOpenNodeDialog = function(el) {
            window.ExoGraphEngine.spotlightNode(el);
          };

          window.exoHighlightPackage = function(category) {
            var nodes = document.querySelectorAll(".network-node, .uml-comp-node");
            nodes.forEach(function(node) {
              var nodeCat = node.getAttribute("data-category");
              if (category === "all" || nodeCat === category) {
                node.style.opacity = "1.0";
              } else {
                node.style.opacity = "0.18";
              }
            });

            ["all", "kernel", "extension", "internal"].forEach(function(cat) {
              var btn = document.getElementById("pkg-btn-" + cat);
              if (btn) {
                if (cat === category) {
                  btn.classList.add("ring-2", "ring-offset-1", "ring-violet-500");
                } else {
                  btn.classList.remove("ring-2", "ring-offset-1", "ring-violet-500");
                }
              }
            });
          };

          document.addEventListener("click", function(e) {
            // Close open menus
            document.querySelectorAll("details.exo-menu[open]").forEach(function(menu) {
              if (!menu.contains(e.target)) {
                menu.removeAttribute("open");
              }
            });

            // Architecture Graph Node Click
            var nodeEl = e.target.closest("[data-graph-node]");
            if (nodeEl) {
              window.ExoGraphEngine.spotlightNode(nodeEl);
              return;
            }

            // Click canvas background to clear spotlight
            if (e.target.closest(".graph-canvas-bg")) {
              window.ExoGraphEngine.clearSpotlight();
            }
          });

          document.addEventListener("keydown", function(e) {
            if (e.key === "Escape") {
              window.ExoGraphEngine.clearSpotlight();
              var modal = document.getElementById("arch-graph-modal");
              if (modal) modal.classList.add("hidden");
            }
          });

          document.addEventListener("DOMContentLoaded", function() {
            if (window.LiveView && window.Phoenix) {
              const metaEl = document.querySelector("meta[name='csrf-token']");
              const csrfToken = metaEl ? metaEl.getAttribute("content") : "";

              const Hooks = {
                AutoDismissToast: {
                  mounted() {
                    const el = this.el;
                    const kind = el.dataset.kind || "info";
                    const timer = setTimeout(() => {
                      el.classList.add("opacity-0", "translate-x-4", "transition-all", "duration-300");
                      setTimeout(() => {
                        el.remove();
                        this.pushEvent("dismiss_toast", { kind: kind });
                      }, 300);
                    }, 3500);

                    el.addEventListener("click", () => {
                      clearTimeout(timer);
                      el.remove();
                      this.pushEvent("dismiss_toast", { kind: kind });
                    });
                  }
                },
                StudioDispatcher: {
                  mounted() {
                    window._studioDispatcher = this;
                  },
                  destroyed() {
                    if (window._studioDispatcher === this) {
                      window._studioDispatcher = null;
                    }
                  }
                },
                ArchGraph: {
                  mounted() {
                    if (window.ExoGraphEngine) {
                      window.ExoGraphEngine.initPanZoom('arch-graph');
                      window.ExoGraphEngine.initPanZoom('modal-arch-graph');
                    }
                  },
                  updated() {
                    if (window.ExoGraphEngine) {
                      window.ExoGraphEngine.initPanZoom('arch-graph');
                      window.ExoGraphEngine.initPanZoom('modal-arch-graph');
                    }
                  }
                },
                NavCapacity: {
                  mounted() {
                    this.calcCapacity = () => {
                      const w = window.innerWidth;
                      // Fits within one row - 1 according to responsive breakpoint:
                      let cap = 6;
                      if (w < 640) cap = 2;
                      else if (w < 768) cap = 3;
                      else if (w < 1024) cap = 4;
                      else if (w < 1280) cap = 6;
                      else if (w < 1536) cap = 8;
                      else cap = 10;

                      if (this._lastCap !== cap) {
                        this._lastCap = cap;
                        this.pushEvent("set_nav_capacity", { max_pinned: cap, screen_width: w });
                      }
                    };

                    this.calcCapacity();
                    this.resizeHandler = () => {
                      if (this._timer) clearTimeout(this._timer);
                      this._timer = setTimeout(this.calcCapacity, 150);
                    };
                    window.addEventListener('resize', this.resizeHandler);
                  },
                  destroyed() {
                    if (this.resizeHandler) window.removeEventListener('resize', this.resizeHandler);
                  }
                },
                MicrofrontendLoader: {
                  mounted() {
                    this.load();
                  },
                  updated() {
                    this.load();
                  },
                  load() {
                    const entry = this.el.dataset.entry;
                    const element = this.el.dataset.element;
                    if (!entry) return;
                    import(entry)
                      .then((mod) => {
                        console.log("[Exoforge MFE] Loaded successfully:", entry);
                        const customEl = element ? this.el.querySelector(element) : null;
                        const target = customEl || this.el;
                        if (customEl) {
                          customEl.style.display = 'block';
                        }
                        if (mod && typeof mod.mount === 'function') {
                          mod.mount(target);
                        } else if (customEl && typeof customEl.connectedCallback === 'function' && !customEl.hasChildNodes()) {
                          customEl.connectedCallback();
                        }
                      })
                      .catch((err) => {
                        console.error("[Exoforge MFE] Error loading module:", entry, err);
                        this.el.innerHTML = `
                          <div class="p-6 bg-red-50 border border-red-200 rounded-xl text-red-700">
                            <h3 class="font-bold text-sm">Failed to load plugin microfrontend</h3>
                            <p class="text-xs mt-1 text-red-600 font-mono">${err && err.message ? err.message : String(err)}</p>
                            <p class="text-[11px] text-gray-500 mt-2 font-mono">Entry: ${entry}</p>
                          </div>
                        `;
                      });
                  }
                }
              };

              const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
                params: { _csrf_token: csrfToken },
                hooks: Hooks
              });

              window.Exoforge = {
                httpBaseUri: "/api",
                theme: window.ExoforgeTheme,
                dispatch: async function(service, action, payload = {}) {
                  // 1. Primary: If LiveView WebSocket is connected, push over the socket (0 HTTP roundtrips)
                  if (window._studioDispatcher && window.liveSocket && window.liveSocket.isConnected()) {
                    return new Promise((resolve) => {
                      window._studioDispatcher.pushEvent("studio_dispatch", { service, action, payload }, (reply) => {
                        resolve(reply);
                      });
                    });
                  }

                  // 2. Fallback: If socket is disconnected or unavailable, fall back to standard HTTP REST
                  const csrf = metaEl ? metaEl.getAttribute("content") : "";
                  const cookieMatch = document.cookie.match(/(?:^|;\s*)exo_auth_token=([^;]+)/);
                  const token = cookieMatch ? decodeURIComponent(cookieMatch[1].trim()) : "";

                  const headers = {
                    "content-type": "application/json",
                    "x-csrf-token": csrf
                  };
                  if (token) {
                    headers["authorization"] = "Bearer " + token;
                  }

                  const resp = await fetch(`/api/${encodeURIComponent(service)}/${encodeURIComponent(action)}`, {
                    method: "POST",
                    credentials: "same-origin",
                    headers: headers,
                    body: JSON.stringify(payload)
                  });
                  return await resp.json();
                },
                callAction: async function(service, action, payload = {}) {
                  const res = await this.dispatch(service, action, payload);
                  if (res && res.status === "ok") {
                    return res.data;
                  }
                  throw new Error(res && res.error ? res.error : "Action failed");
                },
                notifySuccess: function(msg) {
                  console.log("[Exoforge Studio]", msg);
                  window.dispatchEvent(new CustomEvent("exoforge:toast", { detail: { message: msg, type: "success" } }));
                }
              };

              liveSocket.connect();
              window.liveSocket = liveSocket;
              console.log("[Exoforge Studio] Connected to BEAM via Phoenix LiveView!");

              window.addEventListener("exoforge:clip", function(e) {
                const text = (e.detail && e.detail.text) || (e.target && e.target.getAttribute("data-clip")) || "";
                if (text && navigator.clipboard) {
                  navigator.clipboard.writeText(text).then(() => {
                    if (window._studioDispatcher) {
                      window._studioDispatcher.pushEvent("show_toast", { kind: "info", message: "Copied to clipboard!" });
                    }
                  }).catch(function(err) {
                    console.warn("Clipboard copy failed", err);
                  });
                }
              });
            }
          });
        </script>
      </head>
      <body class="text-gray-800 bg-[#f3f4f6] min-h-screen flex flex-col antialiased selection:bg-primary-500 selection:text-white pb-20 md:pb-8">
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main id="studio-main" phx-hook="StudioDispatcher">
      <%= @inner_content %>
    </main>
    """
  end
end
