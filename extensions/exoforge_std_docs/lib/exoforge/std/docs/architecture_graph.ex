defmodule Exoforge.Std.Docs.ArchitectureGraph do
  @moduledoc """
  Interactive Network Architecture Diagram, Progressive Disclosure Subsystem Envelopes,
  Docked Component Inspector Drawer, Fullscreen Maximizer, and Sequential Workflow Pipeline
  Visualizer for Exoforge.
  """
  use Phoenix.Component

  # ---- Subsystems & Components Specification ----

  @components [
    # Layer 1 (Top): Ingress Layer (Client & Tooling)
    %{
      id: "unity_client",
      title: "Unity Client SDK",
      subtitle: "com.exoforge.sdk",
      desc: "Client runtime with async/await stubs, device anonymous auth, and reactive event hooks.",
      icon: "🕹️",
      package: "Client Ingress",
      group: "client",
      category: "client",
      badge: "GAME CLIENT",
      protocol: "WebSocket / HTTP RPC",
      upstream: "",
      downstream: "ws_gateway,transport_layer",
      x: 50,
      y: 55,
      width: 300,
      height: 76
    },
    %{
      id: "exo_cli",
      title: "Exo CLI & Engine",
      subtitle: "Management Engine",
      desc: "Local dev engine, Roslyn generator, C# extension compiler, and remote cluster push.",
      icon: "💻",
      package: "Developer Tooling",
      group: "client",
      category: "tooling",
      badge: "DEV TOOLING",
      protocol: "HTTP Administration",
      upstream: "",
      downstream: "transport_layer,http_gateway",
      x: 390,
      y: 55,
      width: 300,
      height: 76
    },
    %{
      id: "producer_studio",
      title: "Producer Studio",
      subtitle: "LiveView Dashboard :4005",
      desc: "Web-based actor inspector, live cluster metrics, extension lifecycle manager, and dev guide.",
      icon: "🎛️",
      package: "Studio Operations",
      group: "client",
      category: "studio",
      badge: "STUDIO UI",
      protocol: "Phoenix LiveView",
      upstream: "",
      downstream: "http_gateway",
      x: 730,
      y: 55,
      width: 300,
      height: 76
    },

    # Layer 2: Gateways Layer
    %{
      id: "ws_gateway",
      title: "WebSocket Gateway",
      subtitle: ":ws on port 4000",
      desc: "Real-time framed JSON WebSocket ingress and low-latency bidirectional pub/sub event bus.",
      icon: "⚡",
      package: "Gateway Layer",
      group: "gateways",
      category: "extension",
      badge: "GATEWAY",
      protocol: "Framed JSON Socket",
      upstream: "unity_client",
      downstream: "action_dispatcher,event_dispatcher",
      x: 50,
      y: 220,
      width: 300,
      height: 76
    },
    %{
      id: "transport_layer",
      title: "Transport Normalizer",
      subtitle: ":transport service",
      desc: "Strips unverified client spoofed fields, stamps verified player credentials, and normalizes RPCs.",
      icon: "🔄",
      package: "Gateway Layer",
      group: "gateways",
      category: "extension",
      badge: "GATEWAY",
      protocol: "Sanitized RPC Envelope",
      upstream: "unity_client,exo_cli",
      downstream: "action_dispatcher",
      x: 390,
      y: 220,
      width: 300,
      height: 76
    },
    %{
      id: "http_gateway",
      title: "HTTP REST Gateway",
      subtitle: ":http on port 4001",
      desc: "Dynamic OpenAPI REST endpoints derived automatically from service action contracts.",
      icon: "🌐",
      package: "Gateway Layer",
      group: "gateways",
      category: "extension",
      badge: "GATEWAY",
      protocol: "HTTP / OpenAPI JSON",
      upstream: "producer_studio,exo_cli",
      downstream: "action_dispatcher",
      x: 730,
      y: 220,
      width: 300,
      height: 76
    },

    # Layer 3: Kernel Core (Microkernel Boundary)
    %{
      id: "extension_registry",
      title: "ExtensionRegistry",
      subtitle: "In-Memory ETS Catalog",
      desc: "Lockless in-memory catalog of registered extensions, action contracts, resources, and route metadata.",
      icon: "📚",
      package: "Kernel Core",
      group: "kernel",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      protocol: "Direct In-Memory Read",
      upstream: "action_dispatcher",
      downstream: "",
      x: 45,
      y: 395,
      width: 230,
      height: 78
    },
    %{
      id: "action_dispatcher",
      title: "ActionDispatcher",
      subtitle: "Scope & Route Engine",
      desc: "Zero-latency in-memory security scope verification (:guest, :player, :admin) & provider routing.",
      icon: "🎯",
      package: "Kernel Core",
      group: "kernel",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      protocol: "Zero-Copy In-Memory",
      upstream: "ws_gateway,transport_layer,http_gateway",
      downstream: "extension_registry,native_csharp,elixir_runner,std_services",
      x: 295,
      y: 395,
      width: 230,
      height: 78
    },
    %{
      id: "event_dispatcher",
      title: "EventDispatcher",
      subtitle: "Cluster Pub/Sub Bus",
      desc: "Pattern-matched topic fanout over distributed process groups (0.07 ms SLA to 50 concurrent subscribers).",
      icon: "📡",
      package: "Kernel Core",
      group: "kernel",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      protocol: "Distributed Pub/Sub (:pg)",
      upstream: "ws_gateway,native_csharp",
      downstream: "ws_gateway,extension_supervisor,native_csharp",
      x: 545,
      y: 395,
      width: 230,
      height: 78
    },
    %{
      id: "extension_supervisor",
      title: "ExtensionSupervisor",
      subtitle: "Topological DAG Tree",
      desc: "Starts extensions in topological dependency order, isolates worker failures, and restarts crashed actors.",
      icon: "🛡️",
      package: "Kernel Core",
      group: "kernel",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      protocol: "Cluster Supervision Tree",
      upstream: "event_dispatcher",
      downstream: "native_csharp,elixir_runner",
      x: 795,
      y: 395,
      width: 230,
      height: 78
    },

    # Layer 4: Extension Workers
    %{
      id: "native_csharp",
      title: "Native C# Game Worker",
      subtitle: ".NET Single-File Process",
      desc: "Framework-dependent single-file binary with AOT trimming, zero reflection, and static dispatch delegates.",
      icon: "⚙️",
      package: "Extension Workers",
      group: "extension",
      category: "extension",
      badge: "GAME EXTENSION",
      protocol: "Newline-Delimited JSON stdio",
      upstream: "action_dispatcher,event_dispatcher",
      downstream: "database_manager,event_dispatcher",
      x: 50,
      y: 565,
      width: 300,
      height: 76
    },
    %{
      id: "elixir_runner",
      title: "Elixir Extensions",
      subtitle: "Actor Concurrency",
      desc: "System extensions running directly inside the BEAM cluster supervision tree.",
      icon: "🧪",
      package: "Extension Workers",
      group: "extension",
      category: "extension",
      badge: "SYSTEM EXTENSION",
      protocol: "Direct Message Passing",
      upstream: "action_dispatcher,extension_supervisor",
      downstream: "resource_store",
      x: 390,
      y: 565,
      width: 300,
      height: 76
    },
    %{
      id: "std_services",
      title: "Standard Services",
      subtitle: "auth, player_data, cron",
      desc: "Modular platform services providing token issuance, profile persistence, and cron scheduling.",
      icon: "📦",
      package: "Extension Workers",
      group: "extension",
      category: "extension",
      badge: "PLATFORM SERVICE",
      protocol: "Service Action Contracts",
      upstream: "action_dispatcher",
      downstream: "storage_adapters",
      x: 730,
      y: 565,
      width: 300,
      height: 76
    },

    # Layer 5 (Bottom): Data & Storage Layer
    %{
      id: "database_manager",
      title: "Database Manager",
      subtitle: ":database service",
      desc: "Multi-engine database service managing connection pools and per-extension schema isolation.",
      icon: "🗄️",
      package: "Data & Storage",
      group: "storage",
      category: "extension",
      badge: "STORAGE EXTENSION",
      protocol: "Connection Pool RPC",
      upstream: "native_csharp",
      downstream: "storage_adapters",
      x: 50,
      y: 730,
      width: 300,
      height: 76
    },
    %{
      id: "resource_store",
      title: "Resource Store",
      subtitle: ":resource_store",
      desc: "Schema-driven entity storage with declarative typed CRUD, migrations, and drawer definitions.",
      icon: "📊",
      package: "Data & Storage",
      group: "storage",
      category: "extension",
      badge: "STORAGE EXTENSION",
      protocol: "Typed Resource Schema",
      upstream: "elixir_runner",
      downstream: "database_manager,storage_adapters",
      x: 390,
      y: 730,
      width: 300,
      height: 76
    },
    %{
      id: "storage_adapters",
      title: "Isolated DB Schemas",
      subtitle: "SQLite / PostgreSQL Engine",
      desc: "Strictly isolated schema namespace (e.g. ext_snake_game) preventing cross-extension data leakage.",
      icon: "💾",
      package: "Data & Storage",
      group: "storage",
      category: "internal",
      badge: "INTERNAL ENGINE",
      protocol: "Isolated Schema SQL",
      upstream: "database_manager,resource_store,std_services",
      downstream: "",
      x: 730,
      y: 730,
      width: 300,
      height: 76
    }
  ]

  @edges [
    %{from: "unity_client", to: "ws_gateway", path: "M 200 131 L 200 220", label: "WebSocket"},
    %{from: "unity_client", to: "transport_layer", path: "M 230 131 C 230 175, 500 175, 500 220", label: "RPC Ingress"},
    %{from: "exo_cli", to: "transport_layer", path: "M 540 131 L 540 220", label: "Build Push"},
    %{from: "producer_studio", to: "http_gateway", path: "M 880 131 L 880 220", label: "REST / LiveView"},
    %{from: "ws_gateway", to: "action_dispatcher", path: "M 200 296 C 200 350, 360 350, 360 395", label: "dispatch"},
    %{from: "ws_gateway", to: "event_dispatcher", path: "M 240 296 C 240 350, 600 350, 600 395", label: "pub/sub"},
    %{from: "transport_layer", to: "action_dispatcher", path: "M 520 296 C 520 350, 410 350, 410 395", label: "verified"},
    %{from: "http_gateway", to: "action_dispatcher", path: "M 860 296 C 860 350, 460 350, 460 395", label: "route"},
    %{from: "action_dispatcher", to: "extension_registry", path: "M 295 434 L 275 434", label: "catalog lookup"},
    %{from: "action_dispatcher", to: "native_csharp", path: "M 360 473 C 360 520, 200 520, 200 565", label: "stdio IPC"},
    %{from: "action_dispatcher", to: "elixir_runner", path: "M 410 473 C 410 520, 540 520, 540 565", label: "actor message"},
    %{from: "action_dispatcher", to: "std_services", path: "M 460 473 C 460 520, 860 520, 860 565", label: "dispatch"},
    %{from: "event_dispatcher", to: "extension_supervisor", path: "M 775 434 L 795 434", label: "health status"},
    %{from: "event_dispatcher", to: "native_csharp", path: "M 620 473 C 620 525, 250 525, 250 565", label: "event frame"},
    %{from: "native_csharp", to: "event_dispatcher", path: "M 220 565 C 220 515, 580 515, 580 473", label: "publish"},
    %{from: "native_csharp", to: "database_manager", path: "M 200 641 L 200 730", label: "host_call"},
    %{from: "elixir_runner", to: "resource_store", path: "M 540 641 L 540 730", label: "schema CRUD"},
    %{from: "std_services", to: "storage_adapters", path: "M 880 641 L 880 730", label: "storage"},
    %{from: "database_manager", to: "storage_adapters", path: "M 350 768 C 480 768, 600 755, 730 755", label: "SQL isolation"},
    %{from: "resource_store", to: "storage_adapters", path: "M 690 768 L 730 768", label: "resource persistence"}
  ]

  # ---- Workflow Steps Definition ----

  @action_workflow_steps [
    %{
      step: 1,
      id: "wf_client",
      actor_node: "unity_client",
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
      actor_node: "transport_layer",
      title: "Gateway Sanitization & Token Verification",
      actor: "Transport Gateway (:ws / :transport)",
      action: "Transport.sanitize_and_stamp_credentials(packet)",
      summary: "Gateway strips unverified client spoofed fields and stamps verified player identity from the session token.",
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
      details: "Clients can never forge player_id or scopes. The gateway validates the cryptographic session token issued by the auth extension and stamps the verified context."
    },
    %{
      step: 3,
      id: "wf_dispatcher",
      actor_node: "action_dispatcher",
      title: "Scope Authorization & Provider Resolution",
      actor: "ActionDispatcher (Kernel)",
      action: "ActionDispatcher.dispatch(:snake_game, :submit_score, payload)",
      summary: "Kernel verifies caller scope against contract requirements and routes to registered worker in memory.",
      wire_sample: """
      {
        "dispatch": "ScopeAuthorizationCheck",
        "required_scope": "player",
        "caller_scopes": ["player"],
        "status": "authorized",
        "target_worker": "NativeWorker[snake_game]"
      }
      """,
      latency: "< 0.02 ms (Lockless)",
      badge: "Kernel",
      color: "amber",
      details: "Pure lockless in-memory resolution. If the caller has required scope (:guest, :player, :server, :studio), the request routes immediately to the registered worker."
    },
    %{
      step: 4,
      id: "wf_runner",
      actor_node: "native_csharp",
      title: "Native C# Extension Execution",
      actor: "Native .NET Worker (OS Process)",
      action: "SnakeExtension.SubmitScore(ScoreRecord record)",
      summary: "Host delivers newline-delimited JSON frame over stdio to the isolated .NET process without reflection.",
      wire_sample: """
      [ExoAction(Scope = "player")]
      public SnakeScoreSubmitted SubmitScore(int score) {
          Exo.Database.Put("snake_scores", PlayerId, new SnakeScore(score));
          return new SnakeScoreSubmitted(score, Rank: 1);
      }
      """,
      latency: "0.2 - 0.8 ms",
      badge: "Execution",
      color: "emerald",
      details: "The framework-dependent single-file .NET worker deserializes arguments into typed records. Roslyn-generated dispatch maps method directly without reflection overhead."
    },
    %{
      step: 5,
      id: "wf_storage",
      actor_node: "database_manager",
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
      details: "Each extension has its own isolated schema namespace (e.g. ext_snake_game). No extension can access or modify another extension's data without authorized contracts."
    },
    %{
      step: 6,
      id: "wf_response",
      actor_node: "ws_gateway",
      title: "Framed Response Returned to Client",
      actor: "Transport Gateway ➔ Unity Client",
      action: "Transport.format_action_result(result)",
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
      details: "The gateway writes the JSON frame back down the client socket. In Unity, the matching Task completion source is resolved and returns the strongly-typed C# record."
    }
  ]

  @event_workflow_steps [
    %{
      step: 1,
      id: "ev_publish",
      actor_node: "native_csharp",
      title: "Extension Publishes Event",
      actor: "Game Extension",
      action: "await Exo.Events.EmitAsync(new SnakeScoreSubmitted(...))",
      summary: "Extension emits an event without needing to know who or how many consumers are listening.",
      wire_sample: """
      {
        "type": "host_call",
        "op": "emit_event",
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
      actor_node: "event_dispatcher",
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
        "delivery": "direct_process_fanout"
      }
      """,
      latency: "0.07 ms verified SLA",
      badge: "Kernel",
      color: "amber",
      details: "Cluster distributed pub/sub delivers messages directly to subscriber worker processes with zero central serialization bottleneck (0.07 ms verified SLA to 50 concurrent subscribers)."
    },
    %{
      step: 3,
      id: "ev_gateway",
      actor_node: "ws_gateway",
      title: "Gateway Realtime Frame Push",
      actor: "WebSocket Gateway (:ws)",
      action: "WebSocket.push_framed_json(connection, event_frame)",
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
      actor_node: "unity_client",
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

  # ---- Visualizer Component ----

  def visualizer(assigns) do
    assigns =
      assigns
      |> assign_new(:components, fn -> @components end)
      |> assign_new(:edges, fn -> @edges end)
      |> assign_new(:action_workflow_steps, fn -> @action_workflow_steps end)
      |> assign_new(:event_workflow_steps, fn -> @event_workflow_steps end)

    ~H"""
    <div class="space-y-6 select-none font-sans" id="exoforge-architecture-visualizer">
      <!-- Section Header -->
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-gray-200">
        <div>
          <div class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-violet-50 text-violet-700 border border-violet-200 text-[10px] font-bold">
            <span class="w-1.5 h-1.5 rounded-full bg-violet-600 animate-pulse"></span>
            <span>Progressive Disclosure Architecture &amp; Execution Pipeline</span>
          </div>
          <h2 class="text-xl font-bold text-gray-900 tracking-tight mt-1">
            System Topology, Packages &amp; Execution Flow
          </h2>
          <p class="text-xs text-gray-500">
            Interactive network architecture, 1-hop dependency spotlighting, pan/zoom canvas, and sequential cascades.
          </p>
        </div>

        <!-- Mode Toggle: Architecture vs Workflow Cascade -->
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
      <div id="arch-view-graph" class="space-y-4">
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

            <!-- Rule of Thumb Card -->
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

        <!-- Diagram Toolbar: Filters, Zoom, Progressive Disclosure & Fullscreen -->
        <div class="flex flex-wrap items-center justify-between gap-3 bg-white p-3 rounded-2xl border border-gray-200/80 shadow-2xs">
          <!-- Layer Filter Pills -->
          <div class="flex flex-wrap items-center gap-1.5 text-xs font-semibold">
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

          <!-- Canvas Controls: Zoom, Reset, Expand All & Maximize -->
          <div class="flex items-center gap-2">
            <!-- Zoom Controls -->
            <div class="flex items-center bg-gray-100 rounded-xl border border-gray-200/80 p-0.5 text-xs font-mono font-bold text-gray-700">
              <button
                type="button"
                onclick="window.ExoGraphEngine.zoom('arch-graph', 0.85)"
                class="w-7 h-7 flex items-center justify-center rounded-lg hover:bg-white transition-colors cursor-pointer"
                title="Zoom Out"
              >
                −
              </button>
              <span id="arch-graph-zoom-level" class="px-2 text-[11px] select-none">100%</span>
              <button
                type="button"
                onclick="window.ExoGraphEngine.zoom('arch-graph', 1.15)"
                class="w-7 h-7 flex items-center justify-center rounded-lg hover:bg-white transition-colors cursor-pointer"
                title="Zoom In"
              >
                +
              </button>
              <button
                type="button"
                onclick="window.ExoGraphEngine.reset('arch-graph')"
                class="px-2 h-7 flex items-center justify-center rounded-lg hover:bg-white text-[10px] font-sans transition-colors cursor-pointer border-l border-gray-200"
                title="Reset View"
              >
                Reset
              </button>
            </div>

            <!-- Progressive Disclosure Toggles -->
            <div class="hidden md:flex items-center gap-1">
              <button
                type="button"
                onclick="window.ExoGraphEngine.expandAll('arch-graph')"
                class="px-2.5 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-semibold transition-all cursor-pointer"
              >
                Expand All
              </button>
              <button
                type="button"
                onclick="window.ExoGraphEngine.collapseAll('arch-graph')"
                class="px-2.5 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-semibold transition-all cursor-pointer"
              >
                Collapse All
              </button>
            </div>

            <!-- Maximize Fullscreen Button -->
            <button
              type="button"
              onclick="document.getElementById('arch-graph-modal').classList.remove('hidden'); setTimeout(function() { window.ExoGraphEngine.fit('modal-arch-graph'); }, 50);"
              class="px-3 py-1.5 rounded-xl bg-violet-50 hover:bg-violet-100 text-violet-700 border border-violet-200 transition-all cursor-pointer text-xs font-bold flex items-center gap-1.5 shadow-2xs"
            >
              <span>⛶</span>
              <span>Maximize Diagram</span>
            </button>
          </div>
        </div>

        <!-- Network Graph Canvas with Pan/Zoom & Docked Inspector Drawer -->
        <div
          id="arch-graph-container"
          phx-hook="ArchGraph"
          onmouseenter="window.ExoGraphEngine && window.ExoGraphEngine.initPanZoom('arch-graph')"
          class="border border-slate-800 rounded-3xl bg-slate-950 overflow-hidden relative shadow-2xl h-[680px] select-none cursor-grab"
        >
          <!-- Canvas Background Click Area (clears spotlight) -->
          <div class="graph-canvas-bg absolute inset-0 z-0"></div>

          <!-- Viewport Element Transformed by Pan/Zoom -->
          <div
            id="arch-graph-viewport"
            class="absolute top-0 left-0 w-[1080px] h-[850px] transition-transform duration-75 z-10"
          >
            {render_network_svg(assigns, "inline")}
          </div>

          <!-- Hint Pill -->
          <div class="absolute bottom-3 left-4 z-20 pointer-events-none text-[11px] font-mono text-slate-400 bg-slate-900/80 px-3 py-1 rounded-full border border-slate-800 backdrop-blur-sm flex items-center gap-2">
            <span class="w-2 h-2 rounded-full bg-violet-400 animate-pulse"></span>
            <span>Click any node to spotlight 1-hop dependencies • Drag to pan • Scroll to zoom</span>
          </div>

          <!-- Docked In-Graph Inspector Drawer -->
          {render_docked_drawer("arch-node-inspector")}
        </div>
      </div>

      <!-- VIEW 2: SEQUENTIAL CASCADE WORKFLOW (INBOUND RPC & REALTIME PUB/SUB) -->
      <div id="arch-view-workflow" class="hidden space-y-6">
        <!-- Interactive Workflow Stepper Bar -->
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-white p-4 rounded-2xl border border-gray-200/80 shadow-2xs">
          <div>
            <h3 class="text-sm font-bold text-gray-900">Execution Pipeline Stepper</h3>
            <p class="text-xs text-gray-500">Interactive step-by-step trace of packets across boundaries.</p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <!-- Workflow Mode Select -->
            <div class="flex items-center gap-1.5 p-1 bg-gray-100 rounded-xl border border-gray-200 text-xs font-semibold">
              <button
                type="button"
                onclick="document.getElementById('cascade-action-workflow').classList.remove('hidden'); document.getElementById('cascade-event-workflow').classList.add('hidden'); document.getElementById('btn-wf-action').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-wf-event').classList.remove('bg-white', 'text-violet-700', 'shadow-xs'); window._wfType = 'action'; window.ExoGraphEngine.stepWorkflow(1, 'action');"
                id="btn-wf-action"
                class="px-3 py-1.5 rounded-lg bg-white text-violet-700 shadow-xs transition-all cursor-pointer flex items-center gap-1.5"
              >
                <span>🎯</span>
                <span>Action RPC (6 Steps)</span>
              </button>
              <button
                type="button"
                onclick="document.getElementById('cascade-event-workflow').classList.remove('hidden'); document.getElementById('cascade-action-workflow').classList.add('hidden'); document.getElementById('btn-wf-event').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-wf-action').classList.remove('bg-white', 'text-violet-700', 'shadow-xs'); window._wfType = 'event'; window.ExoGraphEngine.stepWorkflow(1, 'event');"
                id="btn-wf-event"
                class="px-3 py-1.5 rounded-lg text-gray-600 hover:text-gray-900 transition-all cursor-pointer flex items-center gap-1.5"
              >
                <span>📡</span>
                <span>Event Pub/Sub (4 Steps)</span>
              </button>
            </div>

            <!-- Stepper Navigation -->
            <div class="flex items-center gap-1 bg-gray-100 p-1 rounded-xl border border-gray-200">
              <button
                type="button"
                onclick="window._activeStep = Math.max(1, (window._activeStep || 1) - 1); window.ExoGraphEngine.stepWorkflow(window._activeStep, window._wfType || 'action');"
                class="px-2.5 py-1 rounded-lg bg-white hover:bg-gray-50 text-gray-700 text-xs font-semibold border border-gray-200/60 shadow-2xs cursor-pointer"
              >
                ◀ Prev
              </button>
              <span id="trace-step-counter" class="px-2.5 text-xs font-mono font-bold text-violet-700">Step 1</span>
              <button
                type="button"
                onclick="window._activeStep = Math.min(6, (window._activeStep || 1) + 1); window.ExoGraphEngine.stepWorkflow(window._activeStep, window._wfType || 'action');"
                class="px-2.5 py-1 rounded-lg bg-violet-600 hover:bg-violet-700 text-white text-xs font-bold shadow-2xs cursor-pointer"
              >
                Next ▶
              </button>
            </div>
          </div>
        </div>

        <!-- 1. ACTION RPC SEQUENTIAL CASCADE -->
        <div id="cascade-action-workflow" class="space-y-4 relative">
          <!-- Pixel-Perfect Centered Vertical Pipeline Line (Center at 16px) -->
          <div class="absolute left-4 -translate-x-1/2 top-4 bottom-4 w-0.5 bg-gradient-to-b from-blue-400 via-violet-400 to-emerald-400 z-0"></div>

          <%= for step <- @action_workflow_steps do %>
            <div class="flex items-start gap-4 relative z-10" data-workflow-type="action" data-step-num={step.step} data-actor-node={step.actor_node}>
              <!-- Concentric Step Circle Badge on Vertical Pipeline -->
              <div class={"w-8 h-8 rounded-full border-2 flex items-center justify-center text-xs font-black shadow-sm shrink-0 z-10 #{case step.color do
                "blue" -> "bg-blue-600 text-white border-blue-200"
                "violet" -> "bg-violet-600 text-white border-violet-200"
                "amber" -> "bg-amber-500 text-white border-amber-200"
                "emerald" -> "bg-emerald-600 text-white border-emerald-200"
                "cyan" -> "bg-cyan-600 text-white border-cyan-200"
              end}"}>
                <%= step.step %>
              </div>

              <!-- Expandable Accordion Card -->
              <details class="group flex-1 bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden transition-all duration-200 hover:border-violet-300">
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

                  <div class="relative group/code">
                    <div class="flex items-center justify-between text-[10px] font-mono font-bold text-gray-500 uppercase tracking-wider mb-1">
                      <span>Wire Frame / Code Execution:</span>
                      <button
                        type="button"
                        onclick="window.exoCopyCode && window.exoCopyCode(this)"
                        class="text-[10px] font-mono font-bold px-2 py-0.5 rounded bg-gray-200 hover:bg-gray-300 text-gray-700 flex items-center gap-1 cursor-pointer"
                      >
                        <span class="copy-icon">📋</span>
                        <span class="copy-text">Copy</span>
                      </button>
                    </div>
                    <pre class="bg-slate-950 text-gray-200 p-4 rounded-xl font-mono text-xs overflow-x-auto border border-slate-800 leading-relaxed shadow-sm"><code>{highlight_code(step.wire_sample)}</code></pre>
                  </div>
                </div>
              </details>
            </div>
          <% end %>
        </div>

        <!-- 2. EVENT PUB/SUB SEQUENTIAL CASCADE -->
        <div id="cascade-event-workflow" class="hidden space-y-4 relative">
          <!-- Pixel-Perfect Centered Vertical Pipeline Line (Center at 16px) -->
          <div class="absolute left-4 -translate-x-1/2 top-4 bottom-4 w-0.5 bg-gradient-to-b from-emerald-400 via-amber-400 to-blue-400 z-0"></div>

          <%= for step <- @event_workflow_steps do %>
            <div class="flex items-start gap-4 relative z-10" data-workflow-type="event" data-step-num={step.step} data-actor-node={step.actor_node}>
              <!-- Concentric Step Circle Badge -->
              <div class={"w-8 h-8 rounded-full border-2 flex items-center justify-center text-xs font-black shadow-sm shrink-0 z-10 #{case step.color do
                "blue" -> "bg-blue-600 text-white border-blue-200"
                "violet" -> "bg-violet-600 text-white border-violet-200"
                "amber" -> "bg-amber-500 text-white border-amber-200"
                "emerald" -> "bg-emerald-600 text-white border-emerald-200"
              end}"}>
                <%= step.step %>
              </div>

              <!-- Expandable Accordion Card -->
              <details class="group flex-1 bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden transition-all duration-200 hover:border-violet-300">
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

                  <div class="relative group/code">
                    <div class="flex items-center justify-between text-[10px] font-mono font-bold text-gray-500 uppercase tracking-wider mb-1">
                      <span>Wire Event Frame:</span>
                      <button
                        type="button"
                        onclick="window.exoCopyCode && window.exoCopyCode(this)"
                        class="text-[10px] font-mono font-bold px-2 py-0.5 rounded bg-gray-200 hover:bg-gray-300 text-gray-700 flex items-center gap-1 cursor-pointer"
                      >
                        <span class="copy-icon">📋</span>
                        <span class="copy-text">Copy</span>
                      </button>
                    </div>
                    <pre class="bg-slate-950 text-gray-200 p-4 rounded-xl font-mono text-xs overflow-x-auto border border-slate-800 leading-relaxed shadow-sm"><code>{highlight_code(step.wire_sample)}</code></pre>
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
                <p class="text-xs text-slate-400">Progressive Disclosure, 1-Hop Spotlighting, and Interconnect Topology</p>
              </div>
            </div>

            <!-- Modal Controls -->
            <div class="flex items-center gap-3">
              <div class="flex items-center bg-slate-800 rounded-xl p-0.5 text-xs font-mono font-bold text-slate-200">
                <button
                  type="button"
                  onclick="window.ExoGraphEngine.zoom('modal-arch-graph', 0.85)"
                  class="w-7 h-7 flex items-center justify-center rounded-lg hover:bg-slate-700 cursor-pointer"
                >
                  −
                </button>
                <span id="modal-arch-graph-zoom-level" class="px-2 select-none">100%</span>
                <button
                  type="button"
                  onclick="window.ExoGraphEngine.zoom('modal-arch-graph', 1.15)"
                  class="w-7 h-7 flex items-center justify-center rounded-lg hover:bg-slate-700 cursor-pointer"
                >
                  +
                </button>
                <button
                  type="button"
                  onclick="window.ExoGraphEngine.fit('modal-arch-graph')"
                  class="px-2 h-7 flex items-center justify-center rounded-lg hover:bg-slate-700 text-[10px] font-sans cursor-pointer border-l border-slate-700"
                >
                  Fit
                </button>
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
          </div>

          <!-- Modal Body Canvas -->
          <div
            id="modal-arch-graph-container"
            phx-hook="ArchGraph"
            onmouseenter="window.ExoGraphEngine && window.ExoGraphEngine.initPanZoom('modal-arch-graph')"
            class="flex-1 overflow-hidden relative p-4 select-none cursor-grab"
          >
            <div class="graph-canvas-bg absolute inset-0 z-0"></div>
            <div id="modal-arch-graph-viewport" class="absolute top-0 left-0 w-[1080px] h-[850px] transition-transform duration-75 z-10">
              {render_network_svg(assigns, "modal")}
            </div>
            <!-- In-Modal Docked Drawer -->
            {render_docked_drawer("modal-node-inspector")}
          </div>
        </div>
      </div>
    </div>
    <script>
      (function() {
        if (window.ExoGraphEngine) {
          window.ExoGraphEngine.initPanZoom('arch-graph');
          window.ExoGraphEngine.initPanZoom('modal-arch-graph');
        }
      })();
    </script>
    """
  end

  # ---- Helper: Docked In-Graph Inspector Drawer ----

  defp render_docked_drawer(drawer_id) do
    assigns = %{drawer_id: drawer_id}

    ~H"""
    <div
      id={@drawer_id}
      class="graph-docked-drawer absolute top-4 right-4 bottom-4 w-80 sm:w-96 bg-slate-900/95 border border-slate-700/80 rounded-3xl shadow-2xl p-6 text-white flex flex-col justify-between z-30 translate-x-full transition-transform duration-300 backdrop-blur-md hidden"
      onclick="event.stopPropagation()"
    >
      <div class="space-y-5">
        <!-- Close button & Header -->
        <div class="flex items-start justify-between gap-3 border-b border-slate-800 pb-4">
          <div class="flex items-center gap-3">
            <div class="drawer-icon w-12 h-12 rounded-2xl bg-slate-800/90 border border-slate-700 flex items-center justify-center text-2xl shrink-0 shadow-inner">
              🎯
            </div>
            <div>
              <div class="flex items-center gap-2">
                <h3 class="drawer-title text-base font-black text-white tracking-tight">
                  ActionDispatcher
                </h3>
              </div>
              <div class="drawer-subtitle text-xs font-mono font-semibold text-violet-400 mt-0.5">
                Scope &amp; Route Engine
              </div>
            </div>
          </div>

          <button
            type="button"
            onclick="window.ExoGraphEngine.clearSpotlight()"
            class="w-7 h-7 rounded-full bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white flex items-center justify-center font-bold text-xs transition-colors cursor-pointer"
            title="Dismiss Inspector"
          >
            ✕
          </button>
        </div>

        <div class="flex items-center justify-between">
          <span class="drawer-badge text-[10px] font-mono font-bold px-2.5 py-0.5 rounded-full bg-amber-400/20 text-amber-300 border border-amber-400/30">
            KERNEL [IMMUTABLE]
          </span>
          <span class="drawer-package text-[11px] font-mono text-slate-400">
            Kernel Core
          </span>
        </div>

        <!-- Description -->
        <div class="bg-slate-950/70 p-3.5 rounded-2xl border border-slate-800/80">
          <div class="text-[10px] font-mono font-bold text-slate-400 uppercase tracking-wider mb-1">
            Subsystem Role &amp; Responsibility
          </div>
          <p class="drawer-desc text-xs text-slate-200 leading-relaxed">
            Zero-latency in-memory security scope verification (:guest, :player, :admin) &amp; provider routing.
          </p>
        </div>

        <!-- Protocol & Transport -->
        <div class="bg-slate-800/40 p-3 rounded-xl border border-slate-700/60 flex items-center justify-between">
          <span class="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Interconnect</span>
          <span class="drawer-protocol text-xs font-bold text-violet-300 font-mono">
            In-Memory Zero-Copy
          </span>
        </div>

        <!-- 1-Hop Upstream Dependencies (What calls or supplies this) -->
        <div class="space-y-1.5">
          <div class="text-[10px] font-mono font-bold text-amber-400 uppercase tracking-wider flex items-center gap-1">
            <span>▲</span> <span>Direct Upstream Dependencies:</span>
          </div>
          <div class="drawer-upstream-list flex flex-wrap gap-1.5">
            <!-- Dynamically populated -->
          </div>
        </div>

        <!-- 1-Hop Downstream Consumers (What depends on this) -->
        <div class="space-y-1.5">
          <div class="text-[10px] font-mono font-bold text-emerald-400 uppercase tracking-wider flex items-center gap-1">
            <span>▼</span> <span>Direct Downstream Consumers:</span>
          </div>
          <div class="drawer-downstream-list flex flex-wrap gap-1.5">
            <!-- Dynamically populated -->
          </div>
        </div>
      </div>

      <!-- Footer -->
      <div class="pt-3 border-t border-slate-800 flex items-center justify-between text-[11px] text-slate-400">
        <span>Click canvas or ESC to dismiss</span>
        <button
          type="button"
          onclick="window.ExoGraphEngine.clearSpotlight()"
          class="text-violet-400 hover:text-violet-300 font-semibold cursor-pointer"
        >
          Dismiss
        </button>
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
      viewBox="0 0 1080 850"
      class="w-full h-auto select-none font-sans"
    >
      <defs>
        <!-- Arrowhead Markers -->
        <marker id={"#{@prefix}net-arrow"} viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#64748b" />
        </marker>
        <marker id={"#{@prefix}net-arrow-amber"} viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#f59e0b" />
        </marker>
        <marker id={"#{@prefix}net-arrow-emerald"} viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#10b981" />
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

      <!-- Subsystem Macro Envelopes (Progressive Disclosure Containers) -->
      <g class="uml-packages">
        <!-- Package 1: Ingress (Client & Dev Tooling) -->
        <g class="uml-package-box" data-category="client" data-subsystem="client">
          <rect x="20" y="20" width="1040" height="135" rx="20" fill="#0f172a" fill-opacity="0.6" stroke="#334155" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 20 44 L 145 44 L 157 32 L 157 20 L 20 20 Z" fill="#1e293b" />
          <text x="30" y="36" fill="#94a3b8" font-size="9" font-weight="bold" font-family="monospace">package Ingress</text>
        </g>

        <!-- Package 2: Gateways Layer -->
        <g class="uml-package-box" data-category="extension" data-subsystem="gateways">
          <rect x="20" y="185" width="1040" height="135" rx="20" fill="#0f172a" fill-opacity="0.6" stroke="#475569" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 20 209 L 145 209 L 157 197 L 157 185 L 20 185 Z" fill="#1e293b" />
          <text x="30" y="201" fill="#94a3b8" font-size="9" font-weight="bold" font-family="monospace">package Gateways</text>
        </g>

        <!-- Package 3: Kernel Core (Microkernel Boundary) -->
        <g class="uml-package-box" data-category="kernel" data-subsystem="kernel">
          <rect x="20" y="350" width="1040" height="150" rx="20" fill="#181308" fill-opacity="0.8" stroke="#f59e0b" stroke-width="2" filter={"url(##{@prefix}kernel-glow)"} />
          <path d="M 20 374 L 175 374 L 187 362 L 187 350 L 20 350 Z" fill="#451a03" />
          <text x="30" y="366" fill="#fde047" font-size="9.5" font-weight="black" font-family="monospace">⚡ package Kernel Core</text>
        </g>

        <!-- Package 4: Extension Workers -->
        <g class="uml-package-box" data-category="extension" data-subsystem="extension">
          <rect x="20" y="530" width="1040" height="135" rx="20" fill="#0f172a" fill-opacity="0.6" stroke="#059669" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 20 554 L 155 554 L 167 542 L 167 530 L 20 530 Z" fill="#064e3b" />
          <text x="30" y="546" fill="#6ee7b7" font-size="9.5" font-weight="bold" font-family="monospace">package Extensions</text>
        </g>

        <!-- Package 5: Data & Storage -->
        <g class="uml-package-box" data-category="internal" data-subsystem="storage">
          <rect x="20" y="695" width="1040" height="135" rx="20" fill="#0f172a" fill-opacity="0.6" stroke="#0284c7" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 20 719 L 145 719 L 157 707 L 157 695 L 20 695 Z" fill="#082f49" />
          <text x="30" y="711" fill="#7dd3fc" font-size="9.5" font-weight="bold" font-family="monospace">package Storage</text>
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
            class="graph-edge opacity-60 transition-all duration-200"
            data-edge-from={edge.from}
            data-edge-to={edge.to}
          />
          <!-- Animated Flow Overlay -->
          <path
            d={edge.path}
            fill="none"
            stroke="#8b5cf6"
            stroke-width="1.8"
            class="animate-flow-dash opacity-75 pointer-events-none"
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
            data-group-id={comp.group}
            data-node-id={comp.id}
            data-node-title={comp.title}
            data-node-subtitle={comp.subtitle}
            data-node-badge={comp.badge}
            data-node-desc={comp.desc}
            data-node-package={comp.package}
            data-node-icon={comp.icon}
            data-node-protocol={comp.protocol}
            data-node-upstream={comp.upstream}
            data-node-downstream={comp.downstream}
            onclick="window.ExoGraphEngine.spotlightNode(this)"
            transform={"translate(#{comp.x}, #{comp.y})"}
          >
            <!-- Card Outer Box -->
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
              class="group-hover:stroke-white transition-all duration-150"
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
