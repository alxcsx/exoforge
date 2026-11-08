defmodule Exoforge.Std.Docs.View do
  @moduledoc """
  Developer Guide, C# Attributes Reference & Live Dynamic API Reference Phoenix Component.
  Supports Markdown rendering, interactive flow navigation, dynamic cluster service catalogs,
  syntax highlighting, and 1-click Print/PDF export.
  """
  use Phoenix.Component

  alias Exoforge.Std.Docs.Markdown

  attr(:action_catalog, :list, default: [])
  attr(:extensions, :list, default: [])
  attr(:project_name, :string, default: "Game")
  attr(:studio_name, :string, default: "Studio")
  attr(:subpage, :string, default: "flow")

  def view(assigns) do
    # Fallback to dynamic catalog if not supplied
    action_catalog =
      if assigns.action_catalog == [] do
        Exoforge.Std.Docs.build_api_catalog()
      else
        assigns.action_catalog
      end

    # Ensure services and actions are strictly deduplicated by name and sanitized
    action_catalog =
      action_catalog
      |> Enum.uniq_by(fn svc -> svc[:name] || svc["name"] end)
      |> Enum.map(fn svc ->
        actions =
          (svc[:actions] || svc["actions"] || [])
          |> Enum.uniq_by(fn act -> act[:name] || act["name"] end)
          |> Enum.map(fn act ->
            %{
              name: to_string(act[:name] || act["name"]),
              mode: to_string(act[:mode] || act["mode"] || "sync"),
              scope: to_string(act[:scope] || act["scope"] || "guest"),
              doc: act[:doc] || act["doc"] || "No description provided.",
              params: act[:params] || act["params"] || [],
              returns: act[:returns] || act["returns"]
            }
          end)

        Map.put(svc, :actions, actions)
      end)

    assigns = assign(assigns, :action_catalog, action_catalog)

    ~H"""
    <div class="space-y-6 max-w-6xl mx-auto pb-16 print:p-0 print:max-w-none print:pb-0">
      <!-- Print & Dark Theme Badges Stylesheet -->
      <style>
        @media print {
          body { background: white !important; color: black !important; font-size: 11pt !important; }
          .print\:hidden { display: none !important; }
          .print\:break-inside-avoid { break-inside: avoid !important; page-break-inside: avoid !important; }
          .print\:shadow-none { box-shadow: none !important; }
          .print\:border-gray-300 { border-color: #d1d5db !important; }
          .print\:p-0 { padding: 0 !important; }
          .print\:bg-white { background-color: white !important; }
          pre, code { white-space: pre-wrap !important; word-break: break-word !important; }
        }

        /* High-contrast badges & code tags in dark theme (especially Architecture & Catalog) */
        html:not(.light) :not(pre) > code {
          background-color: rgba(139, 92, 246, 0.18) !important;
          color: #ddd6fe !important;
          border: 1px solid rgba(139, 92, 246, 0.35) !important;
          font-weight: 600 !important;
        }

        html:not(.light) .prose :not(pre) > code,
        html:not(.light) table code {
          background-color: rgba(139, 92, 246, 0.22) !important;
          color: #e9d5ff !important;
          border: 1px solid rgba(139, 92, 246, 0.4) !important;
          padding: 0.125rem 0.375rem !important;
          border-radius: 0.375rem !important;
          font-weight: 600 !important;
        }

        html:not(.light) .prose strong {
          color: #f3f4f6 !important;
        }

        /* Prevent background/border bleed onto preformatted code blocks */
        pre code,
        .prose pre code,
        html:not(.light) pre code,
        html:not(.light) .prose pre code {
          background: transparent !important;
          background-color: transparent !important;
          border: none !important;
          padding: 0 !important;
          border-radius: 0 !important;
          box-shadow: none !important;
          display: block !important;
          font-weight: 400 !important;
          color: inherit !important;
        }
      </style>

      <!-- Top Guide Navigation Sub-Menu (Hidden on Print) -->
      <div class="print:hidden flex flex-wrap items-center justify-between gap-3 bg-white p-3 rounded-2xl border border-gray-200/90 shadow-2xs">
        <div class="flex items-center gap-2">
          <span class="w-8 h-8 rounded-xl bg-primary-50 text-primary-700 flex items-center justify-center font-bold text-sm">
            📖
          </span>
          <div>
            <span class="font-extrabold text-sm text-gray-900 block leading-tight">Exoforge Developer Guide</span>
            <span class="text-[10px] text-gray-400">Architecture, C# attributes reference &amp; dynamic cluster catalog</span>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <!-- Subpage Pills -->
          <div class="flex flex-wrap items-center gap-1 p-1 bg-gray-100/80 rounded-xl text-xs font-semibold">
            <button
              type="button"
              phx-click="set_guide_subpage"
              phx-value-subpage="flow"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "flow", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>🚀</span>
              <span>Quickstart Flow</span>
            </button>
            <button
              type="button"
              phx-click="set_guide_subpage"
              phx-value-subpage="attributes"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "attributes", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>🧩</span>
              <span>C# Attributes</span>
            </button>
            <button
              type="button"
              phx-click="set_guide_subpage"
              phx-value-subpage="architecture"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "architecture", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>🏗️</span>
              <span>Architecture</span>
            </button>
            <button
              type="button"
              phx-click="set_guide_subpage"
              phx-value-subpage="catalog"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "catalog", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>⚡</span>
              <span>Live API Reference</span>
            </button>
          </div>

          <!-- 1-Click PDF / Print Export Button -->
          <button
            type="button"
            onclick="window.print()"
            title="Export to PDF using native browser print"
            class="px-3.5 py-1.5 rounded-xl bg-gray-900 hover:bg-gray-800 text-white text-xs font-bold transition-all shadow-xs flex items-center gap-1.5 cursor-pointer"
          >
            <svg class="w-3.5 h-3.5 text-gray-300" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 17h2a2 2 0 002-2v-4a2 2 0 00-2-2H5a2 2 0 00-2 2v4a2 2 0 002 2h2m2 4h6a2 2 0 002-2v-4a2 2 0 00-2-2H9a2 2 0 00-2 2v4a2 2 0 002 2zm8-12V5a2 2 0 00-2-2H9a2 2 0 00-2 2v4h10z" />
            </svg>
            <span>Export to PDF</span>
          </button>
        </div>
      </div>

      <!-- SUBPAGE ROUTING -->
      <%= case @subpage do %>
        <% "attributes" -> %>
          <.subpage_attributes />
        <% "architecture" -> %>
          <.subpage_architecture />
        <% "catalog" -> %>
          <.subpage_catalog action_catalog={@action_catalog} />
        <% _ -> %>
          <.subpage_flow
            action_catalog={@action_catalog}
            extensions={@extensions}
            project_name={@project_name}
            studio_name={@studio_name}
          />
      <% end %>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: QUICKSTART FLOW & HERO
  # ===========================================================================
  defp subpage_flow(assigns) do
    ~H"""
    <div class="space-y-8">
      <!-- Hero Banner -->
      <div class="print:border print:border-gray-300 print:text-black relative overflow-hidden bg-gradient-to-br from-gray-900 via-primary-950 to-indigo-950 text-white rounded-3xl p-8 lg:p-10 shadow-xl border border-primary-500/20">
        <div class="absolute -right-12 -bottom-12 w-96 h-96 bg-primary-600/10 rounded-full blur-3xl pointer-events-none"></div>
        <div class="relative z-10 space-y-5 max-w-4xl">
          <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/10 backdrop-blur border border-white/10 text-xs font-bold text-primary-200">
            <span>⚡</span>
            <span>Developer Quickstart &amp; Architecture Reference</span>
          </div>
          <h1 class="text-3xl lg:text-4xl font-extrabold tracking-tight text-white leading-tight">
            From Zero to Live Online Multiplayer Features in 60 Seconds
          </h1>
          <p class="text-base text-gray-300 leading-relaxed">
            Exoforge allows Unity and game developers to write clean, strongly-typed native C# backend extensions that compile locally, hot-reload into an actor concurrency microservices runtime, and sync seamlessly into client code without manual networking boilerplate.
          </p>

          <!-- Quickstart 5-Step Index Grid -->
          <div class="print:hidden pt-2 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2.5">
            <a href="#step-auth" class="group p-3 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/10 hover:border-white/25 transition-all space-y-1 block">
              <div class="flex items-center justify-between">
                <span class="w-6 h-6 rounded-lg bg-primary-500 text-white flex items-center justify-center text-[11px] font-black shadow-xs">1</span>
                <span class="text-[10px] font-semibold text-primary-200 uppercase tracking-wider">Start</span>
              </div>
              <div class="font-bold text-xs text-white group-hover:text-primary-200 transition-colors">Connect &amp; Auth</div>
              <div class="text-[11px] text-gray-300">Anonymous device session</div>
            </a>

            <a href="#step-scaffold" class="group p-3 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/10 hover:border-white/25 transition-all space-y-1 block">
              <div class="flex items-center justify-between">
                <span class="w-6 h-6 rounded-lg bg-primary-500 text-white flex items-center justify-center text-[11px] font-black shadow-xs">2</span>
                <span class="text-[10px] font-semibold text-primary-200 uppercase tracking-wider">C#</span>
              </div>
              <div class="font-bold text-xs text-white group-hover:text-primary-200 transition-colors">Create Extension</div>
              <div class="text-[11px] text-gray-300">Clean service microservice</div>
            </a>

            <a href="#step-deploy" class="group p-3 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/10 hover:border-white/25 transition-all space-y-1 block">
              <div class="flex items-center justify-between">
                <span class="w-6 h-6 rounded-lg bg-primary-500 text-white flex items-center justify-center text-[11px] font-black shadow-xs">3</span>
                <span class="text-[10px] font-semibold text-primary-200 uppercase tracking-wider">Hot</span>
              </div>
              <div class="font-bold text-xs text-white group-hover:text-primary-200 transition-colors">Build &amp; Deploy</div>
              <div class="text-[11px] text-gray-300">Zero-downtime hot reload</div>
            </a>

            <a href="#step-stubs" class="group p-3 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/10 hover:border-white/25 transition-all space-y-1 block">
              <div class="flex items-center justify-between">
                <span class="w-6 h-6 rounded-lg bg-primary-500 text-white flex items-center justify-center text-[11px] font-black shadow-xs">4</span>
                <span class="text-[10px] font-semibold text-primary-200 uppercase tracking-wider">Sync</span>
              </div>
              <div class="font-bold text-xs text-white group-hover:text-primary-200 transition-colors">Sync Client Stubs</div>
              <div class="text-[11px] text-gray-300">Typed Unity client code</div>
            </a>

            <a href="#step-gameplay" class="group p-3 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/10 hover:border-white/25 transition-all space-y-1 block col-span-2 sm:col-span-1">
              <div class="flex items-center justify-between">
                <span class="w-6 h-6 rounded-lg bg-primary-500 text-white flex items-center justify-center text-[11px] font-black shadow-xs">5</span>
                <span class="text-[10px] font-semibold text-primary-200 uppercase tracking-wider">Call</span>
              </div>
              <div class="font-bold text-xs text-white group-hover:text-primary-200 transition-colors">Call from Unity</div>
              <div class="text-[11px] text-gray-300">Callbacks &amp; async/await</div>
            </a>
          </div>
        </div>
      </div>

      <!-- Quick Summary Cards -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-5 print:gap-3">
        <div class="bg-white p-6 rounded-2xl border border-gray-200/90 shadow-sm space-y-2 print:border-gray-300 print:shadow-none print:break-inside-avoid">
          <div class="w-10 h-10 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center text-lg font-bold">
            🔌
          </div>
          <h3 class="font-bold text-gray-900 text-sm">Native C# Headless Services</h3>
          <p class="text-xs text-gray-500 leading-relaxed">
            Extensions execute as isolated native .NET microservices with actor concurrency supervision. Use modern C# records, type-safe APIs, and throw canonical <code class="font-mono text-primary-700 bg-primary-50 px-1 py-0.5 rounded">ExoActionException</code>.
          </p>
        </div>

        <div class="bg-white p-6 rounded-2xl border border-gray-200/90 shadow-sm space-y-2 print:border-gray-300 print:shadow-none print:break-inside-avoid">
          <div class="w-10 h-10 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center text-lg font-bold">
            🔄
          </div>
          <h3 class="font-bold text-gray-900 text-sm">1-Click Hot Deployment</h3>
          <p class="text-xs text-gray-500 leading-relaxed">
            Build and hot-load extensions into the running server from Unity Studio or CLI without stopping player sessions or restarting clusters.
          </p>
        </div>

        <div class="bg-white p-6 rounded-2xl border border-gray-200/90 shadow-sm space-y-2 print:border-gray-300 print:shadow-none print:break-inside-avoid">
          <div class="w-10 h-10 rounded-xl bg-purple-50 text-purple-600 flex items-center justify-center text-lg font-bold">
            🛡️
          </div>
          <h3 class="font-bold text-gray-900 text-sm">Familiar Unity Callbacks</h3>
          <p class="text-xs text-gray-500 leading-relaxed">
            Generated client stubs provide standard Unity main-thread callbacks alongside async/await, with zero networking boilerplate.
          </p>
        </div>
      </div>

      <!-- STEP 1: Connect & Auth -->
      <section id="step-auth" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-2xl bg-primary-600 text-white font-extrabold flex items-center justify-center shrink-0 shadow-md">
            1
          </div>
          <div class="space-y-1">
            <h2 class="text-xl font-bold text-gray-900 tracking-tight">Connect &amp; Authenticate</h2>
            <p class="text-xs text-gray-500">Sign in anonymously using device credentials or authenticate players with seamless token caching.</p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 text-xs text-gray-700">
          <div class="space-y-3">
            <h4 class="font-bold text-gray-900 text-sm flex items-center gap-2">
              <span>🎮</span>
              <span>Anonymous Login &amp; Scene Setup</span>
            </h4>
            <ul class="space-y-2.5 text-gray-600 leading-relaxed">
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span><strong>Add Exoforge Prefab:</strong> In your initial scene, click <strong class="text-gray-900">Exoforge ▸ Add Exoforge to Scene</strong> to instantiate the persistent runtime manager.</span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span><strong>Automatic Device Login:</strong> With <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-semibold">anonymousOnConnect: true</code>, Exoforge signs the player in instantly using their unique hardware hash (<code class="font-mono bg-gray-100 text-gray-800 px-1 py-0.5 rounded">ExoDeviceId.Get()</code>) without passwords.</span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span><strong>Script Login:</strong> Or call <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-semibold">await ExoforgeSDK.Auth.LoginAnonymously()</code> programmatically from any MonoBehaviour.</span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span><strong>Automatic Token Caching:</strong> Player session tokens persist in <code class="font-mono bg-gray-100 text-gray-800 px-1 py-0.5 rounded">ExoTokenStore</code>, and <code class="font-mono bg-gray-100 text-gray-800 px-1 py-0.5 rounded">Exoforge.IsReady</code> activates immediately upon connect.</span>
              </li>
            </ul>
          </div>

          <div class="space-y-2">
            <div class="flex items-center justify-between text-gray-400 font-bold text-xs pb-1">
              <span>Unity Anonymous Sign-In</span>
              <span class="text-emerald-400 font-mono text-[10px]">C# Client</span>
            </div>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_auth())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- STEP 2: Scaffold Extension -->
      <section id="step-scaffold" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-2xl bg-primary-600 text-white font-extrabold flex items-center justify-center shrink-0 shadow-md">
            2
          </div>
          <div class="space-y-1">
            <h2 class="text-xl font-bold text-gray-900 tracking-tight">Create Your Extension</h2>
            <p class="text-xs text-gray-500">Scaffold clean, modern C# backend services in seconds.</p>
          </div>
        </div>

        <div class="space-y-4 text-xs text-gray-700">
          <ul class="space-y-2.5 text-gray-600 leading-relaxed">
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Scaffold Solution:</strong> In Unity Studio, open <strong class="text-gray-900">Extensions</strong> and click <strong class="text-gray-900">⚡ New Extension...</strong> (or run <code class="font-mono bg-gray-100 text-primary-700 px-1.5 py-0.5 rounded font-bold">exo extension new &lt;name&gt;</code>) to create <code class="font-mono bg-gray-100 px-1.5 py-0.5 rounded">Exoforge/extensions/&lt;name&gt;/</code>.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Pure C# Microservice:</strong> Your extension is a standard .NET class library running out-of-process. No bindings or wrappers, just clean C# records and async methods.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Export RPC Actions:</strong> Decorate public methods with <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-bold">[ExoAction]</code>. Execution mode is automatically inferred: <code class="font-mono">Task&lt;T&gt;</code> methods run asynchronously, and concrete returns run synchronously.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Canonical Error Handling:</strong> Throw <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-bold">ExoActionException(code, message)</code> to return structured error codes directly to client callbacks and catch blocks.</span>
            </li>
          </ul>

          <div class="space-y-2">
            <div class="flex items-center justify-between text-gray-400 font-bold text-xs pb-1">
              <span>Exoforge/extensions/gameplay_calculator/src/GameplayCalculatorExtension.cs</span>
              <span class="text-xs text-primary-400 font-mono">C# 12 / .NET 9+</span>
            </div>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_extension())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- STEP 3: Build & Deploy -->
      <section id="step-deploy" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-2xl bg-primary-600 text-white font-extrabold flex items-center justify-center shrink-0 shadow-md">
            3
          </div>
          <div class="space-y-1">
            <h2 class="text-xl font-bold text-gray-900 tracking-tight">Build &amp; Hot-Deploy</h2>
            <p class="text-xs text-gray-500">Fast local compilation and zero-downtime hot reloading.</p>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 text-xs text-gray-600">
          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-3">
            <h4 class="font-bold text-gray-900 text-sm flex items-center gap-2">
              <span>🚀</span>
              <span>1-Click Deploy in Studio</span>
            </h4>
            <ul class="space-y-2 leading-relaxed">
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span>Click <strong class="text-gray-900">🚀 Build &amp; Deploy</strong> directly on the extension card in Exoforge Studio.</span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span>Your local .NET toolchain publishes the single-file binary and uploads it over WebSocket to the cluster.</span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span>Zero server restarts required: existing player sessions remain completely uninterrupted.</span>
              </li>
            </ul>
          </div>

          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-3">
            <h4 class="font-bold text-gray-900 text-sm flex items-center gap-2">
              <span>💻</span>
              <span>CLI Deployment</span>
            </h4>
            <ul class="space-y-2 leading-relaxed">
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span>Build &amp; push from terminal: <code class="font-mono bg-gray-200 px-1 py-0.5 rounded text-gray-900 font-bold">exo extension push &lt;name&gt;</code></span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span>Tail live service logs in real time: <code class="font-mono bg-gray-200 px-1 py-0.5 rounded text-gray-900 font-bold">exo extension logs &lt;name&gt;</code></span>
              </li>
            </ul>
            <pre class="bg-gray-900 text-emerald-400 p-3 rounded-xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto"><code>exo extension push gameplay_calculator&#10;exo extension logs gameplay_calculator</code></pre>
          </div>
        </div>
      </section>

      <!-- STEP 4: Generate Client Stubs -->
      <section id="step-stubs" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-2xl bg-primary-600 text-white font-extrabold flex items-center justify-center shrink-0 shadow-md">
            4
          </div>
          <div class="space-y-1">
            <h2 class="text-xl font-bold text-gray-900 tracking-tight">Generate Client Stubs</h2>
            <p class="text-xs text-gray-500">Automatic emission of strongly-typed C# client bindings.</p>
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <ul class="space-y-2.5 text-gray-600 leading-relaxed">
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>1-Click Client Sync:</strong> Click <strong class="text-gray-900">🔄 Sync Client</strong> in the Unity toolbar (or run <code class="font-mono bg-gray-100 text-primary-700 px-1 py-0.5 rounded font-bold">exo sync</code>) whenever backend contracts change.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Live Contract Reflection:</strong> Queries live extension manifests from the cluster and emits <code class="font-mono bg-gray-100 text-gray-800 px-1 py-0.5 rounded">Assets/Exoforge/Generated/ExoforgeServices.g.cs</code>.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Dual API Generated:</strong> Automatically generates strongly-typed request/response records, Unity main-thread callback methods, and <code class="font-mono text-primary-700 font-bold">Task&lt;T&gt;</code> async overloads.</span>
            </li>
          </ul>
        </div>
      </section>

      <!-- STEP 5: Call from Unity Gameplay Code -->
      <section id="step-gameplay" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-2xl bg-primary-600 text-white font-extrabold flex items-center justify-center shrink-0 shadow-md">
            5
          </div>
          <div class="space-y-1">
            <h2 class="text-xl font-bold text-gray-900 tracking-tight">Call from Unity Gameplay Code</h2>
            <p class="text-xs text-gray-500">Standard main-thread callbacks without mandatory async/await or boilerplate.</p>
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <ul class="space-y-2.5 text-gray-600 leading-relaxed">
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Fluent Service Access:</strong> Call your backend service via generated client extensions: <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-bold">ExoforgeSDK.Client.&lt;ServiceName&gt;()</code>.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Main-Thread Callbacks (Style A):</strong> Use <code class="font-mono">onComplete</code> and <code class="font-mono">onError</code> handlers dispatched safely to the Unity main thread—no async/await or UniTask required.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Task Async/Await (Style B):</strong> Await <code class="font-mono text-primary-700 font-bold">&lt;ActionName&gt;Async(...)</code> in asynchronous methods or Coroutines, catching <code class="font-mono">ExoActionException</code> directly.</span>
            </li>
          </ul>

          <div class="space-y-2 pt-1">
            <div class="flex items-center justify-between text-gray-400 font-bold text-xs pb-1">
              <span>Assets/Scripts/GameplayRewardController.cs</span>
              <span class="text-xs text-emerald-400 font-mono">Unity C#</span>
            </div>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_unity())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- CTA: Jump to Dedicated Live API Reference -->
      <div class="p-6 rounded-3xl bg-gradient-to-r from-purple-950/40 via-indigo-950/30 to-purple-950/40 border border-purple-500/30 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 print:hidden">
        <div class="space-y-1">
          <div class="flex items-center gap-2 text-purple-300 font-bold text-xs uppercase tracking-wider">
            <span>⚡</span>
            <span>Live Action Catalog</span>
          </div>
          <h3 class="text-base font-extrabold text-white">Explore All Registered Services &amp; Actions</h3>
          <p class="text-xs text-gray-300 leading-relaxed max-w-xl">
            Inspect live cluster contracts, action signatures, parameters, authorization scopes, and copy-pasteable Unity SDK calling code in the dedicated API Reference.
          </p>
        </div>
        <button
          type="button"
          phx-click="set_guide_subpage"
          phx-value-subpage="catalog"
          class="shrink-0 px-4 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white text-xs font-bold transition-all shadow-md flex items-center gap-2 cursor-pointer"
        >
          <span>⚡ View Live API Reference</span>
          <span>➔</span>
        </button>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: C# ATTRIBUTES REFERENCE
  # ===========================================================================
  defp subpage_attributes(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-3 print:border-gray-300 print:shadow-none">
        <div class="flex items-center gap-3">
          <span class="w-10 h-10 rounded-2xl bg-primary-50 text-primary-700 flex items-center justify-center font-bold text-xl">
            🧩
          </span>
          <div>
            <h1 class="text-2xl font-extrabold text-gray-900 tracking-tight">C# Attributes Reference</h1>
            <p class="text-xs text-gray-500 mt-0.5">
              Comprehensive reference for all core attributes provided by the Exoforge Extension SDK.
            </p>
          </div>
        </div>

        <div class="print:hidden pt-2 flex flex-wrap gap-2 text-xs font-semibold">
          <a href="#attr-extension" class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors flex items-center gap-1.5">
            <span>[ExoExtension]</span>
          </a>
          <a href="#attr-action" class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors flex items-center gap-1.5">
            <span>[ExoAction]</span>
          </a>
          <a href="#attr-cron" class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors flex items-center gap-1.5">
            <span>[ExoCron]</span>
          </a>
          <a href="#attr-event" class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors flex items-center gap-1.5">
            <span>[ExoEvent]</span>
          </a>
          <a href="#attr-resource" class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors flex items-center gap-1.5">
            <span>[ExoResource]</span>
          </a>
        </div>
      </div>

      <!-- [ExoExtension] -->
      <section id="attr-extension" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-indigo-50 text-indigo-700 flex items-center justify-center font-bold text-lg">
              🧩
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoExtension] / [ExoService]</h2>
                <span class="px-2 py-0.5 rounded-full bg-indigo-100 text-indigo-800 text-[10px] font-bold uppercase tracking-wider">Service Root</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Identifies a C# class or interface as a cluster-supervised native headless service.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-indigo-700">Exoforge.Plugin.SDK</strong> (via <code class="text-gray-800">exoforge_std_extension_manager</code>)
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            The <code class="font-mono text-indigo-700 font-bold">[ExoExtension]</code> attribute is the root entry point for backend features in Exoforge. Classes marked with this attribute are automatically registered into the server extension supervisor, inspected for exported RPC actions, and linked into client code generators.
          </p>

          <div class="overflow-x-auto rounded-xl border border-gray-200 mt-3">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Property</th>
                  <th class="py-2 px-3">Type</th>
                  <th class="py-2 px-3">Required / Default</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">name (positional)</td>
                  <td class="py-2 px-3 text-primary-700">string</td>
                  <td class="py-2 px-3 text-rose-600 font-sans text-xs font-semibold">Required</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Unique identifier of the service / extension (e.g. <code class="font-mono text-primary-700">"inventory_service"</code>). Used for RPC routing, CLI targeting, and log grouping.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Title</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Human-readable title displayed in the Studio Dashboard, cards, and API documentation.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Icon</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional ("⚙️")</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Icon or emoji displayed on extension cards and navigation tabs in Studio (e.g. <code class="font-mono text-primary-700">"🎒"</code>, <code class="font-mono text-primary-700">"🎮"</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Category</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional ("Extension")</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Classification category in Studio (e.g. <code class="font-mono text-primary-700">"Game"</code>, <code class="font-mono text-primary-700">"Economy"</code>, <code class="font-mono text-primary-700">"Social"</code>, <code class="font-mono text-primary-700">"Operations"</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Version</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional ("0.1.0")</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Semantic version string. Checked during client synchronization and hot-reload.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Resources</td>
                  <td class="py-2 px-3 text-primary-700">Type[]?</td>
                  <td class="py-2 px-3 text-gray-400">Optional ([])</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Array of C# record types managed by this extension. Auto-creates database schemas and exposes entries in the Studio dashboard.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">System</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (false)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Marks this as an essential system-level extension. Grouped into the System registry table in Studio.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">DashboardElement</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Custom HTML web-component / microfrontend tag name for the Studio dashboard view.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">DashboardEntry</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">JavaScript entry bundle path for custom Studio microfrontend views.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>Extension Class Declaration Pattern</span>
            <span class="font-mono text-[11px] text-gray-400">C# 12 / .NET 9+</span>
          </div>
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_extension_page())) %></code></pre>
        </div>
      </section>

      <!-- [ExoAction] -->
      <section id="attr-action" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-amber-50 text-amber-700 flex items-center justify-center font-bold text-lg">
              ⚡
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoAction]</h2>
                <span class="px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 text-[10px] font-bold uppercase tracking-wider">RPC Action</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Exposes public class methods as callable RPC endpoints over WebSocket and HTTP.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-amber-700">Kernel ActionDispatcher</strong> (transports: <code class="text-gray-800">exoforge_std_ws</code>, <code class="text-gray-800">exoforge_std_http</code>)
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            Decorate any public method with <code class="font-mono text-amber-700 font-bold">[ExoAction]</code> to make it callable from Unity clients, Web UI, and CLI. Method arguments are automatically deserialized from incoming payloads, and return values are serialized back to the caller.
          </p>

          <div class="p-5 rounded-2xl bg-amber-500/10 border border-amber-500/30 text-amber-950 dark:text-amber-200 space-y-3">
            <div class="font-bold text-xs flex items-center gap-1.5 text-amber-900 dark:text-amber-300 uppercase tracking-wider">
              <span>💡</span> <span>What <code>Mode</code> Implies in C# Extensions</span>
            </div>
            <div class="p-3 rounded-xl bg-amber-500/15 border border-amber-500/30 text-amber-950 dark:text-amber-200 text-[11px] leading-relaxed">
              <strong>Client vs Server Execution:</strong> When called from game clients (Unity over WebSocket or HTTP), <strong>every action works asynchronously</strong> across the network transport (<code class="font-mono">await client.MyActionAsync(...)</code> or callbacks).
              The <code class="font-mono font-bold">Mode</code> attribute exclusively matters for <strong>cluster-side execution</strong> and <strong>extension-to-extension / in-cluster IPC</strong> semantics (<code class="font-mono">ActionDispatcher.dispatch</code>).
            </div>

            <p class="text-[11px] leading-relaxed text-gray-700 dark:text-gray-300">
              <code class="font-mono bg-amber-500/20 px-1 py-0.5 rounded font-bold">ActionMode.Auto</code> is the default and recommended setting: <code class="font-mono">Task&lt;T&gt;</code> returns become async, concrete returns become sync, and fire-and-forget uses <code class="font-mono">Cast</code>.
            </p>

            <details class="group cursor-pointer rounded-xl bg-white/60 dark:bg-gray-900/60 border border-amber-500/20 p-3">
              <summary class="font-bold text-amber-900 dark:text-amber-300 select-none text-[11px] hover:text-amber-700">
                ▸ View Detailed Server-Side Execution Semantics (Sync vs Async vs Cast)
              </summary>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-3 text-[11px] leading-relaxed mt-3">
                <div class="p-3 rounded-xl bg-white/80 dark:bg-gray-800/80 border border-amber-500/20 space-y-1">
                  <div class="font-bold text-amber-800 dark:text-amber-300 flex items-center gap-1">
                    <span>⚡</span> <span>Sync / Auto (Concrete)</span>
                  </div>
                  <p class="text-gray-700 dark:text-gray-300">
                    <strong>What it implies:</strong> Executes directly on the extension dispatch thread and responds immediately with the return payload. In extension-to-extension IPC, the caller awaits the reply in-band.
                  </p>
                  <p class="text-gray-500 dark:text-gray-400">
                    <strong>Best for:</strong> Pure in-memory math, validations, instant calculations (&lt; 1ms).
                  </p>
                </div>

                <div class="p-3 rounded-xl bg-white/80 dark:bg-gray-800/80 border border-amber-500/20 space-y-1">
                  <div class="font-bold text-amber-800 dark:text-amber-300 flex items-center gap-1">
                    <span>🔄</span> <span>Async / Auto (Task)</span>
                  </div>
                  <p class="text-gray-700 dark:text-gray-300">
                    <strong>What it implies:</strong> Method returns <code class="font-mono">Task</code> or <code class="font-mono">Task&lt;T&gt;</code>. Awaits I/O without blocking the extension worker thread, then replies with <code class="font-mono">action_result</code> once resolved.
                  </p>
                  <p class="text-gray-500 dark:text-gray-400">
                    <strong>Best for:</strong> Database queries, external webhooks, multi-step asynchronous logic.
                  </p>
                </div>

                <div class="p-3 rounded-xl bg-white/80 dark:bg-gray-800/80 border border-amber-500/20 space-y-1">
                  <div class="font-bold text-amber-800 dark:text-amber-300 flex items-center gap-1">
                    <span>🚀</span> <span>Cast (Fire-and-Forget)</span>
                  </div>
                  <p class="text-gray-700 dark:text-gray-300">
                    <strong>What it implies:</strong> One-way dispatch. The cluster delivers the message to the extension and returns immediately without awaiting completion or returning any reply frame.
                  </p>
                  <p class="text-gray-500 dark:text-gray-400">
                    <strong>Best for:</strong> Telemetry, analytics, player movement pings, audit logging.
                  </p>
                </div>
              </div>
            </details>
          </div>

          <div class="overflow-x-auto rounded-xl border border-gray-200 mt-3">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Property</th>
                  <th class="py-2 px-3">Type</th>
                  <th class="py-2 px-3">Required / Default</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">name (positional)</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (method name)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Wire action name. When omitted, automatically converted from PascalCase to <code class="font-mono text-primary-700">snake_case</code> (e.g. <code class="font-mono text-primary-700">TransferItem</code> → <code class="font-mono text-primary-700">transfer_item</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Mode</td>
                  <td class="py-2 px-3 text-primary-700">ActionMode</td>
                  <td class="py-2 px-3 text-gray-400">Optional (ActionMode.Auto)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Execution mode (<code class="font-mono text-primary-700">Auto</code>, <code class="font-mono text-primary-700">Sync</code>, <code class="font-mono text-primary-700">Async</code>, <code class="font-mono text-primary-700">Cast</code>). <code class="font-mono">Auto</code> infers from return type: <code class="font-mono">Task&lt;T&gt;</code> becomes async, concrete returns become sync. <code class="font-mono">Cast</code> enables fire-and-forget.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Scope</td>
                  <td class="py-2 px-3 text-primary-700">string</td>
                  <td class="py-2 px-3 text-gray-400">Optional ("global")</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Minimum authorization scope needed to invoke (<code class="font-mono text-primary-700">"guest"</code>, <code class="font-mono text-primary-700">"player"</code>, <code class="font-mono text-primary-700">"admin"</code>, <code class="font-mono text-primary-700">"studio"</code>). The cluster enforces this before invoking the extension.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Transport</td>
                  <td class="py-2 px-3 text-primary-700">ActionTransport</td>
                  <td class="py-2 px-3 text-gray-400">Optional (ActionTransport.Auto)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Preferred transport mechanism (<code class="font-mono text-primary-700">Auto</code>, <code class="font-mono text-primary-700">WebSocket</code>, <code class="font-mono text-primary-700">Http</code>, <code class="font-mono text-primary-700">Webhook</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Service</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">The owning service name when a single extension class provides multiple <code class="font-mono text-primary-700">[ExoService]</code> contracts. Defaults to the primary service.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>Server Action Implementation</span>
            <span class="font-mono text-[11px] text-gray-400">C# Backend</span>
          </div>
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_action_page())) %></code></pre>
        </div>
      </section>

      <!-- [ExoCron] -->
      <section id="attr-cron" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-amber-50 text-amber-700 flex items-center justify-center font-bold text-lg">
              ⏱️
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoCron]</h2>
                <span class="px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 text-[10px] font-bold uppercase tracking-wider">Recurring Task</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Executes scheduled recurring background jobs via the cluster supervisor and scheduler.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-amber-700">Cron Extension</strong> (<code class="text-gray-800">exoforge_std_cron</code>)
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            Decorate parameterless methods with <code class="font-mono text-amber-700 font-bold">[ExoCron]</code> to schedule automated background executions under cluster supervision.
          </p>

          <div class="overflow-x-auto rounded-xl border border-gray-200 mt-3">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Property</th>
                  <th class="py-2 px-3">Type</th>
                  <th class="py-2 px-3">Required / Default</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">schedule (positional 0)</td>
                  <td class="py-2 px-3 text-primary-700">string</td>
                  <td class="py-2 px-3 text-rose-600 font-sans text-xs font-semibold">Required</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Standard 5-field cron expression in UTC (<code class="font-mono text-primary-700">"minute hour day-of-month month day-of-week"</code>). Examples: <code class="font-mono text-primary-700">"0 0 * * *"</code> (midnight daily), <code class="font-mono text-primary-700">"*/5 * * * *"</code> (every 5 min).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">name (positional 1 / named)</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (method name)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Unique task name on the wire. Defaults to method name in <code class="font-mono text-primary-700">snake_case</code>.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Description</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Human-readable description surfaced in Studio telemetry and operations cards.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">RunOnStartup</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (false)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Whether the task executes immediately when the extension starts before the first cron trigger. Useful for seeding or cache pre-warming.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Service</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">The service this cron job belongs to when multiple services are declared. Defaults to primary service.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="space-y-2">
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_cron_page())) %></code></pre>
        </div>
      </section>

      <!-- [ExoEvent] -->
      <section id="attr-event" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-purple-50 text-purple-700 flex items-center justify-center font-bold text-lg">
              📡
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoEvent]</h2>
                <span class="px-2 py-0.5 rounded-full bg-purple-100 text-purple-800 text-[10px] font-bold uppercase tracking-wider">Cluster Pub/Sub</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Declares a record or class as a cluster pub/sub event schema contract.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-purple-700">Kernel EventDispatcher</strong> (broadcast via <code class="text-gray-800">:pg</code>, pushed via <code class="text-gray-800">exoforge_std_ws</code>)
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <div class="p-4 rounded-2xl bg-purple-500/10 border border-purple-500/30 text-purple-950 dark:text-purple-200 space-y-1.5">
            <div class="font-bold text-xs flex items-center gap-1.5">
              <span>⚠️</span> <span>Schema Contract Annotation, Not Function Listener</span>
            </div>
            <p class="text-[11px] leading-relaxed">
              <code class="font-mono text-purple-800 dark:text-purple-300 font-bold">[ExoEvent]</code> annotates <strong>records, classes, or structs</strong> to declare the schema and wire contract of an event payload.
              To <strong>listen</strong> to events inside a C# extension, implement <code class="font-mono bg-purple-500/20 px-1 py-0.5 rounded">public void OnEvent(string name, TPayload payload)</code> on your extension class.
              To <strong>subscribe</strong> in Unity, call <code class="font-mono bg-purple-500/20 px-1 py-0.5 rounded">ExoforgeSDK.Events.Subscribe&lt;T&gt;()</code>.
            </p>
          </div>

          <div class="overflow-x-auto rounded-xl border border-gray-200 mt-3">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Property</th>
                  <th class="py-2 px-3">Type</th>
                  <th class="py-2 px-3">Required / Default</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">name (positional 0)</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (record name)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Event name on the wire and bus (e.g. <code class="font-mono text-primary-700">"player.registered"</code>). When omitted, derived from the record name in <code class="font-mono text-primary-700">snake_case</code>.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Topic</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Pub/sub broadcast topic pattern (e.g. <code class="font-mono text-primary-700">"player:*"</code> or <code class="font-mono text-primary-700">"leaderboard.weekly"</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Scope</td>
                  <td class="py-2 px-3 text-primary-700">string</td>
                  <td class="py-2 px-3 text-gray-400">Optional ("global")</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Minimum authorization scope required to receive or publish this event.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">PayloadType</td>
                  <td class="py-2 px-3 text-primary-700">Type?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Explicit payload type override when declared on a service class rather than directly on the record.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Service</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">The service this event belongs to when multiple services are provided.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <div class="text-xs text-gray-500 font-bold mb-1">C# Backend Schema &amp; Handler</div>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_event_page())) %></code></pre>
          </div>
          <div>
            <div class="text-xs text-gray-500 font-bold mb-1">Unity C# Client Subscription</div>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_event_unity())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- [ExoResource] -->
      <section id="attr-resource" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-emerald-50 text-emerald-700 flex items-center justify-center font-bold text-lg">
              🗄️
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoResource] &amp; [ExoColumn]</h2>
                <span class="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 text-[10px] font-bold uppercase tracking-wider">Database Entity</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Declares typed entity records and columns mapped directly to SQLite / PostgreSQL storage.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-emerald-700">Database &amp; Resources</strong> (<code class="text-gray-800">exoforge_std_database</code>, <code class="text-gray-800">exoforge_std_resources</code>)
          </div>
        </div>

        <div class="space-y-4 text-xs text-gray-700 leading-relaxed">
          <div class="p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-950 dark:text-emerald-200 space-y-1">
            <div class="font-bold flex items-center gap-1.5 text-emerald-800 dark:text-emerald-300 text-[11px] uppercase tracking-wider">
              <span>✨</span> <span>Automatic Table Inference &amp; Studio Forms</span>
            </div>
            <p class="leading-relaxed">
              Resource records map directly to database tables without manual migration files. Attributes configure table names, primary keys, Studio dashboard tabs, sorting, filtering, and custom input widgets.
            </p>
          </div>

          <h3 class="text-sm font-bold text-gray-900 pt-2">[ExoResource] Parameters</h3>
          <div class="overflow-x-auto rounded-xl border border-gray-200">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Property</th>
                  <th class="py-2 px-3">Type</th>
                  <th class="py-2 px-3">Required / Default</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">name (positional / named)</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (record name)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Database table name. When omitted, defaults to the record name in <code class="font-mono text-primary-700">snake_case</code>.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">PrimaryKey</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional ("id")</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Name of the primary key column. Can also be designated on a column using <code class="font-mono text-primary-700">[ExoColumn(PrimaryKey = true)]</code> or automatically inferred from property name <code class="font-mono text-primary-700">Id</code>.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Source</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (same as Name)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">The table or view this resource is stored in. Real database table queryable via SQL.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Singleton</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (false)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Indicates whether this resource stores exactly one record (e.g. server configuration). Creates a default record when empty and renders as a single form in Studio.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">DrawerTabs</td>
                  <td class="py-2 px-3 text-primary-700">string[]?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (["overview"])</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Tab sections displayed when inspecting a row in the Studio drawer (e.g. <code class="font-mono text-primary-700">new[] &#123; "overview", "attributes" &#125;</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">ResourceType</td>
                  <td class="py-2 px-3 text-primary-700">Type?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Explicit record type when declared on a service class via <code class="font-mono text-primary-700">[ExoService(Resources = ...)]</code>.</td>
                </tr>
              </tbody>
            </table>
          </div>

          <h3 class="text-sm font-bold text-gray-900 pt-2">[ExoColumn] Parameters</h3>
          <div class="overflow-x-auto rounded-xl border border-gray-200">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Property</th>
                  <th class="py-2 px-3">Type</th>
                  <th class="py-2 px-3">Required / Default</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">name (positional / named)</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (property name)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Column name in the database table in <code class="font-mono text-primary-700">snake_case</code>.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Label</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (property name)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">User-friendly header label rendered in Studio Dashboard data tables and drawer forms.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">DataType</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (auto-inferred)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Explicit SQL data type override (<code class="font-mono text-primary-700">"text"</code>, <code class="font-mono text-primary-700">"integer"</code>, <code class="font-mono text-primary-700">"float"</code>, <code class="font-mono text-primary-700">"boolean"</code>, <code class="font-mono text-primary-700">"datetime"</code>, <code class="font-mono text-primary-700">"json"</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Role</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Semantic role for special Studio UI presentation from <code class="font-mono text-primary-700">ExoRole</code> (<code class="font-mono">ExoRole.PlayerId</code>, <code class="font-mono">ExoRole.FileReference</code>, <code class="font-mono">ExoRole.Currency</code>, <code class="font-mono">ExoRole.Status</code>, <code class="font-mono">ExoRole.Timestamp</code>, <code class="font-mono">ExoRole.Title</code>, <code class="font-mono">ExoRole.Description</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">InputType</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional ("text")</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Form input widget from <code class="font-mono text-primary-700">ExoInput</code> (<code class="font-mono">Text</code>, <code class="font-mono">Color</code>, <code class="font-mono">Date</code>, <code class="font-mono">Time</code>, <code class="font-mono">DateTimeLocal</code>, <code class="font-mono">Textarea</code>, <code class="font-mono">Email</code>, <code class="font-mono">Url</code>, <code class="font-mono">Password</code>, <code class="font-mono">Range</code>, <code class="font-mono">Json</code>, <code class="font-mono">List</code>, <code class="font-mono">Checkbox</code>, <code class="font-mono">Select</code>, <code class="font-mono">FileReference</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Sortable</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (true)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Enables column click-sorting in Studio data tables.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Filterable</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (true)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Enables quick search &amp; filtering on this column in Studio.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Badge</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (false)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Renders the column value as a distinct colored badge chip in Studio.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Bucket</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Target storage bucket name when referencing binary/blob assets from <code class="font-mono text-primary-700">file_bucket</code>.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">FileReference</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (false)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Convenience shorthand for <code class="font-mono text-primary-700">Role = ExoRole.FileReference</code>.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">PrimaryKey</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (false)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Explicitly marks this column as the primary key for the table.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">ForeignKey</td>
                  <td class="py-2 px-3 text-primary-700">bool</td>
                  <td class="py-2 px-3 text-gray-400">Optional (false)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Marks this column as a foreign key referencing another resource or table. Inferred automatically when <code class="font-mono text-primary-700">ReferencesType</code> is provided.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">ReferencesType</td>
                  <td class="py-2 px-3 text-primary-700">Type?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Entity record or class referenced by this column. Automatically infers <code class="font-mono text-primary-700">ForeignKey = true</code> and target table/key <code class="font-mono text-primary-700">References</code> (e.g. <code class="font-mono text-primary-700">ReferencesType = typeof(PlayerDataRecord)</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">References</td>
                  <td class="py-2 px-3 text-primary-700">string?</td>
                  <td class="py-2 px-3 text-gray-400">Optional (null)</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Target referenced table and column (e.g. <code class="font-mono text-primary-700">"player_data.id"</code>). Inferred automatically from <code class="font-mono text-primary-700">ReferencesType</code> when provided.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="space-y-2">
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_resource_page())) %></code></pre>
        </div>
      </section>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: ARCHITECTURE
  # ===========================================================================
  defp subpage_architecture(assigns) do
    ~H"""
    <div class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none">
      <Exoforge.Std.Docs.ArchitectureGraph.visualizer />
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: DYNAMIC API REFERENCE & CATALOG
  # ===========================================================================
  defp subpage_catalog(assigns) do
    ~H"""
    <section id="catalog" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
      <div class="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <div class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200 text-[10px] font-bold">
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></span>
            <span>Live Cluster Contracts</span>
          </div>
          <h2 class="text-xl font-bold text-gray-900 tracking-tight mt-1">
            Live Services &amp; Action Catalog
          </h2>
          <p class="text-xs text-gray-500">
            Dynamically extracted from currently loaded extensions on this cluster. Foldable by extension and action.
          </p>
        </div>
        <span class="text-xs font-bold text-gray-500 bg-gray-100 px-3 py-1.5 rounded-xl self-start md:self-auto font-mono">
          <%= length(@action_catalog) %> Services Loaded
        </span>
      </div>

      <%= if @action_catalog == [] do %>
        <div class="text-center py-12 text-gray-400 bg-gray-50 rounded-2xl border border-dashed border-gray-200">
          No callable services currently registered. Scaffold and deploy an extension to see it live!
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for svc <- @action_catalog do %>
            <details class="group bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden transition-all duration-200 print:border-gray-300 print:shadow-none print:break-inside-avoid">
              <summary class="flex items-center justify-between gap-3 p-5 cursor-pointer select-none bg-white hover:bg-gray-50 transition-colors list-none">
                <div class="flex items-center gap-3">
                  <span class="w-9 h-9 rounded-xl bg-primary-50 text-primary-700 flex items-center justify-center font-bold text-base shadow-xs">
                    <%= svc[:icon] || "⚙️" %>
                  </span>
                  <div>
                    <h3 class="font-extrabold text-gray-900 text-sm tracking-tight font-mono">
                      <%= svc[:name] %>
                    </h3>
                    <%= if svc[:title] do %>
                      <p class="text-[11px] text-gray-500"><%= svc[:title] %></p>
                    <% end %>
                  </div>
                </div>

                <div class="flex items-center gap-3">
                  <span class="text-[11px] font-bold px-2.5 py-1 rounded-full bg-gray-100 text-gray-600 font-mono">
                    <%= length(svc[:actions] || []) %> <%= if length(svc[:actions] || []) == 1, do: "action", else: "actions" %>
                  </span>
                  <svg class="print:hidden w-5 h-5 text-gray-400 group-open:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </div>
              </summary>

              <div class="p-5 pt-3 border-t border-gray-100 space-y-3 bg-gray-50/50 print:bg-white">
                <%= for act <- (svc[:actions] || []) do %>
                  <details class="group/act bg-white rounded-xl border border-gray-200/80 p-4 space-y-3 shadow-2xs transition-all print:border-gray-300 print:break-inside-avoid">
                    <summary class="flex items-center justify-between gap-2 cursor-pointer select-none list-none">
                      <div class="flex items-center gap-2">
                        <span class="font-bold text-primary-800 text-xs font-mono">
                          <%= format_action_signature(act) %>
                        </span>
                        <span class="text-[9px] font-bold px-1.5 py-0.5 rounded bg-gray-100 text-gray-600 uppercase font-mono">
                          <%= act.mode %>
                        </span>
                        <%= if act.scope && act.scope != "guest" do %>
                          <span class="text-[9px] font-bold px-1.5 py-0.5 rounded bg-amber-50 text-amber-700 border border-amber-200 uppercase font-mono">
                            <%= act.scope %>
                          </span>
                        <% end %>
                      </div>

                      <div class="flex items-center gap-2">
                        <span class="text-[11px] text-gray-400 font-mono hidden sm:inline">
                          <%= length(act.params || []) %> params
                        </span>
                        <svg class="print:hidden w-4 h-4 text-gray-400 group-open/act:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                        </svg>
                      </div>
                    </summary>

                    <div class="pt-2 border-t border-gray-100 space-y-3">
                      <p class="text-xs text-gray-600 leading-relaxed"><%= act.doc %></p>

                      <%= if is_list(act.params) and act.params != [] do %>
                        <div class="space-y-1.5">
                          <div class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Parameters</div>
                          <div class="overflow-x-auto rounded-lg border border-gray-200">
                            <table class="w-full text-left text-xs bg-white">
                              <thead>
                                <tr class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                                  <th class="py-1.5 px-3">Name</th>
                                  <th class="py-1.5 px-3">Type</th>
                                  <th class="py-1.5 px-3">Status</th>
                                  <th class="py-1.5 px-3">Description</th>
                                </tr>
                              </thead>
                              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                                <%= for p <- act.params do %>
                                  <tr>
                                    <td class="py-1.5 px-3 font-bold text-gray-900"><%= p.name %></td>
                                    <td class="py-1.5 px-3 text-primary-700"><%= p.type %></td>
                                    <td class="py-1.5 px-3">
                                      <%= if Map.get(p, :optional, false) do %>
                                        <span class="text-gray-400 text-[10px]">Optional</span>
                                      <% else %>
                                        <span class="text-rose-600 font-bold text-[10px]">Required</span>
                                      <% end %>
                                    </td>
                                    <td class="py-1.5 px-3 font-sans text-xs text-gray-600">
                                      <%= Map.get(p, :doc) || "—" %>
                                    </td>
                                  </tr>
                                <% end %>
                              </tbody>
                            </table>
                          </div>
                        </div>
                      <% end %>

                      <div class="space-y-2 pt-1 print:break-inside-avoid">
                        <div class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Unity Calling Styles</div>
                        
                        <div class="space-y-1">
                          <div class="text-[10px] text-gray-500 font-semibold">Unity Callback (Non-Async / Main Thread):</div>
                          <pre class="bg-gray-950 text-gray-200 p-3 rounded-xl font-mono text-[10px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_callback(svc[:name], act))) %></code></pre>
                        </div>

                        <div class="space-y-1">
                          <div class="text-[10px] text-gray-500 font-semibold">Task Async/Await:</div>
                          <pre class="bg-gray-950 text-gray-200 p-3 rounded-xl font-mono text-[10px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_async(svc[:name], act))) %></code></pre>
                        </div>
                      </div>
                    </div>
                  </details>
                <% end %>
              </div>
            </details>
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  defp format_action_signature(act) do
    name = act[:name] || act.name
    params = act[:params] || act.params || []

    sorted_params =
      Enum.sort_by(params, fn p ->
        optional? = p[:optional] || p["optional"] || false
        if optional?, do: 1, else: 0
      end)

    params_str =
      sorted_params
      |> Enum.map(fn p ->
        p_name = p[:name] || p["name"] || ""
        optional? = p[:optional] || p["optional"] || false

        if optional? do
          "#{p_name}?"
        else
          "#{p_name}"
        end
      end)
      |> Enum.join(", ")

    ".#{name}(#{params_str})"
  end

  # ===========================================================================
  # C# SNIPPET GENERATORS
  # ===========================================================================

  defp snippet_callback(svc_name, act) do
    service_pascal = Macro.camelize(to_string(svc_name))
    action_pascal = Macro.camelize(to_string(act.name))
    params = act.params || []

    args =
      if params == [] do
        ""
      else
        req_name = "#{action_pascal}Request"
        "new #{req_name}(/* parameters */), "
      end

    """
    ExoforgeSDK.Client.#{service_pascal}().#{action_pascal}(
        #{args}onComplete: result => Debug.Log($"Success: {result}"),
        onError: err => Debug.LogError($"Error: {err.Message}")
    );
    """
    |> String.trim()
  end

  defp snippet_async(svc_name, act) do
    service_pascal = Macro.camelize(to_string(svc_name))
    action_pascal = Macro.camelize(to_string(act.name))
    params = act.params || []

    args =
      if params == [] do
        ""
      else
        req_name = "#{action_pascal}Request"
        "new #{req_name}(/* parameters */)"
      end

    """
    var result = await ExoforgeSDK.Client.#{service_pascal}().#{action_pascal}Async(#{args});
    Debug.Log($"Success: {result}");
    """
    |> String.trim()
  end

  defp code_auth do
    """
    using UnityEngine;
    using Exoforge.SDK;

    public class GameInitializer : MonoBehaviour
    {
        async void Start()
        {
            var session = await ExoforgeSDK.Auth.LoginAnonymously();
            Debug.Log($"Player session ready: {session.PlayerId}");

            if (!session.HasDisplayName)
            {
                await ExoforgeSDK.Auth.SetDisplayName("Viper");
            }
        }
    }
    """
  end

  defp code_extension do
    """
    using System.Threading.Tasks;
    using Exoforge.SDK;

    [ExoExtension("gameplay_calculator", Version = "1.0.0")]
    public class GameplayCalculatorExtension
    {
        [ExoAction]
        public CalculateScoreResponse CalculateScore(CalculateScoreRequest req)
        {
            if (req.Multiplier <= 0)
                throw new ExoActionException("invalid_multiplier", "Multiplier must be positive.");

            int finalScore = (req.BasePoints * req.Multiplier) + req.Bonus;
            return new CalculateScoreResponse(finalScore, System.DateTime.UtcNow);
        }
    }

    public record CalculateScoreRequest(int BasePoints, int Multiplier, int Bonus = 0);
    public record CalculateScoreResponse(int TotalScore, System.DateTime CalculatedAt);
    """
  end

  defp code_unity do
    """
    using UnityEngine;
    using System.Threading.Tasks;
    using Exoforge.SDK;
    using Exoforge.Generated;

    public class GameplayRewardController : MonoBehaviour
    {
        // Style A: Unity Main-Thread Callback
        void OnLevelCompletedWithCallback(int points, int multiplier)
        {
            var client = ExoforgeSDK.Client.GameplayCalculator();

            client.CalculateScore(
                new CalculateScoreRequest(points, multiplier),
                onComplete: res => Debug.Log($"Callback Score: {res.TotalScore}"),
                onError: err => Debug.LogError($"Calculation failed: {err.Message}")
            );
        }

        // Style B: Task Async / Await Overload
        async Task OnLevelCompletedAsync(int points, int multiplier)
        {
            try
            {
                var client = ExoforgeSDK.Client.GameplayCalculator();
                var res = await client.CalculateScoreAsync(new CalculateScoreRequest(points, multiplier));
                Debug.Log($"Async Score: {res.TotalScore}");
            }
            catch (ExoActionException err)
            {
                Debug.LogError($"Calculation failed: {err.Message}");
            }
        }
    }
    """
  end

  defp code_exo_extension_page do
    """
    using Exoforge.SDK;

    [ExoExtension("leaderboard_service",
        Title = "Leaderboards & Rankings",
        Icon = "🏆",
        Category = "Game",
        Version = "1.0.0",
        Resources = new[] { typeof(PlayerScoreRecord) })]
    public class LeaderboardExtension
    {
        [ExoAction(Scope = "player")]
        public SubmitScoreResponse SubmitScore(SubmitScoreRequest req)
        {
            return new SubmitScoreResponse(req.Score, 1);
        }
    }
    """
  end

  defp code_exo_action_page do
    """
    // Mode is automatically inferred: Task<T> -> async, concrete -> sync.
    [ExoAction(Scope = "player")]
    public TransferItemResponse TransferItem(TransferItemRequest req)
    {
        if (req.Quantity <= 0)
            throw new ExoActionException("invalid_quantity", "Must transfer at least 1 item.");

        return new TransferItemResponse(req.ItemId, req.Quantity, true);
    }

    // Explicit Cast mode for fire-and-forget
    [ExoAction(Mode = ActionMode.Cast)]
    public void RecordTelemetry(TelemetryPayload payload)
    {
        Exo.Log.Info($"Telemetry: {payload.EventName}");
    }
    """
  end

  defp code_exo_cron_page do
    """
    [ExoCron("0 0 * * *", Description = "Rolls over daily leaderboards at midnight UTC", RunOnStartup = false)]
    public void RolloverDailyLeaderboards()
    {
        // Executes automatically at midnight UTC under cluster supervisor
    }
    """
  end

  defp code_exo_event_page do
    """
    // 1. Declare Event Schema Contract (Record)
    [ExoEvent("player.registered", Topic = "player:*")]
    public record PlayerRegisteredEvent(string PlayerId, string DisplayName, DateTime RegisteredAt);

    // 2. Handle Inbound Cluster Events in Extension
    public class LeaderboardExtension
    {
        public void OnEvent(string name, PlayerRegisteredEvent evt)
        {
            Exo.Log.Info($"Player joined: {evt.DisplayName}");
        }
    }
    """
  end

  defp code_exo_event_unity do
    """
    // Subscribe to strongly-typed event stream in Unity
    ExoforgeSDK.Events.Subscribe<PlayerRegisteredEvent>("player.registered", evt => {
        Debug.Log($"Welcome {evt.DisplayName}!");
    });
    """
  end

  defp code_exo_resource_page do
    """
    [ExoResource(Name = "player_scores", PrimaryKey = "id")]
    public record PlayerScoreRecord(
        [property: ExoColumn(PrimaryKey = true)] string Id,
        [property: ExoColumn(ReferencesType = typeof(PlayerDataRecord), Role = ExoRole.PlayerId, Label = "Player ID")] string PlayerId,
        [property: ExoColumn(Label = "Score", Sortable = true)] int Score,
        [property: ExoColumn(Badge = true, InputType = ExoInput.Color)] string TierBadge,
        [property: ExoColumn(Label = "Submitted At")] DateTime CreatedAt
    );
    """
  end
end
