defmodule Exoforge.Std.Docs.ArchitectureGraph do
  @moduledoc """
  Interactive SVG architecture DAG topology, zoomable inspector, and sequential cascade
  workflow pipeline visualizer for Exoforge.
  """
  use Phoenix.Component

  # ---- Architecture Nodes Definition ----

  @nodes [
    %{
      id: "unity_client",
      title: "Unity Client SDK",
      subtitle: "com.exoforge.sdk",
      desc: "Game client runtime with async/await stubs, device auth, and reactive event bindings.",
      icon: "🕹️",
      category: "client",
      badge: "CLIENT",
      x: 40,
      y: 60,
      litmus: "Client Ingress (Calls gateways over network; not an extension)"
    },
    %{
      id: "exo_cli",
      title: "Exo CLI & Engine",
      subtitle: "Management Engine",
      desc: "Local development CLI, scaffolding, C# extension compiler, and remote cluster push.",
      icon: "💻",
      category: "tooling",
      badge: "TOOLING",
      x: 40,
      y: 200,
      litmus: "Developer Tooling (External executable; interacts via HTTP API)"
    },
    %{
      id: "producer_studio",
      title: "Producer Studio",
      subtitle: "LiveView Dashboard :4005",
      desc: "Web-based actor inspector, live metrics, extension lifecycle manager, and dev guide.",
      icon: "🎛️",
      category: "studio",
      badge: "STUDIO",
      x: 40,
      y: 340,
      litmus: "Studio Extension (LiveView UI interacting with kernel and extensions)"
    },
    %{
      id: "ws_gateway",
      title: "WebSocket Gateway",
      subtitle: ":ws on port 4000",
      desc: "Framed realtime JSON WebSocket ingress & low-latency bidirectional pub/sub bus.",
      icon: "⚡",
      category: "extension",
      badge: "EXTENSION - PLUGGABLE",
      x: 260,
      y: 60,
      litmus: "Swappable (Can be swapped with TCP/UDP; other services do not compile against it)"
    },
    %{
      id: "http_gateway",
      title: "HTTP REST Gateway",
      subtitle: ":http on port 4001",
      desc: "Dynamic OpenAPI REST endpoints automatically derived from service action contracts.",
      icon: "🌐",
      category: "extension",
      badge: "EXTENSION - PLUGGABLE",
      x: 260,
      y: 200,
      litmus: "Swappable (Can be swapped with gRPC; other services do not compile against it)"
    },
    %{
      id: "transport_layer",
      title: "Transport Abstraction",
      subtitle: ":transport service",
      desc: "Normalizes inbound requests, strips spoofed auth, and stamps verified credentials.",
      icon: "🔄",
      category: "extension",
      badge: "EXTENSION - PLUGGABLE",
      x: 260,
      y: 340,
      litmus: "Contract Dependency (Gateways rely on this shared ingress contract)"
    },
    %{
      id: "action_dispatcher",
      title: "ActionDispatcher",
      subtitle: "Scope & Route Engine",
      desc: "Checks caller security scopes (:guest, :player, :admin) & routes actions to service providers.",
      icon: "🎯",
      category: "kernel",
      badge: "KERNEL - IMMUTABLE",
      x: 490,
      y: 60,
      litmus: "Boot Dependency (Required to route ANY action; cannot be swapped or disabled)"
    },
    %{
      id: "event_dispatcher",
      title: "EventDispatcher",
      subtitle: ":pg Distributed Bus",
      desc: "Pattern-matched topic fanout over Erlang process groups (0.07 ms SLA to 50 subscribers).",
      icon: "📡",
      category: "kernel",
      badge: "KERNEL - IMMUTABLE",
      x: 490,
      y: 160,
      litmus: "Boot Dependency (Provides the root event pub/sub mechanism of the cluster)"
    },
    %{
      id: "extension_registry",
      title: "ExtensionRegistry",
      subtitle: "In-Memory ETS Catalog",
      desc: "Lockless in-memory ETS table of registered extensions, action contracts, and resources.",
      icon: "📚",
      category: "kernel",
      badge: "KERNEL - IMMUTABLE",
      x: 490,
      y: 260,
      litmus: "Boot Dependency (Stores service metadata that the entire cluster reads)"
    },
    %{
      id: "extension_supervisor",
      title: "ExtensionSupervisor",
      subtitle: "Topological OTP DAG",
      desc: "Orders startup DAG, isolates worker crashes, and supervises actor lifecycle.",
      icon: "🛡️",
      category: "kernel",
      badge: "KERNEL - IMMUTABLE",
      x: 490,
      y: 360,
      litmus: "Boot Dependency (Owns the root supervision tree of the BEAM node)"
    },
    %{
      id: "native_csharp",
      title: "Native C# Game Extension",
      subtitle: ".NET Worker OS Process",
      desc: "IL trimmed & AOT tree-shaken single file running in an isolated OS worker over stdio IPC.",
      icon: "⚙️",
      category: "extension",
      badge: "EXTENSION - PLUGGABLE",
      x: 740,
      y: 60,
      litmus: "Game Feature (First-party game code; hot-reloaded and isolated in worker process)"
    },
    %{
      id: "elixir_runner",
      title: "Elixir System Extensions",
      subtitle: "OTP Actor Concurrency",
      desc: "Native BEAM actor processes running directly in cluster supervision tree.",
      icon: "🧪",
      category: "extension",
      badge: "EXTENSION - PLUGGABLE",
      x: 740,
      y: 200,
      litmus: "System Extension (Pluggable services written in native Elixir OTP)"
    },
    %{
      id: "std_services",
      title: "Standard Services",
      subtitle: "auth, player_data, cron",
      desc: "Standard platform services providing identity tokens, player profiles, and scheduled jobs.",
      icon: "📦",
      category: "extension",
      badge: "EXTENSION - PLUGGABLE",
      x: 740,
      y: 340,
      litmus: "Contract Dependency (Swappable implementations consumed via abstract service contracts)"
    },
    %{
      id: "database_manager",
      title: "Database Manager",
      subtitle: ":database service",
      desc: "Multi-engine storage routing with strict per-extension schema isolation.",
      icon: "🗄️",
      category: "extension",
      badge: "EXTENSION - PLUGGABLE",
      x: 970,
      y: 60,
      litmus: "Swappable (Swappable storage service consumed via :database atom)"
    },
    %{
      id: "resource_store",
      title: "Resource Store",
      subtitle: ":resource_store",
      desc: "Schema-driven entity storage with declarative typed CRUD and migrations.",
      icon: "📊",
      category: "extension",
      badge: "EXTENSION - PLUGGABLE",
      x: 970,
      y: 200,
      litmus: "Contract Dependency (Standard storage extension for typed game resources)"
    },
    %{
      id: "storage_adapters",
      title: "Storage Adapters",
      subtitle: "SQLite / PostgreSQL Engine",
      desc: "Low-level connection pools and query adapters internal to the database extension.",
      icon: "💾",
      category: "internal",
      badge: "INTERNAL",
      x: 970,
      y: 340,
      litmus: "Internal Implementation (Only consumed internally by the :database extension)"
    }
  ]

  @edges [
    %{from: "unity_client", to: "ws_gateway", path: "M 200 95 C 230 95, 230 95, 260 95", label: "WebSocket :4000"},
    %{from: "unity_client", to: "http_gateway", path: "M 200 95 C 230 95, 230 235, 260 235", label: "REST :4001"},
    %{from: "exo_cli", to: "http_gateway", path: "M 200 235 C 230 235, 230 235, 260 235", label: "REST Push"},
    %{from: "producer_studio", to: "action_dispatcher", path: "M 200 375 C 345 375, 345 95, 490 95", label: "Studio Dispatch"},
    %{from: "ws_gateway", to: "action_dispatcher", path: "M 420 95 C 455 95, 455 95, 490 95", label: "Dispatch"},
    %{from: "ws_gateway", to: "event_dispatcher", path: "M 420 95 C 455 95, 455 195, 490 195", label: "Pub/Sub"},
    %{from: "http_gateway", to: "action_dispatcher", path: "M 420 235 C 455 235, 455 95, 490 95", label: "Route"},
    %{from: "transport_layer", to: "action_dispatcher", path: "M 420 375 C 455 375, 455 95, 490 95", label: "Normalized"},
    %{from: "action_dispatcher", to: "extension_registry", path: "M 570 130 C 570 180, 570 210, 570 260", label: "Lookup"},
    %{from: "action_dispatcher", to: "native_csharp", path: "M 650 95 C 695 95, 695 95, 740 95", label: "Stdio IPC"},
    %{from: "action_dispatcher", to: "elixir_runner", path: "M 650 95 C 695 95, 695 235, 740 235", label: "Actor Msg"},
    %{from: "action_dispatcher", to: "std_services", path: "M 650 95 C 695 95, 695 375, 740 375", label: "Direct"},
    %{from: "native_csharp", to: "database_manager", path: "M 900 95 C 935 95, 935 95, 970 95", label: "Host Call"},
    %{from: "database_manager", to: "storage_adapters", path: "M 1050 130 C 1050 200, 1050 280, 1050 340", label: "Internal Pool"}
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
      |> assign_new(:nodes, fn -> @nodes end)
      |> assign_new(:edges, fn -> @edges end)
      |> assign_new(:action_workflow_steps, fn -> @action_workflow_steps end)
      |> assign_new(:event_workflow_steps, fn -> @event_workflow_steps end)

    ~H"""
    <div class="space-y-10 select-none font-sans" id="exoforge-architecture-visualizer">
      <!-- Section Header -->
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-gray-200">
        <div>
          <div class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-violet-50 text-violet-700 border border-violet-200 text-[10px] font-bold">
            <span class="w-1.5 h-1.5 rounded-full bg-violet-600 animate-pulse"></span>
            <span>Interactive Architecture Topology &amp; Execution Pipeline</span>
          </div>
          <h2 class="text-xl font-bold text-gray-900 tracking-tight mt-1">
            System Topology, Boundaries &amp; Execution Flow
          </h2>
          <p class="text-xs text-gray-500">
            Interactive Directed Acyclic Graph (DAG), zoomable inspection, and end-to-end sequential workflow cascades.
          </p>
        </div>

        <!-- Mode Toggle: Topology Graph vs Sequential Workflow -->
        <div class="flex items-center gap-2 p-1 bg-gray-100 rounded-xl border border-gray-200/80 text-xs font-semibold self-start sm:self-auto">
          <button
            type="button"
            onclick="document.getElementById('arch-view-graph').classList.remove('hidden'); document.getElementById('arch-view-workflow').classList.add('hidden'); document.getElementById('btn-tab-graph').classList.add('bg-white', 'text-violet-700', 'shadow-xs'); document.getElementById('btn-tab-workflow').classList.remove('bg-white', 'text-violet-700', 'shadow-xs');"
            id="btn-tab-graph"
            class="px-3.5 py-1.5 rounded-lg bg-white text-violet-700 shadow-xs transition-all flex items-center gap-1.5 cursor-pointer"
          >
            <span>🕸️</span>
            <span>Architecture Graph</span>
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

      <!-- VIEW 1: INTERACTIVE ZOOMABLE ARCHITECTURE GRAPH -->
      <div id="arch-view-graph" class="space-y-6">
        <!-- Architectural Doctrine & Litmus Test Banner -->
        <div class="bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 rounded-3xl p-6 text-white border border-slate-800 shadow-xl relative overflow-hidden">
          <div class="absolute -right-10 -bottom-10 opacity-10 text-9xl pointer-events-none select-none">
            ⚡
          </div>

          <div class="relative z-10 flex flex-col lg:flex-row lg:items-center justify-between gap-6">
            <div class="space-y-2 max-w-xl">
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold font-mono tracking-wider px-2 py-0.5 rounded-full bg-amber-400/20 text-amber-300 border border-amber-400/30">
                  ARCHITECTURAL DOCTRINE
                </span>
                <span class="text-xs text-slate-400">Rule &amp; One Exception</span>
              </div>
              <h3 class="text-lg font-black tracking-tight text-white">
                "The Rule: Everything above the kernel is an extension."
              </h3>
              <p class="text-xs text-slate-300 leading-relaxed">
                The kernel is strictly limited to 4 foundational primitives: <code class="text-amber-300 font-mono">ActionDispatcher</code>, <code class="text-amber-300 font-mono">EventDispatcher</code>, <code class="text-amber-300 font-mono">ExtensionRegistry</code>, and <code class="text-amber-300 font-mono">ExtensionSupervisor</code>. Everything else—gateways, auth, storage, and game features—is a pluggable extension.
              </p>
            </div>

            <!-- Litmus Test Interactive Buttons -->
            <div class="grid grid-cols-2 gap-2 text-xs">
              <button
                type="button"
                onclick="window.exoFilterNodes('extension')"
                class="p-2.5 rounded-xl bg-slate-800/80 hover:bg-slate-700/80 border border-slate-700 text-left transition-all cursor-pointer group"
              >
                <div class="text-[10px] font-bold text-emerald-400">1. Swappable?</div>
                <div class="text-[11px] text-slate-200 group-hover:text-white">REST ↔ WS ➔ Extension</div>
              </button>
              <button
                type="button"
                onclick="window.exoFilterNodes('extension')"
                class="p-2.5 rounded-xl bg-slate-800/80 hover:bg-slate-700/80 border border-slate-700 text-left transition-all cursor-pointer group"
              >
                <div class="text-[10px] font-bold text-violet-400">2. Contract Dep?</div>
                <div class="text-[11px] text-slate-200 group-hover:text-white">Dep by Contract ➔ Extension</div>
              </button>
              <button
                type="button"
                onclick="window.exoFilterNodes('kernel')"
                class="p-2.5 rounded-xl bg-slate-800/80 hover:bg-slate-700/80 border border-slate-700 text-left transition-all cursor-pointer group"
              >
                <div class="text-[10px] font-bold text-amber-400">3. Boot Dep?</div>
                <div class="text-[11px] text-slate-200 group-hover:text-white">Boot depends on it ➔ Kernel</div>
              </button>
              <button
                type="button"
                onclick="window.exoFilterNodes('internal')"
                class="p-2.5 rounded-xl bg-slate-800/80 hover:bg-slate-700/80 border border-slate-700 text-left transition-all cursor-pointer group"
              >
                <div class="text-[10px] font-bold text-cyan-400">4. Domain Only?</div>
                <div class="text-[11px] text-slate-200 group-hover:text-white">Consumed by one ➔ Internal</div>
              </button>
            </div>
          </div>
        </div>

        <!-- Graph Viewport Controls & Focus Filter -->
        <div class="flex flex-wrap items-center justify-between gap-3 bg-white p-3 rounded-2xl border border-gray-200/80 shadow-2xs">
          <!-- Boundary Focus Filter Pills -->
          <div class="flex items-center gap-1.5 text-xs font-semibold">
            <span class="text-gray-400 text-[11px] mr-1 hidden sm:inline">Focus Boundary:</span>
            <button
              type="button"
              onclick="window.exoFilterNodes('all')"
              id="filter-btn-all"
              class="px-2.5 py-1 rounded-lg bg-slate-900 text-white shadow-2xs transition-all cursor-pointer text-xs"
            >
              All Components
            </button>
            <button
              type="button"
              onclick="window.exoFilterNodes('kernel')"
              id="filter-btn-kernel"
              class="px-2.5 py-1 rounded-lg bg-amber-50 text-amber-700 border border-amber-200 hover:bg-amber-100 transition-all cursor-pointer text-xs flex items-center gap-1"
            >
              <span>⚡</span>
              <span>Kernel Core</span>
            </button>
            <button
              type="button"
              onclick="window.exoFilterNodes('extension')"
              id="filter-btn-extension"
              class="px-2.5 py-1 rounded-lg bg-violet-50 text-violet-700 border border-violet-200 hover:bg-violet-100 transition-all cursor-pointer text-xs flex items-center gap-1"
            >
              <span>🧩</span>
              <span>Extensions</span>
            </button>
            <button
              type="button"
              onclick="window.exoFilterNodes('internal')"
              id="filter-btn-internal"
              class="px-2.5 py-1 rounded-lg bg-cyan-50 text-cyan-700 border border-cyan-200 hover:bg-cyan-100 transition-all cursor-pointer text-xs flex items-center gap-1"
            >
              <span>💾</span>
              <span>Internal / Storage</span>
            </button>
          </div>

          <!-- Zoom & Pan Controls -->
          <div class="flex items-center gap-1.5 bg-gray-100 p-1 rounded-xl border border-gray-200 text-xs font-mono font-bold">
            <button
              type="button"
              onclick="window.exoGraphZoom(-0.15)"
              class="w-7 h-7 flex items-center justify-center rounded-lg bg-white text-gray-700 hover:bg-gray-50 shadow-2xs cursor-pointer"
              title="Zoom Out"
            >
              −
            </button>
            <span id="arch-graph-zoom-label" class="px-2 text-[11px] text-gray-600 font-bold min-w-[48px] text-center">
              100%
            </span>
            <button
              type="button"
              onclick="window.exoGraphZoom(0.15)"
              class="w-7 h-7 flex items-center justify-center rounded-lg bg-white text-gray-700 hover:bg-gray-50 shadow-2xs cursor-pointer"
              title="Zoom In"
            >
              +
            </button>
            <button
              type="button"
              onclick="window.exoGraphResetZoom()"
              class="px-2.5 h-7 flex items-center justify-center rounded-lg bg-white text-gray-700 hover:bg-gray-50 shadow-2xs cursor-pointer text-[10px]"
              title="Reset View"
            >
              Reset
            </button>
          </div>
        </div>

        <!-- SVG Graph Canvas -->
        <div class="border border-gray-200/90 rounded-3xl bg-slate-950 overflow-hidden relative shadow-inner">
          <div id="arch-graph-container" class="overflow-auto max-h-[640px] cursor-grab active:cursor-grabbing p-6">
            <svg
              id="arch-dag-svg"
              width="1220"
              height="490"
              viewBox="0 0 1220 490"
              class="w-full h-auto select-none font-sans"
              style="transform-origin: 0 0; transition: transform 0.15s ease-out;"
            >
              <defs>
                <!-- Arrow Markers -->
                <marker id="marker-arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                  <path d="M 0 1 L 10 5 L 0 9 z" fill="#64748b" />
                </marker>
                <marker id="marker-arrow-amber" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                  <path d="M 0 1 L 10 5 L 0 9 z" fill="#f59e0b" />
                </marker>
                <marker id="marker-arrow-violet" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                  <path d="M 0 1 L 10 5 L 0 9 z" fill="#8b5cf6" />
                </marker>
                <marker id="marker-arrow-emerald" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                  <path d="M 0 1 L 10 5 L 0 9 z" fill="#10b981" />
                </marker>
                <!-- Node Shadow Filter -->
                <filter id="node-drop-shadow" x="-10%" y="-10%" width="120%" height="120%">
                  <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#000000" flood-opacity="0.4" />
                </filter>
              </defs>

              <!-- Layer Column Background Zones -->
              <g class="layer-columns opacity-70">
                <!-- 1. Client / Tooling -->
                <rect x="20" y="20" width="200" height="440" rx="20" fill="#0f172a" stroke="#1e293b" stroke-width="1" />
                <text x="35" y="44" fill="#94a3b8" font-size="11" font-weight="bold" letter-spacing="0.08em">1. CLIENT &amp; TOOLING</text>

                <!-- 2. Gateways & Transport -->
                <rect x="240" y="20" width="200" height="440" rx="20" fill="#0f172a" stroke="#1e293b" stroke-width="1" />
                <text x="255" y="44" fill="#a78bfa" font-size="11" font-weight="bold" letter-spacing="0.08em">2. GATEWAY INGRESS</text>

                <!-- 3. Kernel Boundary (Prominent Golden Frame) -->
                <rect x="465" y="20" width="210" height="440" rx="20" fill="#1e1b18" stroke="#f59e0b" stroke-width="2" stroke-dasharray="6 4" />
                <rect x="475" y="28" width="190" height="20" rx="6" fill="#f59e0b" fill-opacity="0.2" />
                <text x="485" y="42" fill="#fbbf24" font-size="10" font-weight="black" letter-spacing="0.08em">⚡ 3. KERNEL (IMMUTABLE)</text>

                <!-- 4. Extension Runtimes -->
                <rect x="700" y="20" width="210" height="440" rx="20" fill="#0f172a" stroke="#1e293b" stroke-width="1" />
                <text x="715" y="44" fill="#34d399" font-size="11" font-weight="bold" letter-spacing="0.08em">4. EXTENSION RUNTIME</text>

                <!-- 5. Persistence & Storage -->
                <rect x="930" y="20" width="220" height="440" rx="20" fill="#0f172a" stroke="#1e293b" stroke-width="1" />
                <text x="945" y="44" fill="#38bdf8" font-size="11" font-weight="bold" letter-spacing="0.08em">5. STORAGE &amp; ADAPTERS</text>
              </g>

              <!-- Connection Edges (Bezier Curves) -->
              <g class="edges" id="arch-graph-edges">
                <%= for edge <- @edges do %>
                  <path
                    d={edge.path}
                    fill="none"
                    stroke="#64748b"
                    stroke-width="1.8"
                    marker-end="url(#marker-arrow)"
                    class="opacity-60 hover:opacity-100 hover:stroke-violet-400 transition-opacity"
                  />
                <% end %>
              </g>

              <!-- Interactive Topology Nodes -->
              <g class="nodes" id="arch-graph-nodes">
                <%= for node <- @nodes do %>
                  <g
                    id={"node-#{node.id}"}
                    class="cursor-pointer group transition-transform duration-150"
                    data-category={node.category}
                    data-title={node.title}
                    data-subtitle={node.subtitle}
                    data-badge={node.badge}
                    data-desc={node.desc}
                    data-litmus={node.litmus}
                    data-icon={node.icon}
                    onclick="window.exoSelectNode(this)"
                    transform={"translate(#{node.x}, #{node.y})"}
                  >
                    <!-- Node Box -->
                    <rect
                      width="160"
                      height="70"
                      rx="14"
                      fill={case node.category do
                        "kernel" -> "#291e0a"
                        "extension" -> "#1e1b4b"
                        "internal" -> "#082f49"
                        _ -> "#1e293b"
                      end}
                      stroke={case node.category do
                        "kernel" -> "#f59e0b"
                        "extension" -> "#8b5cf6"
                        "internal" -> "#06b6d4"
                        _ -> "#475569"
                      end}
                      stroke-width={if node.category == "kernel", do: "2", else: "1.2"}
                      filter="url(#node-drop-shadow)"
                      class="group-hover:stroke-white transition-colors"
                    />

                    <!-- Icon & Title -->
                    <text x="12" y="24" font-size="14"><%= node.icon %></text>
                    <text
                      x="34"
                      y="23"
                      fill="#ffffff"
                      font-size="11"
                      font-weight="bold"
                      font-family="system-ui, sans-serif"
                    >
                      <%= node.title %>
                    </text>

                    <!-- Subtitle / Port -->
                    <text
                      x="12"
                      y="42"
                      fill={case node.category do
                        "kernel" -> "#fcd34d"
                        "extension" -> "#c4b5fd"
                        "internal" -> "#67e8f9"
                        _ -> "#94a3b8"
                      end}
                      font-size="9"
                      font-weight="bold"
                      font-family="monospace"
                    >
                      <%= node.subtitle %>
                    </text>

                    <!-- Category Pill Badge -->
                    <rect
                      x="12"
                      y="49"
                      width="136"
                      height="14"
                      rx="4"
                      fill={case node.category do
                        "kernel" -> "#f59e0b"
                        "extension" -> "#7c3aed"
                        "internal" -> "#0284c7"
                        _ -> "#334155"
                      end}
                      fill-opacity="0.3"
                    />
                    <text
                      x="18"
                      y="59"
                      fill={case node.category do
                        "kernel" -> "#fef08a"
                        "extension" -> "#e9d5ff"
                        "internal" -> "#bae6fd"
                        _ -> "#cbd5e1"
                      end}
                      font-size="8"
                      font-weight="bold"
                      letter-spacing="0.04em"
                      font-family="monospace"
                    >
                      [<%= node.badge %>]
                    </text>
                  </g>
                <% end %>
              </g>
            </svg>
          </div>
        </div>

        <!-- Node Inspector Detail Card -->
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
                  KERNEL - IMMUTABLE
                </span>
              </div>
              <div id="inspector-subtitle" class="text-xs font-mono font-semibold text-violet-600 mt-0.5">
                Scope &amp; Route Engine
              </div>
              <p id="inspector-desc" class="text-xs text-gray-600 mt-1 max-w-xl">
                Checks caller security scopes (:guest, :player, :admin) &amp; routes actions to service providers.
              </p>
            </div>
          </div>

          <div class="bg-gray-50 p-3.5 rounded-2xl border border-gray-200/80 md:max-w-xs shrink-0">
            <div class="text-[10px] font-bold text-gray-500 uppercase tracking-wider">
              Litmus Test Verdict
            </div>
            <div id="inspector-litmus" class="text-xs font-semibold text-gray-900 mt-1 leading-snug">
              Boot Dependency (Required to route ANY action; cannot be swapped or disabled)
            </div>
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

      <!-- Graph Interactive JavaScript Controller -->
      <script>
        (function() {
          let currentZoom = 1.0;
          const svg = document.getElementById('arch-dag-svg');
          const zoomLabel = document.getElementById('arch-graph-zoom-label');

          window.exoGraphZoom = function(delta) {
            currentZoom = Math.min(2.0, Math.max(0.6, currentZoom + delta));
            if (svg) {
              svg.style.transform = `scale(${currentZoom})`;
            }
            if (zoomLabel) {
              zoomLabel.innerText = `${Math.round(currentZoom * 100)}%`;
            }
          };

          window.exoGraphResetZoom = function() {
            currentZoom = 1.0;
            if (svg) {
              svg.style.transform = 'scale(1.0)';
            }
            if (zoomLabel) {
              zoomLabel.innerText = '100%';
            }
          };

          window.exoFilterNodes = function(category) {
            const nodes = document.querySelectorAll('#arch-graph-nodes > g');
            const edges = document.getElementById('arch-graph-edges');

            nodes.forEach(node => {
              const nodeCat = node.getAttribute('data-category');
              if (category === 'all' || nodeCat === category) {
                node.style.opacity = '1.0';
              } else {
                node.style.opacity = '0.2';
              }
            });

            if (edges) {
              edges.style.opacity = category === 'all' ? '0.6' : '0.2';
            }

            // Update button styles
            ['all', 'kernel', 'extension', 'internal'].forEach(cat => {
              const btn = document.getElementById('filter-btn-' + cat);
              if (btn) {
                if (cat === category) {
                  btn.classList.add('ring-2', 'ring-offset-1', 'ring-violet-500');
                } else {
                  btn.classList.remove('ring-2', 'ring-offset-1', 'ring-violet-500');
                }
              }
            });
          };

          window.exoSelectNode = function(elem) {
            const title = elem.getAttribute('data-title');
            const subtitle = elem.getAttribute('data-subtitle');
            const badge = elem.getAttribute('data-badge');
            const desc = elem.getAttribute('data-desc');
            const litmus = elem.getAttribute('data-litmus');
            const icon = elem.getAttribute('data-icon');

            document.getElementById('inspector-title').innerText = title;
            document.getElementById('inspector-subtitle').innerText = subtitle;
            document.getElementById('inspector-badge').innerText = badge;
            document.getElementById('inspector-desc').innerText = desc;
            document.getElementById('inspector-litmus').innerText = litmus;
            document.getElementById('inspector-icon').innerText = icon;
          };
        })();
      </script>
    </div>
    """
  end
end
