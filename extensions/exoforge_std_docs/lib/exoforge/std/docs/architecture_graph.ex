defmodule Exoforge.Std.Docs.ArchitectureGraph do
  @moduledoc """
  Interactive Network Architecture Diagram, In-Graph Inspection Dialog, Fullscreen Maximizer,
  and Sequential Workflow Pipeline Visualizer for Exoforge.
  """
  use Phoenix.Component

  # ---- Architecture Components Specification ----

  @components [
    # Ingress (x: 35)
    %{
      id: "unity_client",
      title: "Unity Client SDK",
      subtitle: "com.exoforge.sdk",
      desc: "Client runtime with async/await stubs, device anonymous auth, and reactive event hooks.",
      icon: "🕹️",
      package: "Client Ingress",
      category: "client",
      badge: "GAME CLIENT",
      protocol: "WebSocket / HTTP RPC",
      x: 35,
      y: 135,
      width: 175,
      height: 80
    },
    %{
      id: "exo_cli",
      title: "Exo CLI & Engine",
      subtitle: "Management Engine",
      desc: "Local dev engine, Roslyn generator, C# extension compiler, and remote cluster push.",
      icon: "💻",
      package: "Developer Tooling",
      category: "tooling",
      badge: "DEV TOOLING",
      protocol: "HTTP Administration",
      x: 35,
      y: 280,
      width: 175,
      height: 80
    },
    %{
      id: "producer_studio",
      title: "Producer Studio",
      subtitle: "LiveView Dashboard :4005",
      desc: "Web-based actor inspector, live cluster metrics, extension lifecycle manager, and dev guide.",
      icon: "🎛️",
      package: "Studio Operations",
      category: "studio",
      badge: "STUDIO UI",
      protocol: "Phoenix LiveView",
      x: 35,
      y: 425,
      width: 175,
      height: 80
    },

    # Gateways (x: 245)
    %{
      id: "ws_gateway",
      title: "WebSocket Gateway",
      subtitle: ":ws on port 4000",
      desc: "Real-time framed JSON WebSocket ingress and low-latency bidirectional pub/sub event bus.",
      icon: "⚡",
      package: "Gateway Layer",
      category: "extension",
      badge: "GATEWAY EXTENSION",
      protocol: "Framed JSON Socket",
      x: 245,
      y: 135,
      width: 180,
      height: 80
    },
    %{
      id: "transport_layer",
      title: "Transport Abstraction",
      subtitle: ":transport service",
      desc: "Strips unverified client spoofed fields, stamps verified player credentials, and normalizes RPCs.",
      icon: "🔄",
      package: "Gateway Layer",
      category: "extension",
      badge: "GATEWAY EXTENSION",
      protocol: "Sanitized RPC Envelope",
      x: 245,
      y: 280,
      width: 180,
      height: 80
    },
    %{
      id: "http_gateway",
      title: "HTTP REST Gateway",
      subtitle: ":http on port 4001",
      desc: "Dynamic OpenAPI REST endpoints derived automatically from service action contracts.",
      icon: "🌐",
      package: "Gateway Layer",
      category: "extension",
      badge: "GATEWAY EXTENSION",
      protocol: "HTTP / OpenAPI JSON",
      x: 245,
      y: 425,
      width: 180,
      height: 80
    },

    # Kernel Core (Central Equilibrium Hub)
    %{
      id: "extension_registry",
      title: "ExtensionRegistry",
      subtitle: "In-Memory ETS Catalog",
      desc: "Lockless ETS table of registered extensions, action contracts, resources, and route metadata.",
      icon: "📚",
      package: "Kernel Core",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      protocol: "Direct ETS Lockless Read",
      x: 485,
      y: 48,
      width: 220,
      height: 72
    },
    %{
      id: "action_dispatcher",
      title: "ActionDispatcher",
      subtitle: "Scope & Route Engine",
      desc: "Zero-latency in-memory security scope verification (:guest, :player, :admin) & provider routing.",
      icon: "🎯",
      package: "Kernel Core",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      protocol: "In-Memory Zero-Copy",
      x: 475,
      y: 190,
      width: 240,
      height: 85
    },
    %{
      id: "event_dispatcher",
      title: "EventDispatcher",
      subtitle: ":pg Distributed Bus",
      desc: "Pattern-matched topic fanout over distributed process groups (0.07 ms SLA to 50 concurrent subscribers).",
      icon: "📡",
      package: "Kernel Core",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      protocol: "Erlang Process Groups (:pg)",
      x: 475,
      y: 340,
      width: 240,
      height: 85
    },
    %{
      id: "extension_supervisor",
      title: "ExtensionSupervisor",
      subtitle: "Topological OTP DAG",
      desc: "Starts extensions in topological dependency order, isolates worker failures, and restarts crashed actors.",
      icon: "🛡️",
      package: "Kernel Core",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      protocol: "OTP Supervision Tree",
      x: 485,
      y: 490,
      width: 220,
      height: 72
    },

    # Extension Workers (x: 765)
    %{
      id: "native_csharp",
      title: "Native C# Game Worker",
      subtitle: ".NET Single-File Process",
      desc: "Framework-dependent single-file binary with AOT trimming, zero reflection, and static dispatch delegates.",
      icon: "⚙️",
      package: "Extension Workers",
      category: "extension",
      badge: "GAME EXTENSION",
      protocol: "Newline-Delimited JSON stdio",
      x: 765,
      y: 135,
      width: 205,
      height: 85
    },
    %{
      id: "elixir_runner",
      title: "Elixir Extensions",
      subtitle: "OTP Actor Concurrency",
      desc: "System extensions running directly inside the Erlang/Elixir BEAM cluster supervision tree.",
      icon: "🧪",
      package: "Extension Workers",
      category: "extension",
      badge: "SYSTEM EXTENSION",
      protocol: "Direct BEAM Message Passing",
      x: 765,
      y: 280,
      width: 205,
      height: 80
    },
    %{
      id: "std_services",
      title: "Standard Services",
      subtitle: "auth, player_data, cron",
      desc: "Modular platform services providing token issuance, profile persistence, and cron scheduling.",
      icon: "📦",
      package: "Extension Workers",
      category: "extension",
      badge: "PLATFORM SERVICE",
      protocol: "Service Action Contracts",
      x: 765,
      y: 425,
      width: 205,
      height: 80
    },

    # Data & Storage Layer (x: 1010)
    %{
      id: "database_manager",
      title: "Database Manager",
      subtitle: ":database service",
      desc: "Multi-engine database service managing connection pools and per-extension schema isolation.",
      icon: "🗄️",
      package: "Data & Storage",
      category: "extension",
      badge: "STORAGE EXTENSION",
      protocol: "Connection Pool RPC",
      x: 1010,
      y: 135,
      width: 165,
      height: 80
    },
    %{
      id: "resource_store",
      title: "Resource Store",
      subtitle: ":resource_store",
      desc: "Schema-driven entity storage with declarative typed CRUD, migrations, and drawer definitions.",
      icon: "📊",
      package: "Data & Storage",
      category: "extension",
      badge: "STORAGE EXTENSION",
      protocol: "Typed Resource Schema",
      x: 1010,
      y: 280,
      width: 165,
      height: 80
    },
    %{
      id: "storage_adapters",
      title: "Isolated DB Schemas",
      subtitle: "SQLite / PostgreSQL Engine",
      desc: "Strictly isolated schema namespace (e.g. ext_snake_game) preventing cross-extension data leakage.",
      icon: "💾",
      package: "Data & Storage",
      category: "internal",
      badge: "INTERNAL ENGINE",
      protocol: "Isolated Schema SQL",
      x: 1010,
      y: 425,
      width: 165,
      height: 80
    }
  ]

  @edges [
    %{from: "unity_client", to: "ws_gateway", path: "M 210 175 L 245 175", label: "WebSocket"},
    %{from: "unity_client", to: "transport_layer", path: "M 210 175 C 230 175, 225 320, 245 320", label: "RPC Ingress"},
    %{from: "exo_cli", to: "transport_layer", path: "M 210 320 L 245 320", label: "Build Push"},
    %{from: "producer_studio", to: "http_gateway", path: "M 210 465 L 245 465", label: "REST / LiveView"},
    %{from: "ws_gateway", to: "action_dispatcher", path: "M 425 175 C 450 175, 450 225, 475 225", label: "dispatch"},
    %{from: "ws_gateway", to: "event_dispatcher", path: "M 425 175 C 450 175, 450 375, 475 375", label: ":pg pub/sub"},
    %{from: "transport_layer", to: "action_dispatcher", path: "M 425 320 C 450 320, 450 240, 475 240", label: "verified"},
    %{from: "http_gateway", to: "action_dispatcher", path: "M 425 465 C 455 465, 450 255, 475 255", label: "route"},
    %{from: "action_dispatcher", to: "extension_registry", path: "M 595 190 L 595 120", label: "catalog lookup"},
    %{from: "action_dispatcher", to: "native_csharp", path: "M 715 225 C 740 225, 740 175, 765 175", label: "stdio IPC"},
    %{from: "action_dispatcher", to: "elixir_runner", path: "M 715 235 C 740 235, 740 320, 765 320", label: "actor message"},
    %{from: "action_dispatcher", to: "std_services", path: "M 715 245 C 745 245, 740 465, 765 465", label: "dispatch"},
    %{from: "event_dispatcher", to: "extension_supervisor", path: "M 595 425 L 595 490", label: "health status"},
    %{from: "event_dispatcher", to: "native_csharp", path: "M 715 375 C 740 375, 740 190, 765 190", label: "event frame"},
    %{from: "native_csharp", to: "database_manager", path: "M 970 175 L 1010 175", label: "host_call"},
    %{from: "elixir_runner", to: "resource_store", path: "M 970 320 L 1010 320", label: "schema CRUD"},
    %{from: "std_services", to: "storage_adapters", path: "M 970 465 L 1010 465", label: "storage"},
    %{from: "database_manager", to: "storage_adapters", path: "M 1092 215 L 1092 425", label: "SQL isolation"}
  ]

  # ---- Workflow Steps Definition ----

  @action_workflow_steps [
    %{
      step: 1,
      id: "wf_client",
      title: "Client Action Request",
      actor: "Unity Game Client",
      action: "ExoforgeSDK.Client.SnakeLeaderboard().SubmitScoreAsync(1500)",
      summary: "Client serializes typed request record into a framed JSON packet sent over WebSocket or HTTP.",
      wire_sample: """
      {
        "type": "action",
        "service": "snake_game",
        "action": "submit_score",
        "payload": {
          "score": 1500
        },
        "id": "req_8492"
      }
      """,
      latency: "0.5 - 1.2 ms (Network RTT)",
      badge: "Ingress",
      color: "blue",
      details: "The Unity SDK formats the typed C# request into canonical JSON framing. An async Task is registered in the pending queue awaiting response with matching request id."
    },
    %{
      step: 2,
      id: "wf_gateway",
      title: "Gateway Sanitization & Auth Stamp",
      actor: "Transport Gateway (:ws / :http)",
      action: "Exoforge.Std.Transport.sanitize_payload/2",
      summary: "Transport strips unverified client spoofed fields and forcibly stamps verified player identity from the session token.",
      wire_sample: """
      {
        "action": "submit_score",
        "payload": {
          "score": 1500,
          "player_id": "usr_99a8b1"
        },
        "context": {
          "authenticated": true,
          "scopes": ["player"],
          "verified_at": "2026-11-07T21:00:00Z"
        }
      }
      """,
      latency: "< 0.05 ms",
      badge: "Security",
      color: "violet",
      details: "Clients can never forge their player_id or scopes. The gateway validates the cryptographic session token issued by the auth extension and stamps the verified context."
    },
    %{
      step: 3,
      id: "wf_dispatcher",
      title: "Scope Authorization & Provider Resolution",
      actor: "ActionDispatcher (Kernel)",
      action: "ActionDispatcher.dispatch(:snake_game, :submit_score, payload)",
      summary: "Kernel verifies that caller's scopes satisfy the contract requirements and resolves worker entry point in memory.",
      wire_sample: """
      {
        "kernel_dispatch": "ScopeAuthorizationCheck",
        "required_scope": "player",
        "caller_scopes": ["player"],
        "status": "authorized",
        "target_worker": "NativeWorker[snake_game]"
      }
      """,
      latency: "< 0.02 ms (Lockless ETS)",
      badge: "Kernel",
      color: "amber",
      details: "Pure lockless in-memory resolution. If caller has required scope (:guest, :player, :server, :studio), the request is dispatched immediately to the registered worker."
    },
    %{
      step: 4,
      id: "wf_runner",
      title: "Native C# Extension Execution",
      actor: "Native .NET Worker (OS Process)",
      action: "SnakeExtension.SubmitScore(ScoreRecord record)",
      summary: "Host delivers newline-delimited JSON frame over stdio to the isolated .NET OS process. Dispatch runs without reflection.",
      wire_sample: """
      [ExoAction]
      public SnakeScoreSubmitted SubmitScore(int score) {
          Exo.Database.Put("snake_scores", PlayerId, new SnakeScore(score));
          return new SnakeScoreSubmitted(score, Rank: 1);
      }
      """,
      latency: "0.2 - 0.8 ms",
      badge: "Execution",
      color: "emerald",
      details: "The framework-dependent .NET single-file worker deserializes the JSON arguments into typed records. Roslyn-generated ExoforgeDispatch maps method directly without reflection."
    },
    %{
      step: 5,
      id: "wf_storage",
      title: "Isolated Schema Database Query",
      actor: "Database Manager (:database)",
      action: "Exo.Database.Put / Typed SQL",
      summary: "Extension invokes host capability to persist data into its strictly isolated SQLite/PostgreSQL schema.",
      wire_sample: """
      -- Extension-isolated schema query executed via host bridge
      INSERT INTO ext_snake_game.scores (player_id, score, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (player_id) DO UPDATE SET score = EXCLUDED.score;
      """,
      latency: "< 0.3 ms",
      badge: "Persistence",
      color: "cyan",
      details: "Each extension has its own isolated schema namespace (e.g. ext_snake_game). No extension can access or modify another extension's data without authorized contract actions."
    },
    %{
      step: 6,
      id: "wf_response",
      title: "Framed Response Returned to Client",
      actor: "Transport Gateway ➔ Unity Client",
      action: "Exoforge.Std.Transport.format_action_result/3",
      summary: "Result is framed with status ok and matching request id, resolving the client async Task.",
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
      color: "blue",
      details: "The gateway writes the JSON frame back down the client socket. In Unity, the matching Task completion source is triggered and returns the strongly-typed C# record."
    }
  ]

  @event_workflow_steps [
    %{
      step: 1,
      id: "ev_publish",
      title: "Extension Publishes Event",
      actor: "Game Extension",
      action: "Exo.Events.Publish(\"snake.score_submitted\", payload)",
      summary: "Extension emits an event without knowing who or how many consumers are listening.",
      wire_sample: """
      {
        "type": "host_call",
        "op": "publish_event",
        "args": {
          "event": "snake.score_submitted",
          "topic": "snake:leaderboard",
          "payload": {
            "player_id": "usr_1",
            "score": 1500
          }
        }
      }
      """,
      latency: "< 0.05 ms",
      badge: "Publish",
      color: "emerald",
      details: "Extensions remain decoupled from event consumers. A single call sends the host_call frame to the host supervisor over the stdio pipe."
    },
    %{
      step: 2,
      id: "ev_dispatcher",
      title: "Kernel Event Fanout via High-Performance Bus",
      actor: "EventDispatcher (Kernel)",
      action: "EventDispatcher.broadcast(\"snake.score_submitted\", payload)",
      summary: "Kernel matches event against active topic subscribers and fans out over distributed process groups.",
      wire_sample: """
      {
        "event_bus": "ClusterDistributedPubSub",
        "topic": "snake:leaderboard",
        "sla": "0.07 ms fanout to 50 concurrent subscribers",
        "subscribers_matched": 50,
        "delivery": "zero_lock_direct_dispatch"
      }
      """,
      latency: "0.07 ms verified SLA",
      badge: "Kernel",
      color: "amber",
      details: "Cluster distributed pub/sub distributes messages directly to subscriber worker processes with zero central serialization bottleneck (0.07 ms verified SLA to 50 concurrent subscribers)."
    },
    %{
      step: 3,
      id: "ev_gateway",
      title: "Gateway Realtime Frame Push",
      actor: "WebSocket Gateway (:ws)",
      action: "WebSock.push({:text, json})",
      summary: "WebSocket gateway serializes the event frame and writes it down to subscribed client connections.",
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
      color: "violet",
      details: "The gateway handles connection multiplexing, backpressure, and per-client socket writes asynchronously."
    },
    %{
      step: 4,
      id: "ev_client",
      title: "Client Gameplay Hook Triggered",
      actor: "Unity Client SDK",
      action: "ExoforgeSDK.Events.Subscribe<SnakeScoreSubmitted>(...)",
      summary: "Unity client receives event, deserializes payload into typed C# record, and invokes gameplay listener.",
      wire_sample: """
      // Unity Client Subscription Handler
      ExoforgeSDK.Events.Subscribe<SnakeScoreSubmitted>("snake:leaderboard", evt => {
          LeaderboardUI.UpdateRank(evt.PlayerId, evt.Score);
      });
      """,
      latency: "< 1.5 ms total fanout",
      badge: "Gameplay",
      color: "blue",
      details: "Client-side code dispatches the event on Unity's main thread, enabling immediate UI updates, leaderboard refreshes, or audio triggers."
    }
  ]

  # ---- Components ----

  def visualizer(assigns) do
    assigns =
      assigns
      |> assign_new(:components, fn -> @components end)
      |> assign_new(:edges, fn -> @edges end)
      |> assign_new(:action_workflow_steps, fn -> @action_workflow_steps end)
      |> assign_new(:event_workflow_steps, fn -> @event_workflow_steps end)

    ~H"""
    <div class="space-y-8 select-none font-sans" id="exoforge-architecture-visualizer">
      <!-- Section Header -->
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-gray-200">
        <div>
          <div class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-violet-50 text-violet-700 border border-violet-200 text-[10px] font-bold">
            <span class="w-1.5 h-1.5 rounded-full bg-violet-600 animate-pulse"></span>
            <span>UML Subsystem Diagram &amp; Execution Pipeline</span>
          </div>
          <h2 class="text-xl font-bold text-gray-900 tracking-tight mt-1">
            System Topology, Packages &amp; Execution Flow
          </h2>
          <p class="text-xs text-gray-500">
            Interactive network architecture, in-graph component inspection dialog, and sequential workflow cascades.
          </p>
        </div>

        <!-- Mode Toggle: UML Architecture vs Sequential Workflow -->
        <div class="flex items-center gap-2 p-1 bg-gray-100 rounded-xl border border-gray-200/80 text-xs font-semibold self-start sm:self-auto">
          <button
            type="button"
            onclick="document.getElementById('arch-view-graph').classList.remove('hidden'); document.getElementById('arch-view-workflow').classList.add('hidden'); document.getElementById('btn-tab-graph').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-tab-workflow').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
            id="btn-tab-graph"
            class="px-3.5 py-1.5 rounded-lg bg-white text-violet-700 shadow-xs transition-all flex items-center gap-1.5 cursor-pointer"
          >
            <span>🕸️</span>
            <span>Network Architecture</span>
          </button>
          <button
            type="button"
            onclick="document.getElementById('arch-view-workflow').classList.remove('hidden'); document.getElementById('arch-view-graph').classList.add('hidden'); document.getElementById('btn-tab-workflow').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-tab-graph').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
            id="btn-tab-workflow"
            class="px-3.5 py-1.5 rounded-lg text-gray-600 hover:text-gray-900 transition-all flex items-center gap-1.5 cursor-pointer"
          >
            <span>⚡</span>
            <span>Sequential Workflow Cascade</span>
          </button>
        </div>
      </div>

      <!-- VIEW 1: NETWORK ARCHITECTURE COMPONENT DIAGRAM -->
      <div id="arch-view-graph" class="space-y-6">
        <!-- Core Philosophy: Microkernel & Pluggable Extensions -->
        <div class="bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 rounded-3xl p-6 text-white border border-slate-800 shadow-xl relative overflow-hidden">
          <div class="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div class="space-y-2 max-w-2xl">
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold font-mono tracking-wider px-2 py-0.5 rounded-full bg-amber-400/20 text-amber-300 border border-amber-400/30">
                  CORE PHILOSOPHY
                </span>
                <span class="text-xs text-slate-400">Microkernel &amp; Pluggable Extensions</span>
              </div>
              <h3 class="text-lg font-black tracking-tight text-white">
                Immutable Kernel Core + Pluggable Extensions
              </h3>
              <p class="text-xs text-slate-300 leading-relaxed">
                The kernel is strictly limited to four foundational primitives: <code class="text-amber-300 font-mono">ActionDispatcher</code>, <code class="text-amber-300 font-mono">EventDispatcher</code>, <code class="text-amber-300 font-mono">ExtensionRegistry</code>, and <code class="text-amber-300 font-mono">ExtensionSupervisor</code>. Everything else—gateways, auth, databases, and native C# game logic—is a pluggable extension.
              </p>
            </div>

            <!-- Simple Rule of Thumb Card -->
            <div class="bg-slate-800/90 p-4 rounded-2xl border border-slate-700 md:max-w-xs shrink-0 space-y-2 text-xs">
              <div class="font-bold text-amber-400 flex items-center gap-1.5">
                <span>💡</span>
                <span>Rule of Thumb</span>
              </div>
              <div class="text-slate-300 leading-snug">
                • <strong>Game logic, storage, or transport?</strong> ➔ <span class="text-emerald-400 font-semibold">Extension</span><br/>
                • <strong>Bootstrapping depends on it?</strong> ➔ <span class="text-amber-300 font-semibold">Kernel</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Diagram Toolbar: Maximize & Package Filters -->
        <div class="flex flex-wrap items-center justify-between gap-3 bg-white p-3 rounded-2xl border border-gray-200/80 shadow-2xs">
          <!-- Package Filters -->
          <div class="flex items-center gap-1.5 text-xs font-semibold">
            <span class="text-gray-400 text-[11px] mr-1 hidden sm:inline">Highlight Layer:</span>
            <button
              type="button"
              onclick="window.exoHighlightPackage('all')"
              id="pkg-btn-all"
              class="px-2.5 py-1 rounded-lg bg-slate-900 text-white shadow-2xs transition-all cursor-pointer text-xs"
            >
              All Layers
            </button>
            <button
              type="button"
              onclick="window.exoHighlightPackage('kernel')"
              id="pkg-btn-kernel"
              class="px-2.5 py-1 rounded-lg bg-amber-50 text-amber-700 border border-amber-200 hover:bg-amber-100 transition-all cursor-pointer text-xs flex items-center gap-1"
            >
              <span>⚡</span>
              <span>Kernel Core</span>
            </button>
            <button
              type="button"
              onclick="window.exoHighlightPackage('extension')"
              id="pkg-btn-extension"
              class="px-2.5 py-1 rounded-lg bg-violet-50 text-violet-700 border border-violet-200 hover:bg-violet-100 transition-all cursor-pointer text-xs flex items-center gap-1"
            >
              <span>🧩</span>
              <span>Extensions</span>
            </button>
            <button
              type="button"
              onclick="window.exoHighlightPackage('internal')"
              id="pkg-btn-internal"
              class="px-2.5 py-1 rounded-lg bg-cyan-50 text-cyan-700 border border-cyan-200 hover:bg-cyan-100 transition-all cursor-pointer text-xs flex items-center gap-1"
            >
              <span>💾</span>
              <span>Storage</span>
            </button>
          </div>

          <!-- Maximize Button -->
          <button
            type="button"
            onclick="document.getElementById('arch-graph-modal').classList.remove('hidden');"
            class="px-3.5 py-1.5 rounded-xl bg-violet-50 hover:bg-violet-100 text-violet-700 border border-violet-200 transition-all cursor-pointer text-xs font-bold flex items-center gap-1.5 shadow-2xs"
          >
            <span>⛶</span>
            <span>Maximize Diagram</span>
          </button>
        </div>

        <!-- Network Graph Canvas with In-Graph Dialog Container -->
        <div class="border border-slate-800 rounded-3xl bg-slate-950 overflow-x-auto relative shadow-2xl p-4 min-h-[580px]">
          <div class="min-w-[1180px]">
            {render_network_svg(assigns, "inline")}
          </div>

          <!-- In-Graph Component Inspector Dialog (Overlay inside graph) -->
          {render_node_dialog("arch-node-inspector")}
        </div>
      </div>

      <!-- VIEW 2: SEQUENTIAL CASCADE WORKFLOW (INBOUND RPC & REALTIME PUB/SUB) -->
      <div id="arch-view-workflow" class="hidden space-y-6">
        <!-- Workflow Mode Switcher -->
        <div class="flex items-center justify-between bg-white p-4 rounded-2xl border border-gray-200/80 shadow-2xs">
          <div>
            <h3 class="text-sm font-bold text-gray-900">End-to-End Execution Cascade</h3>
            <p class="text-xs text-gray-500">Step-by-step sequential timeline of data flow across boundaries.</p>
          </div>

          <div class="flex items-center gap-2 p-1 bg-gray-100 rounded-xl border border-gray-200 text-xs font-semibold">
            <button
              type="button"
              onclick="document.getElementById('cascade-action-workflow').classList.remove('hidden'); document.getElementById('cascade-event-workflow').classList.add('hidden'); document.getElementById('btn-wf-action').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-wf-event').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
              id="btn-wf-action"
              class="px-3 py-1.5 rounded-lg bg-white text-violet-700 shadow-xs transition-all cursor-pointer flex items-center gap-1.5"
            >
              <span>🎯</span>
              <span>Action RPC Request (6 Steps)</span>
            </button>
            <button
              type="button"
              onclick="document.getElementById('cascade-event-workflow').classList.remove('hidden'); document.getElementById('cascade-action-workflow').classList.add('hidden'); document.getElementById('btn-wf-event').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-wf-action').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
              id="btn-wf-event"
              class="px-3 py-1.5 rounded-lg text-gray-600 hover:text-gray-900 transition-all cursor-pointer flex items-center gap-1.5"
            >
              <span>📡</span>
              <span>Event Pub/Sub Broadcast (4 Steps)</span>
            </button>
          </div>
        </div>

        <!-- 1. ACTION RPC SEQUENTIAL CASCADE -->
        <div id="cascade-action-workflow" class="space-y-4 relative">
          <!-- Continuous Vertical Pipeline Line -->
          <div class="absolute left-6 -translate-x-1/2 top-6 bottom-6 w-0.5 bg-gradient-to-b from-blue-400 via-violet-400 to-emerald-400 z-0"></div>

          <%= for step <- @action_workflow_steps do %>
            <div class="relative z-10 pl-14">
              <!-- Step Circle Badge on Pipeline Line -->
              <div class={"absolute left-6 -translate-x-1/2 top-5 w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs font-black shadow-sm #{case step.color do
                "blue" -> "bg-blue-600 text-white border-blue-200"
                "violet" -> "bg-violet-600 text-white border-violet-200"
                "amber" -> "bg-amber-500 text-white border-amber-200"
                "emerald" -> "bg-emerald-600 text-white border-emerald-200"
                "cyan" -> "bg-cyan-600 text-white border-cyan-200"
              end}"}>
                <%= step.step %>
              </div>

              <!-- Expandable Accordion Card -->
              <details class="group bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden transition-all duration-200 hover:border-violet-300">
                <summary class="p-4 flex items-center justify-between gap-3 cursor-pointer select-none list-none">
                  <div class="flex items-center gap-3">
                    <div>
                      <div class="flex items-center gap-2">
                        <span class="font-bold text-gray-900 text-sm"><%= step.title %></span>
                        <span class={"text-[9px] font-mono font-bold px-1.5 py-0.5 rounded uppercase #{case step.color do
                          "blue" -> "bg-blue-50 text-blue-700 border border-blue-200"
                          "violet" -> "bg-violet-50 text-violet-700 border border-violet-200"
                          "amber" -> "bg-amber-50 text-amber-700 border border-amber-200"
                          "emerald" -> "bg-emerald-50 text-emerald-700 border border-emerald-200"
                          "cyan" -> "bg-cyan-50 text-cyan-700 border border-cyan-200"
                        end}"}>
                          <%= step.badge %>
                        </span>
                      </div>
                      <div class="text-xs text-gray-500 mt-0.5 font-mono">
                        <span class="font-semibold text-gray-700"><%= step.actor %>:</span>
                        <span class="text-violet-600"><%= step.action %></span>
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center gap-3">
                    <span class="text-[11px] font-mono font-bold text-gray-500 bg-gray-50 px-2.5 py-1 rounded-lg border border-gray-200">
                      ⏱️ <%= step.latency %>
                    </span>
                    <svg class="w-5 h-5 text-gray-400 group-open:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </div>
                </summary>

                <!-- Expanded Details & Syntax-Highlighted Wire JSON Framing -->
                <div class="p-5 pt-0 border-t border-gray-100 bg-gray-50/50 space-y-3">
                  <p class="text-xs text-gray-600 mt-3 leading-relaxed">
                    <%= step.details %>
                  </p>

                  <div>
                    <div class="text-[10px] font-mono font-bold text-gray-500 uppercase tracking-wider mb-1">
                      Wire Frame / Code Execution:
                    </div>
                    <pre class="bg-slate-950 text-gray-200 p-4 rounded-xl font-mono text-xs overflow-x-auto border border-slate-800 leading-relaxed"><code>{highlight_code(step.wire_sample)}</code></pre>
                  </div>
                </div>
              </details>
            </div>
          <% end %>
        </div>

        <!-- 2. EVENT PUB/SUB SEQUENTIAL CASCADE -->
        <div id="cascade-event-workflow" class="hidden space-y-4 relative">
          <!-- Continuous Vertical Pipeline Line -->
          <div class="absolute left-6 -translate-x-1/2 top-6 bottom-6 w-0.5 bg-gradient-to-b from-emerald-400 via-amber-400 to-blue-400 z-0"></div>

          <%= for step <- @event_workflow_steps do %>
            <div class="relative z-10 pl-14">
              <!-- Step Circle Badge on Pipeline Line -->
              <div class={"absolute left-6 -translate-x-1/2 top-5 w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs font-black shadow-sm #{case step.color do
                "blue" -> "bg-blue-600 text-white border-blue-200"
                "violet" -> "bg-violet-600 text-white border-violet-200"
                "amber" -> "bg-amber-500 text-white border-amber-200"
                "emerald" -> "bg-emerald-600 text-white border-emerald-200"
              end}"}>
                <%= step.step %>
              </div>

              <!-- Expandable Accordion Card -->
              <details class="group bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden transition-all duration-200 hover:border-violet-300">
                <summary class="p-4 flex items-center justify-between gap-3 cursor-pointer select-none list-none">
                  <div class="flex items-center gap-3">
                    <div>
                      <div class="flex items-center gap-2">
                        <span class="font-bold text-gray-900 text-sm"><%= step.title %></span>
                        <span class={"text-[9px] font-mono font-bold px-1.5 py-0.5 rounded uppercase #{case step.color do
                          "blue" -> "bg-blue-50 text-blue-700 border border-blue-200"
                          "violet" -> "bg-violet-50 text-violet-700 border border-violet-200"
                          "amber" -> "bg-amber-50 text-amber-700 border border-amber-200"
                          "emerald" -> "bg-emerald-50 text-emerald-700 border border-emerald-200"
                        end}"}>
                          <%= step.badge %>
                        </span>
                      </div>
                      <div class="text-xs text-gray-500 mt-0.5 font-mono">
                        <span class="font-semibold text-gray-700"><%= step.actor %>:</span>
                        <span class="text-emerald-600"><%= step.action %></span>
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center gap-3">
                    <span class="text-[11px] font-mono font-bold text-gray-500 bg-gray-50 px-2.5 py-1 rounded-lg border border-gray-200">
                      ⏱️ <%= step.latency %>
                    </span>
                    <svg class="w-5 h-5 text-gray-400 group-open:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </div>
                </summary>

                <!-- Expanded Details & Wire JSON Framing -->
                <div class="p-5 pt-0 border-t border-gray-100 bg-gray-50/50 space-y-3">
                  <p class="text-xs text-gray-600 mt-3 leading-relaxed">
                    <%= step.details %>
                  </p>

                  <div>
                    <div class="text-[10px] font-mono font-bold text-gray-500 uppercase tracking-wider mb-1">
                      Wire Event Frame:
                    </div>
                    <pre class="bg-slate-950 text-gray-200 p-4 rounded-xl font-mono text-xs overflow-x-auto border border-slate-800 leading-relaxed"><code>{highlight_code(step.wire_sample)}</code></pre>
                  </div>
                </div>
              </details>
            </div>
          <% end %>
        </div>
      </div>

      <!-- FULLSCREEN MODAL POPUP FOR ARCHITECTURE DIAGRAM -->
      <div id="arch-graph-modal" class="hidden fixed inset-0 z-50 bg-black/85 backdrop-blur-md flex flex-col p-4 sm:p-6 animate-in fade-in duration-150">
        <div class="bg-slate-950 rounded-3xl border border-slate-800 flex-1 flex flex-col overflow-hidden shadow-2xl relative">
          <!-- Modal Header -->
          <div class="flex items-center justify-between p-4 px-6 border-b border-slate-800 bg-slate-900/80">
            <div class="flex items-center gap-3">
              <span class="text-xl">🕸️</span>
              <div>
                <h3 class="text-base font-bold text-white tracking-tight">Exoforge UML Architecture Diagram</h3>
                <p class="text-xs text-slate-400">Subsystem Packages, Core Microkernel, and Ingress Topology</p>
              </div>
            </div>

            <button
              type="button"
              onclick="document.getElementById('arch-graph-modal').classList.add('hidden');"
              class="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 hover:text-white text-xs font-bold transition-colors cursor-pointer flex items-center gap-1.5"
            >
              <span>✕</span>
              <span>Close Fullscreen</span>
            </button>
          </div>

          <!-- Modal Body with Full-Size SVG -->
          <div class="flex-1 overflow-auto p-6 flex items-center justify-center relative">
            <div class="w-full max-w-[1240px]">
              {render_network_svg(assigns, "modal")}
            </div>

            <!-- In-Modal Dialog for full-screen inspection -->
            {render_node_dialog("modal-node-inspector")}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---- Helper: In-Graph Node Inspector Dialog ----

  defp render_node_dialog(dialog_id) do
    assigns = %{dialog_id: dialog_id}

    ~H"""
    <div
      id={@dialog_id}
      class="graph-node-dialog absolute inset-0 bg-slate-950/85 backdrop-blur-md flex items-center justify-center p-4 sm:p-6 hidden z-30 transition-all duration-200"
      onclick="if (event.target === this) this.classList.add('hidden')"
    >
      <div
        class="bg-slate-900 border border-slate-700/80 rounded-3xl p-6 sm:p-8 max-w-lg w-full shadow-2xl relative text-white space-y-5 animate-in fade-in zoom-in-95 duration-150"
        onclick="event.stopPropagation()"
      >
        <!-- Close button -->
        <button
          type="button"
          onclick="document.querySelectorAll('.graph-node-dialog').forEach(d => d.classList.add('hidden'))"
          class="absolute top-5 right-5 w-8 h-8 rounded-full bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white flex items-center justify-center font-bold text-sm transition-colors cursor-pointer"
          title="Close dialog"
        >
          ✕
        </button>

        <!-- Header: Icon, Title, Badge -->
        <div class="flex items-start gap-4">
          <div
            id={"#{@dialog_id}-icon"}
            class="dialog-icon w-14 h-14 rounded-2xl bg-slate-800/90 border border-slate-700 flex items-center justify-center text-3xl shrink-0 shadow-inner"
          >
            🎯
          </div>
          <div class="space-y-1 pr-6">
            <div class="flex flex-wrap items-center gap-2">
              <h3 id={"#{@dialog_id}-title"} class="dialog-title text-xl font-black text-white tracking-tight">
                ActionDispatcher
              </h3>
              <span
                id={"#{@dialog_id}-badge"}
                class="dialog-badge text-[10px] font-mono font-bold px-2.5 py-0.5 rounded-full bg-amber-400/20 text-amber-300 border border-amber-400/30"
              >
                KERNEL [IMMUTABLE]
              </span>
            </div>
            <div id={"#{@dialog_id}-subtitle"} class="dialog-subtitle text-xs font-mono font-semibold text-violet-400">
              Scope &amp; Route Engine
            </div>
          </div>
        </div>

        <!-- Description -->
        <div class="bg-slate-950/60 p-4 rounded-2xl border border-slate-800/80">
          <div class="text-[10px] font-mono font-bold text-slate-400 uppercase tracking-wider mb-1.5">
            Subsystem Role &amp; Responsibility
          </div>
          <p id={"#{@dialog_id}-desc"} class="dialog-desc text-xs text-slate-200 leading-relaxed">
            Zero-latency in-memory security scope verification (:guest, :player, :admin) &amp; provider routing.
          </p>
        </div>

        <!-- Details Grid: Package & Interconnects -->
        <div class="grid grid-cols-2 gap-3">
          <div class="bg-slate-800/50 p-3 rounded-xl border border-slate-700/60">
            <div class="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Subsystem Layer</div>
            <div id={"#{@dialog_id}-package"} class="dialog-package text-xs font-bold text-slate-100 mt-0.5 font-mono">
              Kernel Core
            </div>
          </div>
          <div class="bg-slate-800/50 p-3 rounded-xl border border-slate-700/60">
            <div class="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Interconnect Protocol</div>
            <div id={"#{@dialog_id}-protocol"} class="dialog-protocol text-xs font-bold text-violet-300 mt-0.5 font-mono">
              In-Memory Zero-Copy
            </div>
          </div>
        </div>

        <!-- Dismiss footer -->
        <div class="flex items-center justify-between pt-2 border-t border-slate-800 text-[11px] text-slate-400">
          <span class="flex items-center gap-1.5">
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
            Click anywhere outside or press ESC to dismiss
          </span>
          <button
            type="button"
            onclick="document.querySelectorAll('.graph-node-dialog').forEach(d => d.classList.add('hidden'))"
            class="text-violet-400 hover:text-violet-300 font-semibold cursor-pointer"
          >
            Dismiss
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ---- Helper: Render Network SVG ----

  defp render_network_svg(assigns, variant) do
    prefix = if variant == "modal", do: "m_", else: "i_"
    assigns = assign(assigns, :prefix, prefix)

    ~H"""
    <svg
      viewBox="0 0 1208 590"
      class="w-full h-auto select-none font-sans"
    >
      <defs>
        <!-- Arrowhead Marker -->
        <marker id={"#{@prefix}net-arrow"} viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#64748b" />
        </marker>
        <marker id={"#{@prefix}net-arrow-amber"} viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#f59e0b" />
        </marker>
        <marker id={"#{@prefix}net-arrow-violet"} viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#8b5cf6" />
        </marker>

        <!-- Drop Shadow Filters -->
        <filter id={"#{@prefix}net-shadow"} x="-10%" y="-10%" width="120%" height="120%">
          <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000000" flood-opacity="0.45" />
        </filter>
        <filter id={"#{@prefix}kernel-glow"} x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="0" dy="0" stdDeviation="8" flood-color="#f59e0b" flood-opacity="0.25" />
        </filter>

        <!-- Gradients -->
        <linearGradient id={"#{@prefix}kernel-bg"} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#2a1f0a" />
          <stop offset="100%" stop-color="#191305" />
        </linearGradient>
        <linearGradient id={"#{@prefix}extension-bg"} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#1e183a" />
          <stop offset="100%" stop-color="#0f0c24" />
        </linearGradient>
        <linearGradient id={"#{@prefix}storage-bg"} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#082a3d" />
          <stop offset="100%" stop-color="#031622" />
        </linearGradient>
      </defs>

      <!-- Subsystem UML Packages (Envelopes) -->
      <g class="uml-packages">
        <!-- Package 1: Client Ingress & Gateways -->
        <g class="uml-package-box" data-category="client">
          <rect x="20" y="24" width="418" height="544" rx="20" fill="#0f172a" fill-opacity="0.6" stroke="#334155" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 20 48 L 140 48 L 152 36 L 152 24 L 20 24 Z" fill="#1e293b" />
          <text x="32" y="40" fill="#94a3b8" font-size="9.5" font-weight="bold" font-family="monospace">package Ingress</text>
        </g>

        <!-- Package 2: Kernel Core (Prominent Microkernel Boundary) -->
        <g class="uml-package-box" data-category="kernel">
          <rect x="456" y="24" width="278" height="544" rx="20" fill="#181308" fill-opacity="0.8" stroke="#f59e0b" stroke-width="2" filter={"url(##{@prefix}kernel-glow)"} />
          <path d="M 456 48 L 610 48 L 622 36 L 622 24 L 456 24 Z" fill="#451a03" />
          <text x="468" y="40" fill="#fde047" font-size="9.5" font-weight="black" font-family="monospace">⚡ package Kernel</text>
        </g>

        <!-- Package 3: Extension Workers -->
        <g class="uml-package-box" data-category="extension">
          <rect x="750" y="24" width="234" height="544" rx="20" fill="#0f172a" fill-opacity="0.6" stroke="#059669" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 750 48 L 890 48 L 902 36 L 902 24 L 750 24 Z" fill="#064e3b" />
          <text x="762" y="40" fill="#6ee7b7" font-size="9.5" font-weight="bold" font-family="monospace">package Extensions</text>
        </g>

        <!-- Package 4: Data & Storage -->
        <g class="uml-package-box" data-category="internal">
          <rect x="996" y="24" width="192" height="544" rx="20" fill="#0f172a" fill-opacity="0.6" stroke="#0284c7" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 996 48 L 1120 48 L 1132 36 L 1132 24 L 996 24 Z" fill="#082f49" />
          <text x="1008" y="40" fill="#7dd3fc" font-size="9.5" font-weight="bold" font-family="monospace">package Storage</text>
        </g>
      </g>

      <!-- Connecting Directed Edges with Dynamic Animated Flow -->
      <g class="uml-edges">
        <%= for edge <- @edges do %>
          <!-- Static Base Line -->
          <path
            d={edge.path}
            fill="none"
            stroke="#475569"
            stroke-width="1.8"
            marker-end={"url(##{@prefix}net-arrow)"}
            class="opacity-50"
          />
          <!-- Animated Flow Overlay -->
          <path
            d={edge.path}
            fill="none"
            stroke="#8b5cf6"
            stroke-width="1.8"
            class="animate-flow-dash opacity-80"
          />
        <% end %>
      </g>

      <!-- Subsystem Network Nodes (Cards with Large, Legible Typography) -->
      <g class="uml-components">
        <%= for comp <- @components do %>
          <g
            class="network-node uml-comp-node cursor-pointer group"
            data-graph-node="true"
            data-category={comp.category}
            data-node-id={comp.id}
            data-node-title={comp.title}
            data-node-subtitle={comp.subtitle}
            data-node-badge={comp.badge}
            data-node-desc={comp.desc}
            data-node-package={comp.package}
            data-node-icon={comp.icon}
            data-node-protocol={comp.protocol}
            onclick="window.exoOpenNodeDialog && window.exoOpenNodeDialog(this)"
            transform={"translate(#{comp.x}, #{comp.y})"}
          >
            <!-- Card Outer Rectangle -->
            <rect
              width={comp.width}
              height={comp.height}
              rx="16"
              fill={case comp.category do
                "kernel" -> "url(##{@prefix}kernel-bg)"
                "extension" -> "url(##{@prefix}extension-bg)"
                "internal" -> "url(##{@prefix}storage-bg)"
                _ -> "#1e293b"
              end}
              stroke={case comp.category do
                "kernel" -> "#f59e0b"
                "extension" -> "#8b5cf6"
                "internal" -> "#06b6d4"
                _ -> "#475569"
              end}
              stroke-width={if comp.category == "kernel", do: "2", else: "1.4"}
              filter={"url(##{@prefix}net-shadow)"}
              class="group-hover:stroke-white transition-all"
            />

            <!-- Top Meta Line: Stereotype & Category Badge -->
            <text x="12" y="19" fill="#94a3b8" font-size="8.5" font-family="monospace">&laquo;component&raquo;</text>
            <text
              x={comp.width - 12}
              y="19"
              text-anchor="end"
              fill={case comp.category do
                "kernel" -> "#fde047"
                "extension" -> "#c4b5fd"
                "internal" -> "#67e8f9"
                _ -> "#cbd5e1"
              end}
              font-size="8.5"
              font-weight="bold"
              font-family="monospace"
            >
              <%= comp.badge %>
            </text>

            <!-- Icon -->
            <text x="12" y="48" font-size="22"><%= comp.icon %></text>

            <!-- Title (Large 13.5px Bold White) -->
            <text
              x="42"
              y="44"
              fill="#ffffff"
              font-size="13.5"
              font-weight="bold"
              font-family="system-ui, -apple-system, sans-serif"
            >
              <%= comp.title %>
            </text>

            <!-- Subtitle (10.5px Monospace) -->
            <text
              x="42"
              y="61"
              fill={case comp.category do
                "kernel" -> "#fcd34d"
                "extension" -> "#a78bfa"
                "internal" -> "#38bdf8"
                _ -> "#94a3b8"
              end}
              font-size="10.5"
              font-weight="600"
              font-family="monospace"
            >
              <%= comp.subtitle %>
            </text>

            <!-- Live Active Indicator Dot -->
            <%= if comp.category in ["kernel", "extension"] do %>
              <circle
                cx={comp.width - 14}
                cy="44"
                r="3.5"
                fill={if comp.category == "kernel", do: "#f59e0b", else: "#10b981"}
                class="animate-pulse"
              />
            <% end %>
          </g>
        <% end %>
      </g>
    </svg>
    """
  end

  # ---- Syntax Highlighter for Workflow JSON & Code ----

  defp highlight_code(code) do
    code
    |> String.trim()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.split("\n")
    |> Enum.map(&highlight_line/1)
    |> Enum.join("\n")
    |> Phoenix.HTML.raw()
  end

  defp highlight_line(line) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "//") or String.starts_with?(trimmed, "--") or
          String.starts_with?(trimmed, "/*") ->
        "<span class=\"text-slate-500 italic\">#{line}</span>"

      String.starts_with?(trimmed, "[") and String.ends_with?(trimmed, "]") ->
        "<span class=\"text-violet-400 font-semibold\">#{line}</span>"

      true ->
        line
        # JSON keys: &quot;key&quot;:
        |> String.replace(
          ~r/&quot;([a-zA-Z0-9_]+)&quot;(?=\s*:)/,
          "<span class=\"text-sky-300 font-semibold\">&quot;\\1&quot;</span>"
        )
        # JSON string values: : &quot;value&quot;
        |> String.replace(
          ~r/(:\s*)&quot;([^&]*)&quot;/,
          "\\1<span class=\"text-emerald-300\">&quot;\\2&quot;</span>"
        )
        # JSON numbers: : 1234
        |> String.replace(
          ~r/(:\s*)([0-9]+(?:\.[0-9]+)?)/,
          "\\1<span class=\"text-amber-300 font-bold\">\\2</span>"
        )
        # JSON booleans & null
        |> String.replace(
          ~r/(:\s*)(true|false|null)/,
          "\\1<span class=\"text-purple-300 font-bold\">\\2</span>"
        )
        # SQL keywords
        |> String.replace(
          ~r/\b(INSERT INTO|VALUES|ON CONFLICT|DO UPDATE SET|SELECT|FROM|WHERE)\b/,
          "<span class=\"text-violet-400 font-bold\">\\1</span>"
        )
    end
  end
end
