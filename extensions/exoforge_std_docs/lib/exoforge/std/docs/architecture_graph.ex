defmodule Exoforge.Std.Docs.ArchitectureGraph do
  @moduledoc """
  Interactive UML Architecture Diagram, Fullscreen Maximizer, and Sequential Workflow
  Pipeline Visualizer for Exoforge.
  """
  use Phoenix.Component

  # ---- Architecture Components Specification ----

  @components [
    %{
      id: "unity_client",
      title: "Unity Client SDK",
      subtitle: "com.exoforge.sdk",
      desc: "Game client runtime with async/await stubs, device anonymous auth, and reactive event hooks.",
      icon: "🕹️",
      package: "Client Ingress",
      category: "client",
      badge: "GAME CLIENT",
      x: 45,
      y: 75,
      width: 160,
      height: 70
    },
    %{
      id: "exo_cli",
      title: "Exo CLI & Engine",
      subtitle: "Management Engine",
      desc: "Local development CLI, scaffolding, C# extension compiler, and remote cluster push.",
      icon: "💻",
      package: "Developer Tooling",
      category: "tooling",
      badge: "DEV TOOLING",
      x: 45,
      y: 195,
      width: 160,
      height: 70
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
      x: 45,
      y: 315,
      width: 160,
      height: 70
    },
    %{
      id: "ws_gateway",
      title: "WebSocket Gateway",
      subtitle: ":ws on port 4000",
      desc: "Real-time framed JSON WebSocket ingress and low-latency bidirectional pub/sub event bus.",
      icon: "⚡",
      package: "Gateway Layer",
      category: "extension",
      badge: "GATEWAY EXTENSION",
      x: 265,
      y: 75,
      width: 160,
      height: 70
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
      x: 265,
      y: 195,
      width: 160,
      height: 70
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
      x: 265,
      y: 315,
      width: 160,
      height: 70
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
      x: 485,
      y: 65,
      width: 170,
      height: 65
    },
    %{
      id: "event_dispatcher",
      title: "EventDispatcher",
      subtitle: ":pg Distributed Bus",
      desc: "Pattern-matched topic fanout over Erlang process groups (0.07 ms SLA to 50 concurrent subscribers).",
      icon: "📡",
      package: "Kernel Core",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      x: 485,
      y: 155,
      width: 170,
      height: 65
    },
    %{
      id: "extension_registry",
      title: "ExtensionRegistry",
      subtitle: "In-Memory ETS Catalog",
      desc: "Lockless ETS table of registered extensions, action contracts, resources, and route metadata.",
      icon: "📚",
      package: "Kernel Core",
      category: "kernel",
      badge: "KERNEL [IMMUTABLE]",
      x: 485,
      y: 245,
      width: 170,
      height: 65
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
      x: 485,
      y: 335,
      width: 170,
      height: 65
    },
    %{
      id: "native_csharp",
      title: "Native C# Game Worker",
      subtitle: ".NET OS Process (stdio IPC)",
      desc: "Framework-dependent single-file binary with AOT trimming, zero reflection, and static dispatch delegates.",
      icon: "⚙️",
      package: "Extension Workers",
      category: "extension",
      badge: "GAME EXTENSION",
      x: 715,
      y: 75,
      width: 170,
      height: 75
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
      x: 715,
      y: 195,
      width: 170,
      height: 70
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
      x: 715,
      y: 315,
      width: 170,
      height: 70
    },
    %{
      id: "database_manager",
      title: "Database Manager",
      subtitle: ":database service",
      desc: "Multi-engine database service managing connection pools and per-extension schema isolation.",
      icon: "🗄️",
      package: "Data & Storage",
      category: "extension",
      badge: "STORAGE EXTENSION",
      x: 950,
      y: 75,
      width: 180,
      height: 75
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
      x: 950,
      y: 195,
      width: 180,
      height: 70
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
      x: 950,
      y: 315,
      width: 180,
      height: 70
    }
  ]

  @edges [
    %{from: "unity_client", to: "ws_gateway", path: "M 205 110 L 265 110", label: "WebSocket"},
    %{from: "unity_client", to: "http_gateway", path: "M 205 110 C 235 110, 235 230, 265 230", label: "REST"},
    %{from: "exo_cli", to: "http_gateway", path: "M 205 230 L 265 230", label: "Build Push"},
    %{from: "producer_studio", to: "action_dispatcher", path: "M 205 350 C 345 350, 345 95, 485 95", label: "LiveView"},
    %{from: "ws_gateway", to: "action_dispatcher", path: "M 425 110 C 455 110, 455 95, 485 95", label: "dispatch"},
    %{from: "ws_gateway", to: "event_dispatcher", path: "M 425 110 C 455 110, 455 185, 485 185", label: ":pg pub/sub"},
    %{from: "http_gateway", to: "action_dispatcher", path: "M 425 230 C 455 230, 455 95, 485 95", label: "route"},
    %{from: "transport_layer", to: "action_dispatcher", path: "M 425 350 C 455 350, 455 95, 485 95", label: "normalized"},
    %{from: "action_dispatcher", to: "extension_registry", path: "M 570 130 L 570 245", label: "lookup"},
    %{from: "action_dispatcher", to: "native_csharp", path: "M 655 95 C 685 95, 685 110, 715 110", label: "stdio IPC"},
    %{from: "action_dispatcher", to: "elixir_runner", path: "M 655 95 C 685 95, 685 230, 715 230", label: "actor"},
    %{from: "action_dispatcher", to: "std_services", path: "M 655 95 C 685 95, 685 350, 715 350", label: "dispatch"},
    %{from: "native_csharp", to: "database_manager", path: "M 885 110 L 950 110", label: "host_call"},
    %{from: "database_manager", to: "storage_adapters", path: "M 1040 150 L 1040 315", label: "SQL"}
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
        "payload": { "score": 1500 },
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
      // Strips unverified spoofed auth; forcibly stamps session
      sanitized_payload = %{
        "score" => 1500,
        "player_id" => "usr_99a8b1",
        "_auth" => %{player_id: "usr_99a8b1", scopes: ["player"]}
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
      summary: "Kernel verifies that caller's scopes satisfy the contract requirements and resolves worker entry point in ETS.",
      wire_sample: """
      // In-Memory Kernel Dispatch & Scope Check
      case verify_scope(manifest.scope, caller_scopes) do
        :ok -> route_to_worker(manifest.entry_point, payload)
        {:error, reason} -> {:error, :unauthorized}
      end
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
      // C# Action Execution (Framework-Dependent Single File)
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
      -- Isolated schema query executed by host bridge
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
      // Extension Host Call over Stdio
      {
        "type": "host_call",
        "op": "publish_event",
        "args": {
          "event": "snake.score_submitted",
          "payload": { "player_id": "usr_1", "score": 1500 }
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
      title: "Kernel Event Fanout via :pg",
      actor: "EventDispatcher (Kernel)",
      action: "EventDispatcher.broadcast(\"snake.score_submitted\", payload)",
      summary: "Kernel matches event against active topic subscribers and fans out over distributed Erlang process groups.",
      wire_sample: """
      // Verified SLA: 0.07 ms fanout to 50 concurrent subscribers over :pg
      :pg.get_members(:exo_events, topic)
      |> Enum.each(&send(&1, {:exo_event, topic, payload}))
      """,
      latency: "0.07 ms verified SLA",
      badge: "Kernel",
      color: "amber",
      details: "Erlang distributed process groups (:pg) deliver messages directly to subscriber process mailboxes with zero central serialization bottleneck."
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
            UML component architecture, fullscreen inspection, and end-to-end sequential workflow cascades.
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
            <span>📐</span>
            <span>UML Architecture</span>
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

      <!-- VIEW 1: UML ARCHITECTURE COMPONENT DIAGRAM -->
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
            <span class="text-gray-400 text-[11px] mr-1 hidden sm:inline">Highlight Package:</span>
            <button
              type="button"
              onclick="window.exoHighlightPackage('all')"
              id="pkg-btn-all"
              class="px-2.5 py-1 rounded-lg bg-slate-900 text-white shadow-2xs transition-all cursor-pointer text-xs"
            >
              All Packages
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

        <!-- Inline SVG UML Diagram Container -->
        <div class="border border-gray-200/90 rounded-3xl bg-slate-950 overflow-x-auto relative shadow-inner p-4">
          <div class="min-w-[1160px]">
            {render_uml_svg(assigns, "inline")}
          </div>
        </div>

        <!-- Interactive Component Inspector Card -->
        <div id="arch-node-inspector" class="bg-white p-5 rounded-3xl border border-gray-200/90 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <div id="inspector-icon" class="w-12 h-12 rounded-2xl bg-amber-50 text-amber-700 border border-amber-200 flex items-center justify-center text-2xl shrink-0">
              🎯
            </div>
            <div>
              <div class="flex items-center gap-2">
                <h4 id="inspector-title" class="text-base font-bold text-gray-900 tracking-tight">
                  ActionDispatcher
                </h4>
                <span id="inspector-badge" class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-full bg-amber-50 text-amber-700 border border-amber-200">
                  KERNEL [IMMUTABLE]
                </span>
              </div>
              <div id="inspector-subtitle" class="text-xs font-mono font-semibold text-violet-600 mt-0.5">
                Scope &amp; Route Engine
              </div>
              <p id="inspector-desc" class="text-xs text-gray-600 mt-1 max-w-xl">
                Zero-latency in-memory security scope verification (:guest, :player, :admin) &amp; provider routing.
              </p>
            </div>
          </div>

          <div class="bg-gray-50 p-3.5 rounded-2xl border border-gray-200/80 md:max-w-xs shrink-0">
            <div class="text-[10px] font-bold text-gray-500 uppercase tracking-wider">
              Subsystem Package
            </div>
            <div id="inspector-package" class="text-xs font-bold text-gray-900 mt-0.5">
              Kernel Core
            </div>
          </div>
        </div>

        <!-- Clickable UML Component Directory -->
        <div class="bg-white p-5 rounded-3xl border border-gray-200/80 shadow-2xs space-y-3">
          <div class="text-xs font-bold text-gray-500 uppercase tracking-wider">
            Click to Inspect Subsystem Components:
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-8 gap-2">
            <%= for comp <- @components do %>
              <button
                type="button"
                onclick={"window.exoSelectComponentById('#{comp.id}')"}
                class={"p-2.5 rounded-xl border text-left transition-all cursor-pointer hover:shadow-sm group flex flex-col justify-between h-20 #{case comp.category do
                  "kernel" -> "bg-amber-50/60 border-amber-200 hover:border-amber-400"
                  "extension" -> "bg-violet-50/60 border-violet-200 hover:border-violet-400"
                  "internal" -> "bg-cyan-50/60 border-cyan-200 hover:border-cyan-400"
                  _ -> "bg-gray-50/80 border-gray-200 hover:border-gray-400"
                end}"}
              >
                <div class="flex items-center justify-between">
                  <span class="text-base"><%= comp.icon %></span>
                  <span class="text-[9px] font-mono font-bold text-gray-500 uppercase">
                    <%= comp.category %>
                  </span>
                </div>
                <div class="font-bold text-[11px] text-gray-900 truncate group-hover:text-violet-700">
                  <%= comp.title %>
                </div>
              </button>
            <% end %>
          </div>
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
          <div class="absolute left-6 top-6 bottom-6 w-0.5 bg-gradient-to-b from-blue-400 via-violet-400 to-emerald-400 z-0"></div>

          <%= for step <- @action_workflow_steps do %>
            <div class="relative z-10 pl-14">
              <!-- Step Circle Badge on Pipeline Line -->
              <div class={"absolute left-3.5 -translate-x-1/2 top-5 w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs font-black shadow-sm #{case step.color do
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

                <!-- Expanded Details & Wire JSON Framing -->
                <div class="p-5 pt-0 border-t border-gray-100 bg-gray-50/50 space-y-3">
                  <p class="text-xs text-gray-600 mt-3 leading-relaxed">
                    <%= step.details %>
                  </p>

                  <div>
                    <div class="text-[10px] font-mono font-bold text-gray-500 uppercase tracking-wider mb-1">
                      Wire Frame / Code Execution:
                    </div>
                    <pre class="bg-gray-950 text-gray-200 p-3.5 rounded-xl font-mono text-[11px] overflow-x-auto border border-gray-800 leading-tight"><code><%= step.wire_sample %></code></pre>
                  </div>
                </div>
              </details>
            </div>
          <% end %>
        </div>

        <!-- 2. EVENT PUB/SUB SEQUENTIAL CASCADE -->
        <div id="cascade-event-workflow" class="hidden space-y-4 relative">
          <!-- Continuous Vertical Pipeline Line -->
          <div class="absolute left-6 top-6 bottom-6 w-0.5 bg-gradient-to-b from-emerald-400 via-amber-400 to-blue-400 z-0"></div>

          <%= for step <- @event_workflow_steps do %>
            <div class="relative z-10 pl-14">
              <!-- Step Circle Badge on Pipeline Line -->
              <div class={"absolute left-3.5 -translate-x-1/2 top-5 w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs font-black shadow-sm #{case step.color do
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
                    <pre class="bg-gray-950 text-gray-200 p-3.5 rounded-xl font-mono text-[11px] overflow-x-auto border border-gray-800 leading-tight"><code><%= step.wire_sample %></code></pre>
                  </div>
                </div>
              </details>
            </div>
          <% end %>
        </div>
      </div>

      <!-- FULLSCREEN MODAL POPUP FOR ARCHITECTURE DIAGRAM -->
      <div id="arch-graph-modal" class="hidden fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex flex-col p-4 sm:p-6 animate-in fade-in duration-150">
        <div class="bg-slate-950 rounded-3xl border border-slate-800 flex-1 flex flex-col overflow-hidden shadow-2xl">
          <!-- Modal Header -->
          <div class="flex items-center justify-between p-4 px-6 border-b border-slate-800 bg-slate-900/80">
            <div class="flex items-center gap-3">
              <span class="text-xl">📐</span>
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
          <div class="flex-1 overflow-auto p-6 flex items-center justify-center">
            <div class="w-full max-w-[1240px]">
              {render_uml_svg(assigns, "modal")}
            </div>
          </div>
        </div>
      </div>

      <!-- JavaScript Controller for Diagram Interaction -->
      <script>
        (function() {
          const components = <%= Phoenix.HTML.raw(Jason.encode!(Map.new(@components, fn c -> {c.id, c} end))) %>;

          window.exoSelectComponentById = function(id) {
            const comp = components[id];
            if (!comp) return;

            const titleEl = document.getElementById('inspector-title');
            const subEl = document.getElementById('inspector-subtitle');
            const badgeEl = document.getElementById('inspector-badge');
            const descEl = document.getElementById('inspector-desc');
            const pkgEl = document.getElementById('inspector-package');
            const iconEl = document.getElementById('inspector-icon');

            if (titleEl) titleEl.innerText = comp.title;
            if (subEl) subEl.innerText = comp.subtitle;
            if (badgeEl) badgeEl.innerText = comp.badge;
            if (descEl) descEl.innerText = comp.desc;
            if (pkgEl) pkgEl.innerText = comp.package;
            if (iconEl) iconEl.innerText = comp.icon;
          };

          window.exoHighlightPackage = function(category) {
            const nodes = document.querySelectorAll('.uml-comp-node');
            const packages = document.querySelectorAll('.uml-package-box');

            nodes.forEach(node => {
              const nodeCat = node.getAttribute('data-category');
              if (category === 'all' || nodeCat === category) {
                node.style.opacity = '1.0';
              } else {
                node.style.opacity = '0.2';
              }
            });

            // Update toolbar button states
            ['all', 'kernel', 'extension', 'internal'].forEach(cat => {
              const btn = document.getElementById('pkg-btn-' + cat);
              if (btn) {
                if (cat === category) {
                  btn.classList.add('ring-2', 'ring-offset-1', 'ring-violet-500');
                } else {
                  btn.classList.remove('ring-2', 'ring-offset-1', 'ring-violet-500');
                }
              }
            });
          };

          // Close modal on Escape key
          document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') {
              const modal = document.getElementById('arch-graph-modal');
              if (modal) modal.classList.add('hidden');
            }
          });
        })();
      </script>
    </div>
    """
  end

  # Helper to render the UML Architecture SVG
  defp render_uml_svg(assigns, variant) do
    prefix = if variant == "modal", do: "m_", else: "i_"
    assigns = assign(assigns, :prefix, prefix)

    ~H"""
    <svg
      viewBox="0 0 1180 440"
      class="w-full h-auto select-none font-sans"
    >
      <defs>
        <marker id={"#{@prefix}uml-arrow"} viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#64748b" />
        </marker>
        <filter id={"#{@prefix}uml-shadow"} x="-10%" y="-10%" width="120%" height="120%">
          <feDropShadow dx="0" dy="4" stdDeviation="5" flood-color="#000000" flood-opacity="0.35" />
        </filter>
      </defs>

      <!-- Subsystem UML Packages (Envelopes) -->
      <g class="uml-packages">
        <!-- Package 1: Client Ingress -->
        <g class="uml-package-box" data-category="client">
          <rect x="30" y="30" width="190" height="390" rx="16" fill="#0f172a" stroke="#334155" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 30 54 L 140 54 L 152 42 L 152 30 L 30 30 Z" fill="#1e293b" />
          <text x="42" y="46" fill="#94a3b8" font-size="9" font-weight="bold" font-family="monospace">package Ingress</text>
        </g>

        <!-- Package 2: Gateways -->
        <g class="uml-package-box" data-category="extension">
          <rect x="250" y="30" width="190" height="390" rx="16" fill="#0f172a" stroke="#6d28d9" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 250 54 L 370 54 L 382 42 L 382 30 L 250 30 Z" fill="#2e1065" />
          <text x="262" y="46" fill="#c4b5fd" font-size="9" font-weight="bold" font-family="monospace">package Gateways</text>
        </g>

        <!-- Package 3: Kernel Core (Glow Boundary) -->
        <g class="uml-package-box" data-category="kernel">
          <rect x="470" y="30" width="200" height="390" rx="16" fill="#1e180d" stroke="#f59e0b" stroke-width="2" />
          <path d="M 470 54 L 620 54 L 632 42 L 632 30 L 470 30 Z" fill="#451a03" />
          <text x="482" y="46" fill="#fde047" font-size="9" font-weight="black" font-family="monospace">⚡ package Kernel</text>
        </g>

        <!-- Package 4: Extension Workers -->
        <g class="uml-package-box" data-category="extension">
          <rect x="700" y="30" width="200" height="390" rx="16" fill="#0f172a" stroke="#059669" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 700 54 L 840 54 L 852 42 L 852 30 L 700 30 Z" fill="#064e3b" />
          <text x="712" y="46" fill="#6ee7b7" font-size="9" font-weight="bold" font-family="monospace">package Extensions</text>
        </g>

        <!-- Package 5: Storage -->
        <g class="uml-package-box" data-category="internal">
          <rect x="930" y="30" width="220" height="390" rx="16" fill="#0f172a" stroke="#0284c7" stroke-width="1.2" stroke-dasharray="4 3" />
          <path d="M 930 54 L 1060 54 L 1072 42 L 1072 30 L 930 30 Z" fill="#082f49" />
          <text x="942" y="46" fill="#7dd3fc" font-size="9" font-weight="bold" font-family="monospace">package Storage</text>
        </g>
      </g>

      <!-- UML Connecting Directed Edges -->
      <g class="uml-edges">
        <%= for edge <- @edges do %>
          <path
            d={edge.path}
            fill="none"
            stroke="#64748b"
            stroke-width="1.8"
            marker-end={"url(##{@prefix}uml-arrow)"}
            class="opacity-70 hover:opacity-100 hover:stroke-violet-400 transition-opacity"
          />
        <% end %>
      </g>

      <!-- UML Components -->
      <g class="uml-components">
        <%= for comp <- @components do %>
          <g
            class="uml-comp-node cursor-pointer group transition-transform duration-100"
            data-category={comp.category}
            data-id={comp.id}
            onclick={"window.exoSelectComponentById('#{comp.id}')"}
            transform={"translate(#{comp.x}, #{comp.y})"}
          >
            <!-- Component Outer Rectangle -->
            <rect
              width={comp.width}
              height={comp.height}
              rx="12"
              fill={case comp.category do
                "kernel" -> "#291e0a"
                "extension" -> "#1e1b4b"
                "internal" -> "#082f49"
                _ -> "#1e293b"
              end}
              stroke={case comp.category do
                "kernel" -> "#f59e0b"
                "extension" -> "#8b5cf6"
                "internal" -> "#06b6d4"
                _ -> "#475569"
              end}
              stroke-width={if comp.category == "kernel", do: "2", else: "1.2"}
              filter={"url(##{@prefix}uml-shadow)"}
              class="group-hover:stroke-white transition-colors"
            />

            <!-- UML Stereotype <<component>> -->
            <text x="10" y="16" fill="#94a3b8" font-size="8" font-family="monospace">&laquo;component&raquo;</text>

            <!-- Icon & Title -->
            <text x="10" y="32" font-size="13"><%= comp.icon %></text>
            <text
              x="30"
              y="32"
              fill="#ffffff"
              font-size="10.5"
              font-weight="bold"
              font-family="system-ui, sans-serif"
            >
              <%= comp.title %>
            </text>

            <!-- Subtitle -->
            <text
              x="10"
              y="48"
              fill={case comp.category do
                "kernel" -> "#fcd34d"
                "extension" -> "#c4b5fd"
                "internal" -> "#67e8f9"
                _ -> "#94a3b8"
              end}
              font-size="8.5"
              font-weight="bold"
              font-family="monospace"
            >
              <%= comp.subtitle %>
            </text>
          </g>
        <% end %>
      </g>
    </svg>
    """
  end
end
