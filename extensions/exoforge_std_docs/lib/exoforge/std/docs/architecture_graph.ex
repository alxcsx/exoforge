defmodule Exoforge.Std.Docs.ArchitectureGraph do
  @moduledoc """
  Interactive SVG architecture topology and workflow pipeline visualizer for Exoforge.
  Renders system layers, Directed Acyclic Graph (DAG) dependency curves, and step-by-step
  inbound RPC and event pub/sub workflow simulations.
  """
  use Phoenix.Component

  # ---- Architecture Topology Definition ----

  @system_layers [
    %{
      id: "clients",
      title: "1. Client & Tooling Layer",
      icon: "🎮",
      badge: "Ingress Callers",
      color: "blue",
      nodes: [
        %{
          id: "unity_sdk",
          title: "Unity Client SDK",
          subtitle: "com.exoforge.sdk",
          desc: "C# Async/Await & reactive state bindings for Unity games.",
          icon: "🕹️",
          type: "Client"
        },
        %{
          id: "exo_cli",
          title: "Exo CLI & Engine",
          subtitle: "Management Engine",
          desc: "Project scaffolding, extension build/push, and stub generator.",
          icon: "💻",
          type: "Tooling"
        },
        %{
          id: "producer_studio",
          title: "Producer Studio",
          subtitle: "LiveView Dashboard :4005",
          desc: "Actor inspector, database browser, cluster metrics, and guide.",
          icon: "🎛️",
          type: "Studio"
        }
      ]
    },
    %{
      id: "gateways",
      title: "2. Transport & Gateway Layer",
      icon: "🔌",
      badge: "Ingress Normalization",
      color: "violet",
      nodes: [
        %{
          id: "ws_gateway",
          title: "WebSocket Gateway",
          subtitle: ":ws on port 4000",
          desc: "Real-time framed JSON WebSocket ingress & event subscription bus.",
          icon: "⚡",
          type: "Gateway"
        },
        %{
          id: "http_gateway",
          title: "HTTP REST Gateway",
          subtitle: ":http on port 4001",
          desc: "Dynamic OpenAPI REST endpoints derived from service contracts.",
          icon: "🌐",
          type: "Gateway"
        },
        %{
          id: "transport_layer",
          title: "Transport Abstraction",
          subtitle: ":transport service",
          desc: "Canonical request normalization, session auth verification & framing.",
          icon: "🔄",
          type: "Protocol"
        }
      ]
    },
    %{
      id: "kernel",
      title: "3. Kernel Core (Non-Extension Boundary)",
      icon: "⚡",
      badge: "The Rule: Immutable Kernel",
      color: "amber",
      nodes: [
        %{
          id: "action_dispatcher",
          title: "ActionDispatcher",
          subtitle: "Scope & Route Engine",
          desc: "Authorization scope verification (:guest, :player, :admin) & service routing.",
          icon: "🎯",
          type: "Kernel"
        },
        %{
          id: "event_dispatcher",
          title: "EventDispatcher",
          subtitle: ":pg Pub/Sub Bus",
          desc: "0.07 ms fanout over Erlang process groups with topic pattern matching.",
          icon: "📡",
          type: "Kernel"
        },
        %{
          id: "extension_registry",
          title: "ExtensionRegistry",
          subtitle: "In-Memory ETS Catalog",
          desc: "Zero-latency lockless service catalog, manifests, and contract schemas.",
          icon: "📚",
          type: "Kernel"
        },
        %{
          id: "extension_supervisor",
          title: "ExtensionSupervisor",
          subtitle: "OTP DAG Lifecycle",
          desc: "Topological DAG startup, process isolation, and actor recovery.",
          icon: "🛡️",
          type: "Kernel"
        }
      ]
    },
    %{
      id: "runtimes",
      title: "4. Extension Runtime & Services",
      icon: "🧩",
      badge: "Supervised Workers",
      color: "emerald",
      nodes: [
        %{
          id: "native_csharp",
          title: "Native C# Extensions",
          subtitle: ".NET Process Runner",
          desc: "IL trimmed & AOT tree-shaken single file running in isolated OS worker.",
          icon: "⚙️",
          type: "Native .NET"
        },
        %{
          id: "elixir_runner",
          title: "Elixir System Extensions",
          subtitle: "Actor Concurrency",
          desc: "Native OTP actor concurrency processes supervised in cluster tree.",
          icon: "🧪",
          type: "Elixir OTP"
        },
        %{
          id: "platform_services",
          title: "Standard Services",
          subtitle: "auth, player_data, cron",
          desc: "Pluggable contracts for identity, player profiles, scheduling & metering.",
          icon: "📦",
          type: "Services"
        }
      ]
    },
    %{
      id: "storage",
      title: "5. Storage & Persistence Layer",
      icon: "💾",
      badge: "Isolated Schema Storage",
      color: "cyan",
      nodes: [
        %{
          id: "database_manager",
          title: "Database Manager",
          subtitle: ":database service",
          desc: "Postgres & SQLite multi-engine support with per-extension schema isolation.",
          icon: "🗄️",
          type: "Storage"
        },
        %{
          id: "resource_store",
          title: "Resource Store",
          subtitle: ":resource_store",
          desc: "Schema-driven persistence with declarative typed CRUD & migrations.",
          icon: "📊",
          type: "Store"
        },
        %{
          id: "blob_storage",
          title: "File Bucket",
          subtitle: ":file_bucket CDN",
          desc: "Binary asset storage with metadata, tags, and streaming HTTP routes.",
          icon: "📁",
          type: "Blob"
        }
      ]
    }
  ]

  # ---- Workflow Steps Definition ----

  @action_workflow_steps [
    %{
      step: 1,
      id: "wf_client",
      title: "1. Client Ingress",
      actor: "Unity Game Client",
      action: "ExoforgeSDK.Client.SnakeLeaderboard().SubmitScoreAsync(1500)",
      description: "Game client serializes typed request record into a framed WebSocket action JSON frame or HTTP POST request.",
      wire_sample: """
      {
        "type": "action",
        "service": "snake_game",
        "action": "submit_score",
        "payload": { "score": 1500 },
        "id": "req_8492"
      }
      """,
      latency: "0.5 - 1.2 ms (Network RTT)",
      badge: "Ingress",
      color: "blue"
    },
    %{
      step: 2,
      id: "wf_gateway",
      title: "2. Gateway Sanitization",
      actor: "Transport Gateway (:ws / :http)",
      action: "Exoforge.Std.Transport.sanitize_payload/2",
      description: "The transport layer strips any unverified spoofed `_auth` fields and forcibly stamps caller's verified `player_id` from the session token.",
      wire_sample: """
      // Strips unverified spoofed auth; stamps verified session
      sanitized_payload = %{
        "score" => 1500,
        "player_id" => "usr_99a8b1",
        "_auth" => %{player_id: "usr_99a8b1", scopes: ["player"]}
      }
      """,
      latency: "< 0.05 ms",
      badge: "Security",
      color: "violet"
    },
    %{
      step: 3,
      id: "wf_dispatcher",
      title: "3. Scope Check & Routing",
      actor: "ActionDispatcher (Kernel)",
      action: "ActionDispatcher.dispatch(:snake_game, :submit_score, payload)",
      description: "Kernel checks whether caller scopes satisfy the action's contract scope (e.g. :guest, :player, :admin). Resolves provider in ExtensionRegistry.",
      wire_sample: """
      // Scope authorization check
      case verify_scope(manifest.scope, caller_scopes) do
        :ok -> route_to_worker(manifest.entry_point, payload)
        {:error, reason} -> refuse_with_code(403, :forbidden_scope)
      end
      """,
      latency: "< 0.02 ms (Lockless ETS)",
      badge: "Kernel",
      color: "amber"
    },
    %{
      step: 4,
      id: "wf_runner",
      title: "4. Extension Execution",
      actor: "Native .NET C# Worker (OS Process)",
      action: "SnakeExtension.SubmitScore(ScoreRecord record)",
      description: "Host sends newline-delimited JSON frame over stdio to the isolated .NET process. Generated ExoforgeDispatch maps method without reflection.",
      wire_sample: """
      // C# Action Execution via Stdio JSON Wire Protocol
      [ExoAction]
      public SnakeScoreSubmitted SubmitScore(int score) {
          Exo.Database.Put("snake_scores", PlayerId, new SnakeScore(score));
          return new SnakeScoreSubmitted(score, Rank: 1);
      }
      """,
      latency: "0.2 - 0.8 ms",
      badge: "Execution",
      color: "emerald"
    },
    %{
      step: 5,
      id: "wf_storage",
      title: "5. Isolated Schema Storage",
      actor: "Exoforge Database Layer (:database)",
      action: "Exo.Database.Put / Typed SQL",
      description: "Per-extension isolated SQLite/Postgres schema executes the query. No extension can read or modify another extension's tables without contract authorization.",
      wire_sample: """
      -- Isolated schema query executed by host bridge
      INSERT INTO ext_snake_game.scores (player_id, score, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (player_id) DO UPDATE SET score = EXCLUDED.score;
      """,
      latency: "< 0.3 ms",
      badge: "Persistence",
      color: "cyan"
    },
    %{
      step: 6,
      id: "wf_response",
      title: "6. Framed Return to Client",
      actor: "Transport Gateway ➔ Unity",
      action: "Exoforge.Std.Transport.format_action_result/3",
      description: "The response is packaged into a canonical JSON action_result frame matching the original request id and returned over WebSocket / HTTP.",
      wire_sample: """
      {
        "type": "action_result",
        "id": "req_8492",
        "status": "ok",
        "data": {
          "score": 1500,
          "rank": 1,
          "is_new_high_score": true
        }
      }
      """,
      latency: "< 0.1 ms framing",
      badge: "Egress",
      color: "blue"
    }
  ]

  @event_workflow_steps [
    %{
      step: 1,
      id: "ev_publish",
      title: "1. Extension Emits Event",
      actor: "Game Extension",
      action: "Exo.Events.Publish(\"snake.score_submitted\", payload)",
      description: "Extension publishes an event notification without needing to know who is listening.",
      wire_sample: """
      // Extension Host Call over Stdio
      {"type":"host_call", "op":"publish_event", "args":{"event":"snake.score_submitted", "payload":{"player_id":"usr_1", "score":1500}}}
      """,
      latency: "< 0.05 ms",
      badge: "Publish",
      color: "emerald"
    },
    %{
      step: 2,
      id: "ev_dispatcher",
      title: "2. Kernel Event Fanout",
      actor: "EventDispatcher & :pg Bus",
      action: "EventDispatcher.broadcast(\"snake.score_submitted\", payload)",
      description: "Kernel pattern-matches event name against active subscriptions and fans out via distributed Erlang process groups (:pg).",
      wire_sample: """
      // Fanout SLA: 0.07 ms to 50 concurrent subscribers over :pg
      :pg.get_members(:exo_events, topic)
      |> Enum.each(&send(&1, {:exo_event, topic, payload}))
      """,
      latency: "0.07 ms verified SLA",
      badge: "Kernel",
      color: "amber"
    },
    %{
      step: 3,
      id: "ev_gateway",
      title: "3. Gateway WebSocket Push",
      actor: "WebSocket Gateway (:ws)",
      action: "WebSock.push({:text, json})",
      description: "Gateway pushes the framed event frame directly down to subscribed game clients.",
      wire_sample: """
      {
        "type": "event",
        "event": "snake.score_submitted",
        "topic": "snake:leaderboard",
        "payload": {
          "player_id": "usr_1",
          "score": 1500
        }
      }
      """,
      latency: "< 0.1 ms",
      badge: "Realtime",
      color: "violet"
    },
    %{
      step: 4,
      id: "ev_client",
      title: "4. Client Hook Triggered",
      actor: "Unity Client SDK",
      action: "ExoforgeSDK.Events.Subscribe<SnakeScoreSubmitted>(...)",
      description: "Unity client receives event, deserializes payload into typed C# record, and triggers local gameplay reactive handlers.",
      wire_sample: """
      // Unity Client Subscription Hook
      ExoforgeSDK.Events.Subscribe<SnakeScoreSubmitted>("snake:leaderboard", evt => {
          LeaderboardUI.UpdateRank(evt.PlayerId, evt.Score);
      });
      """,
      latency: "< 1.5 ms total fanout",
      badge: "Gameplay",
      color: "blue"
    }
  ]

  # ---- Components ----

  attr(:active_tab, :string, default: "topology")
  attr(:selected_node_id, :string, default: "action_dispatcher")
  attr(:workflow_mode, :string, default: "action")
  attr(:active_step, :integer, default: 1)

  def visualizer(assigns) do
    assigns =
      assigns
      |> assign_new(:system_layers, fn -> @system_layers end)
      |> assign_new(:action_workflow_steps, fn -> @action_workflow_steps end)
      |> assign_new(:event_workflow_steps, fn -> @event_workflow_steps end)

    ~H"""
    <div class="space-y-8" id="exoforge-architecture-visualizer">
      <!-- Section Navigation Bar -->
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-gray-200">
        <div>
          <div class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-violet-50 text-violet-700 border border-violet-200 text-[10px] font-bold">
            <span class="w-1.5 h-1.5 rounded-full bg-violet-600 animate-pulse"></span>
            <span>Interactive Architecture &amp; Workflow Visualizer</span>
          </div>
          <h2 class="text-xl font-bold text-gray-900 tracking-tight mt-1">
            System Topology &amp; Execution Pipeline
          </h2>
          <p class="text-xs text-gray-500">
            Explore the layered architecture, kernel boundaries, and end-to-end data workflows.
          </p>
        </div>

        <!-- Visualizer Mode Controls -->
        <div class="flex items-center gap-2 p-1 bg-gray-100 rounded-xl border border-gray-200/80 text-xs font-semibold self-start sm:self-auto">
          <button
            type="button"
            onclick="document.getElementById('arch-view-topology').classList.remove('hidden'); document.getElementById('arch-view-workflow').classList.add('hidden'); document.getElementById('btn-tab-topology').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-tab-workflow').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
            id="btn-tab-topology"
            class="px-3 py-1.5 rounded-lg bg-white text-violet-700 shadow-xs transition-all flex items-center gap-1.5 cursor-pointer"
          >
            <span>🏗️</span>
            <span>System Layers</span>
          </button>
          <button
            type="button"
            onclick="document.getElementById('arch-view-workflow').classList.remove('hidden'); document.getElementById('arch-view-topology').classList.add('hidden'); document.getElementById('btn-tab-workflow').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-tab-topology').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
            id="btn-tab-workflow"
            class="px-3 py-1.5 rounded-lg text-gray-600 hover:text-gray-900 transition-all flex items-center gap-1.5 cursor-pointer"
          >
            <span>⚡</span>
            <span>Request &amp; Event Workflow</span>
          </button>
        </div>
      </div>

      <!-- VIEW 1: SYSTEM LAYERS & TOPOLOGY GRAPH -->
      <div id="arch-view-topology" class="space-y-6">
        <div class="grid grid-cols-1 lg:grid-cols-5 gap-4">
          <%= for layer <- @system_layers do %>
            <div class={"rounded-2xl border p-4 flex flex-col space-y-3 #{case layer.color do
              "blue" -> "bg-blue-50/50 border-blue-200/80"
              "violet" -> "bg-violet-50/50 border-violet-200/80"
              "amber" -> "bg-amber-50/50 border-amber-200/80"
              "emerald" -> "bg-emerald-50/50 border-emerald-200/80"
              "cyan" -> "bg-cyan-50/50 border-cyan-200/80"
            end}"}>
              <div class="flex items-center justify-between pb-2 border-b border-black/5">
                <div class="flex items-center gap-2">
                  <span class="text-base"><%= layer.icon %></span>
                  <span class="font-extrabold text-xs text-gray-900"><%= layer.title %></span>
                </div>
              </div>

              <div class="space-y-2 flex-1">
                <%= for node <- layer.nodes do %>
                  <div class="bg-white rounded-xl p-3 border border-gray-200/80 shadow-2xs hover:shadow-sm hover:border-violet-300 transition-all cursor-pointer group">
                    <div class="flex items-center justify-between gap-1 mb-1">
                      <div class="flex items-center gap-1.5">
                        <span class="text-sm"><%= node.icon %></span>
                        <span class="font-bold text-xs text-gray-900 group-hover:text-violet-700 transition-colors">
                          <%= node.title %>
                        </span>
                      </div>
                      <span class="text-[9px] font-mono px-1.5 py-0.5 rounded bg-gray-100 text-gray-600 font-bold">
                        <%= node.type %>
                      </span>
                    </div>
                    <div class="text-[10px] font-mono font-semibold text-violet-600 mb-1">
                      <%= node.subtitle %>
                    </div>
                    <p class="text-[11px] text-gray-500 leading-snug">
                      <%= node.desc %>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Architectural Litmus Test Banner -->
        <div class="bg-gradient-to-r from-violet-900 to-indigo-900 text-white rounded-2xl p-5 shadow-sm border border-violet-800">
          <div class="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div>
              <span class="text-[10px] font-bold uppercase tracking-wider text-violet-300">Architectural Doctrine</span>
              <h3 class="text-base font-extrabold tracking-tight mt-0.5">
                The 4-Question Litmus Test: "Should this be an extension?"
              </h3>
              <p class="text-xs text-violet-200 mt-1 max-w-3xl">
                The Rule: Everything above the kernel is an extension. The Exception: The kernel itself is not an extension.
              </p>
            </div>
            <div class="grid grid-cols-2 gap-2 text-[11px] font-mono">
              <div class="bg-white/10 px-3 py-1.5 rounded-lg border border-white/10">1. Swappable? ➔ <span class="text-emerald-300 font-bold">Extension</span></div>
              <div class="bg-white/10 px-3 py-1.5 rounded-lg border border-white/10">2. Depended on? ➔ <span class="text-emerald-300 font-bold">Extension</span></div>
              <div class="bg-white/10 px-3 py-1.5 rounded-lg border border-white/10">3. Bootstraps self? ➔ <span class="text-amber-300 font-bold">Kernel</span></div>
              <div class="bg-white/10 px-3 py-1.5 rounded-lg border border-white/10">4. Single domain? ➔ <span class="text-cyan-300 font-bold">Internal</span></div>
            </div>
          </div>
        </div>
      </div>

      <!-- VIEW 2: INTERACTIVE REQUEST & EVENT WORKFLOW PIPELINE -->
      <div id="arch-view-workflow" class="hidden space-y-6">
        <!-- Workflow Sub-Tabs -->
        <div class="flex items-center justify-between gap-4 p-2 bg-gray-50 rounded-2xl border border-gray-200">
          <div class="flex items-center gap-2">
            <button
              type="button"
              onclick="document.getElementById('wf-action-panel').classList.remove('hidden'); document.getElementById('wf-event-panel').classList.add('hidden'); document.getElementById('tab-wf-action').classList.add('bg-white', 'text-emerald-700', 'shadow-xs', 'font-bold'); document.getElementById('tab-wf-event').classList.remove('bg-white', 'text-emerald-700', 'shadow-xs', 'font-bold');"
              id="tab-wf-action"
              class="px-4 py-2 rounded-xl bg-white text-emerald-700 shadow-xs font-bold text-xs transition-all flex items-center gap-2 cursor-pointer"
            >
              <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
              <span>Action RPC Workflow (Client ➔ Worker)</span>
            </button>
            <button
              type="button"
              onclick="document.getElementById('wf-event-panel').classList.remove('hidden'); document.getElementById('wf-action-panel').classList.add('hidden'); document.getElementById('tab-wf-event').classList.add('bg-white', 'text-emerald-700', 'shadow-xs', 'font-bold'); document.getElementById('tab-wf-action').classList.remove('bg-white', 'text-emerald-700', 'shadow-xs', 'font-bold');"
              id="tab-wf-event"
              class="px-4 py-2 rounded-xl text-gray-600 hover:text-gray-900 text-xs transition-all flex items-center gap-2 cursor-pointer"
            >
              <span class="w-2 h-2 rounded-full bg-violet-500"></span>
              <span>Realtime Event Fanout (:pg Pub/Sub Bus)</span>
            </button>
          </div>
          <span class="text-[11px] font-mono text-gray-400 hidden sm:inline">
            Zero-Reflection Stdio Wire Framing
          </span>
        </div>

        <!-- PANEL A: ACTION RPC WORKFLOW -->
        <div id="wf-action-panel" class="space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for step <- @action_workflow_steps do %>
              <div class="bg-white rounded-2xl border border-gray-200 p-4 shadow-2xs hover:shadow-md transition-all flex flex-col space-y-3">
                <div class="flex items-center justify-between">
                  <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-full bg-gray-100 text-gray-700">
                    Step <%= step.step %>
                  </span>
                  <span class="text-[10px] font-mono font-semibold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-full">
                    <%= step.latency %>
                  </span>
                </div>

                <div>
                  <h4 class="font-bold text-sm text-gray-900 tracking-tight"><%= step.title %></h4>
                  <div class="text-[11px] font-mono font-semibold text-violet-700 mt-0.5"><%= step.actor %></div>
                  <p class="text-xs text-gray-600 mt-2 leading-relaxed"><%= step.description %></p>
                </div>

                <div class="mt-auto pt-2">
                  <div class="text-[10px] font-bold uppercase tracking-wider text-gray-400 mb-1">Payload / Frame</div>
                  <pre class="bg-gray-950 text-gray-200 p-2.5 rounded-xl font-mono text-[10px] overflow-x-auto border border-gray-800"><code><%= step.wire_sample %></code></pre>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- PANEL B: EVENT FANOUT WORKFLOW -->
        <div id="wf-event-panel" class="hidden space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <%= for step <- @event_workflow_steps do %>
              <div class="bg-white rounded-2xl border border-gray-200 p-4 shadow-2xs hover:shadow-md transition-all flex flex-col space-y-3">
                <div class="flex items-center justify-between">
                  <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-full bg-gray-100 text-gray-700">
                    Step <%= step.step %>
                  </span>
                  <span class="text-[10px] font-mono font-semibold text-violet-600 bg-violet-50 px-2 py-0.5 rounded-full">
                    <%= step.latency %>
                  </span>
                </div>

                <div>
                  <h4 class="font-bold text-sm text-gray-900 tracking-tight"><%= step.title %></h4>
                  <div class="text-[11px] font-mono font-semibold text-violet-700 mt-0.5"><%= step.actor %></div>
                  <p class="text-xs text-gray-600 mt-2 leading-relaxed"><%= step.description %></p>
                </div>

                <div class="mt-auto pt-2">
                  <div class="text-[10px] font-bold uppercase tracking-wider text-gray-400 mb-1">Wire Snippet</div>
                  <pre class="bg-gray-950 text-gray-200 p-2.5 rounded-xl font-mono text-[10px] overflow-x-auto border border-gray-800"><code><%= step.wire_sample %></code></pre>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def system_layers, do: @system_layers
  def action_workflow_steps, do: @action_workflow_steps
  def event_workflow_steps, do: @event_workflow_steps
end
