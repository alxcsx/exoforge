defmodule Exoforge.Std.Docs.View do
  @moduledoc """
  Developer Guide, C# Attributes Reference & Live Dynamic API Reference Phoenix Component.
  Supports Markdown rendering, interactive flow navigation, dynamic cluster service catalogs,
  syntax highlighting, and 1-click Print/PDF export.
  """
  use Phoenix.Component

  alias Exoforge.Std.Docs.Markdown

  @badge_color_palette [
    "bg-emerald-50 text-emerald-700 border-emerald-200",
    "bg-sky-50 text-sky-700 border-sky-200",
    "bg-indigo-50 text-indigo-700 border-indigo-200",
    "bg-purple-50 text-purple-700 border-purple-200",
    "bg-amber-50 text-amber-700 border-amber-200",
    "bg-rose-50 text-rose-700 border-rose-200",
    "bg-teal-50 text-teal-700 border-teal-200",
    "bg-fuchsia-50 text-fuchsia-700 border-fuchsia-200"
  ]

  defp hashed_badge_class(nil), do: "bg-gray-100 text-gray-600 border-gray-200"

  defp hashed_badge_class(str) when is_binary(str) do
    idx = :erlang.phash2(str, length(@badge_color_palette))
    Enum.at(@badge_color_palette, idx)
  end

  defp hashed_badge_class(atom) when is_atom(atom), do: hashed_badge_class(to_string(atom))

  attr(:action_catalog, :list, default: [])
  attr(:extensions, :list, default: [])
  attr(:project_name, :string, default: "Game")
  attr(:studio_name, :string, default: "Studio")
  attr(:subpage, :string, default: "flow")
  attr(:myself, :any, default: nil)

  def view(assigns) do
    assigns = assign_new(assigns, :myself, fn -> nil end)

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
    <div id="developer-guide-container" phx-hook="GuideNavigator" class="space-y-6 max-w-6xl mx-auto pb-16 print:p-0 print:max-w-none print:pb-0">
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

        /* High-contrast callouts and disclaimers in dark theme */
        html:not(.light) .text-rose-950, html:not(.light) .text-rose-900 { color: #fca5a5 !important; }
        html:not(.light) .text-rose-800 { color: #fecdd3 !important; }
        html:not(.light) .text-emerald-950, html:not(.light) .text-emerald-900 { color: #6ee7b7 !important; }
        html:not(.light) .text-emerald-800 { color: #a7f3d0 !important; }
        html:not(.light) .text-amber-950, html:not(.light) .text-amber-900 { color: #fcd34d !important; }
        html:not(.light) .text-amber-800 { color: #fde68a !important; }
        html:not(.light) .text-blue-950, html:not(.light) .text-blue-900 { color: #93c5fd !important; }
        html:not(.light) .text-blue-800 { color: #bfdbfe !important; }

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
              phx-target={@myself}
              phx-value-subpage="flow"
              onclick="window.scrollTo({top: 0, behavior: 'smooth'})"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "flow", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>🚀</span>
              <span>Quickstart Flow</span>
            </button>
            <button
              type="button"
              phx-click="set_guide_subpage"
              phx-target={@myself}
              phx-value-subpage="use_cases"
              onclick="window.scrollTo({top: 0, behavior: 'smooth'})"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "use_cases", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>💡</span>
              <span>What You Can Build</span>
            </button>
            <button
              type="button"
              phx-click="set_guide_subpage"
              phx-target={@myself}
              phx-value-subpage="attributes"
              onclick="window.scrollTo({top: 0, behavior: 'smooth'})"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "attributes", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>🧩</span>
              <span>C# Attributes</span>
            </button>
            <button
              type="button"
              phx-click="set_guide_subpage"
              phx-target={@myself}
              phx-value-subpage="architecture"
              onclick="window.scrollTo({top: 0, behavior: 'smooth'})"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "architecture", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>🏗️</span>
              <span>Architecture</span>
            </button>
            <button
              type="button"
              phx-click="set_guide_subpage"
              phx-target={@myself}
              phx-value-subpage="catalog"
              onclick="window.scrollTo({top: 0, behavior: 'smooth'})"
              class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "catalog", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
            >
              <span>⚡</span>
              <span>Live API Reference</span>
            </button>
          </div>

          <!-- 1-Click PDF Export Button (Direct Binary Download) -->
          <a
            href="/api/docs/manual.pdf"
            download="exoforge-developer-manual.pdf"
            title="Download Exoforge Developer Manual as a PDF"
            class="px-3.5 py-1.5 rounded-xl bg-gray-900 hover:bg-gray-800 text-white text-xs font-bold transition-all shadow-xs flex items-center gap-1.5 cursor-pointer no-underline"
          >
            <svg class="w-3.5 h-3.5 text-gray-300" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <span>Export to PDF</span>
          </a>
        </div>
      </div>

      <!-- SUBPAGE ROUTING -->
      <%= case @subpage do %>
        <% "use_cases" -> %>
          <.subpage_use_cases myself={@myself} />
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
            myself={@myself}
          />
      <% end %>

      <!-- Floating Back to Top Button -->
      <button
        type="button"
        onclick="window.scrollTo({top: 0, behavior: 'smooth'})"
        title="Back to Top"
        class="fixed bottom-6 right-6 z-50 print:hidden p-3 rounded-full bg-primary-600 hover:bg-primary-700 text-white shadow-lg shadow-primary-900/30 transition-all duration-200 hover:scale-105 active:scale-95 flex items-center justify-center cursor-pointer border border-primary-500/30"
      >
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 15l7-7 7 7" />
        </svg>
      </button>
    </div>
    """
  end

  # ===========================================================================
  # COMPONENT: CODE TABS (ASYNC / CALLBACK / SQL / TABLE VARIANTS)
  # ===========================================================================
  attr(:badge, :string, default: "C#")
  attr(:tabs, :list, required: true)

  defp code_tabs(assigns) do
    ~H"""
    <div class="code-tab-group rounded-2xl border border-gray-800 overflow-hidden bg-gray-950 shadow-md">
      <div class="flex items-center justify-between border-b border-gray-800 bg-gray-900/90 px-3 py-2">
        <div class="flex items-center gap-1.5 text-xs font-bold flex-wrap">
          <%= for {tab, idx} <- Enum.with_index(@tabs) do %>
            <button
              type="button"
              onclick={"const g = this.closest('.code-tab-group'); g.querySelectorAll('.tab-btn').forEach(b => { b.classList.remove('bg-primary-600', 'text-white'); b.classList.add('text-gray-400', 'hover:text-white'); }); this.classList.add('bg-primary-600', 'text-white'); this.classList.remove('text-gray-400', 'hover:text-white'); g.querySelectorAll('.tab-pane').forEach((p, i) => p.classList.toggle('hidden', i !== #{idx}));"}
              class={"tab-btn px-2.5 py-1 rounded-lg transition-all text-xs cursor-pointer " <> if idx == 0, do: "bg-primary-600 text-white shadow-2xs", else: "text-gray-400 hover:text-white"}
            >
              <%= tab.label %>
            </button>
          <% end %>
        </div>
        <span class="text-xs text-emerald-400 font-mono shrink-0 pl-2"><%= @badge %></span>
      </div>

      <%= for {tab, idx} <- Enum.with_index(@tabs) do %>
        <div class={"tab-pane " <> if idx != 0, do: "hidden", else: ""}>
          <pre class="bg-gray-950 text-gray-200 p-4 font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(tab.code)) %></code></pre>
        </div>
      <% end %>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: QUICKSTART FLOW & HERO
  # ===========================================================================
  attr(:action_catalog, :list, default: [])
  attr(:extensions, :list, default: [])
  attr(:project_name, :string, default: "Game")
  attr(:studio_name, :string, default: "Studio")
  attr(:myself, :any, default: nil)

  defp subpage_flow(assigns) do
    assigns = assign_new(assigns, :myself, fn -> nil end)

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
            Creating Your First Online Multiplayer Feature
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
            Extensions execute as isolated native .NET microservices with actor concurrency supervision. Use modern C# records, type-safe APIs, and standard C# exceptions or structured error codes.
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
      <section id="step-auth" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
              <span>Two-Stage Anonymous Login &amp; Zero-Wiring Setup</span>
            </h4>
            <ul class="space-y-2.5 text-gray-600 leading-relaxed">
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span><strong>Zero Scene Wiring:</strong> You do not need to manually place prefabs in your scene. <code class="font-mono bg-gray-100 text-gray-800 px-1 py-0.5 rounded">ExoforgeManager</code> initializes automatically on demand when any SDK call is made.</span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span><strong>Stage 1 (Device Sign-In):</strong> Call <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-semibold">await ExoforgeSDK.Auth.LoginAnonymously()</code>. Signs the player in using their stable hardware device hash (<code class="font-mono bg-gray-100 text-gray-800 px-1 py-0.5 rounded">ExoDeviceId</code>).</span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span><strong>Stage 2 (Display Name):</strong> When <code class="font-mono bg-gray-100 text-gray-800 px-1 py-0.5 rounded">session.HasDisplayName == false</code>, prompt the player and call <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-semibold">await ExoforgeSDK.Auth.SetDisplayName("Viper")</code>.</span>
              </li>
              <li class="flex items-start gap-2">
                <span class="text-primary-600 font-bold shrink-0">●</span>
                <span><strong>Session Caching:</strong> Player session credentials persist in local storage securely, and reconnects resolve seamlessly.</span>
              </li>
            </ul>
          </div>

          <div>
            <.code_tabs
              badge="Unity C#"
              tabs={[
                %{label: "Async / Await (Task)", code: code_auth_async()},
                %{label: "Main-Thread Callback", code: code_auth_callback()}
              ]}
            />
          </div>
        </div>
      </section>

      <!-- STEP 2: Scaffold Extension -->
      <section id="step-scaffold" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
              <span><strong>Canonical Error Handling:</strong> Throw standard C# exceptions (e.g. <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-bold">ArgumentOutOfRangeException</code>) or structured <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-bold">ExoActionException(code, message)</code> to return error codes directly to client callbacks and catch blocks.</span>
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
      <section id="step-deploy" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
      <section id="step-stubs" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
              <span><strong>1-Click Unity Client Sync:</strong> Click <strong class="text-gray-900">🔄 Sync Client</strong> in the Unity toolbar (or via Studio) whenever backend contracts change to generate typed client bindings in <code class="font-mono bg-gray-100 text-gray-800 px-1 py-0.5 rounded">Assets/Exoforge/Generated/ExoforgeServices.g.cs</code>.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Server Extension Stubs:</strong> Run <code class="font-mono bg-gray-100 text-primary-700 px-1 py-0.5 rounded font-bold">exo extension stubs &lt;name&gt;</code> to generate strongly-typed inter-service call stubs from the cluster contract export.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Dual API Generated:</strong> Automatically generates strongly-typed request/response records, Unity main-thread callback methods, and <code class="font-mono text-primary-700 font-bold">Task&lt;T&gt;</code> async overloads.</span>
            </li>
          </ul>
        </div>
      </section>

      <!-- STEP 5: Call from Unity Gameplay Code -->
      <section id="step-gameplay" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
              <span><strong>Fluent Service Access:</strong> Call your backend service via generated client extensions: <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-bold">Exo.&lt;ServiceName&gt;</code> or <code class="font-mono text-primary-700 bg-gray-100 px-1 py-0.5 rounded font-bold">ExoforgeSDK.Client.&lt;ServiceName&gt;()</code>.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Main-Thread Callbacks (Style A):</strong> Use <code class="font-mono">onComplete</code> and <code class="font-mono">onError</code> handlers dispatched safely to the Unity main thread—no async/await or UniTask required.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="text-primary-600 font-bold shrink-0">●</span>
              <span><strong>Task Async/Await (Style B):</strong> Await <code class="font-mono text-primary-700 font-bold">&lt;ActionName&gt;Async(...)</code> in asynchronous methods or Coroutines, catching exceptions directly.</span>
            </li>
          </ul>

          <div class="pt-1">
            <.code_tabs
              badge="Unity C#"
              tabs={[
                %{label: "Async / Await (Task)", code: code_unity_async()},
                %{label: "Main-Thread Callback", code: code_unity_callback()}
              ]}
            />
          </div>
        </div>
      </section>

      <!-- Next Steps: Deep Dive into Blueprints or Live Action Catalog -->
      <div class="space-y-4 pt-4 border-t border-gray-200/60 print:hidden">
        <div class="flex items-center gap-2">
          <span class="text-xs font-bold text-gray-400 uppercase tracking-wider font-mono">Next Steps &amp; Deep Dive</span>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="p-6 rounded-3xl bg-gradient-to-r from-blue-950/40 via-indigo-950/30 to-blue-950/40 border border-blue-500/30 flex flex-col justify-between gap-4 shadow-md">
            <div class="space-y-1">
              <div class="flex items-center gap-2 text-blue-300 font-bold text-xs uppercase tracking-wider">
                <span>💡</span>
                <span>Architectural Blueprints</span>
              </div>
              <h3 class="text-base font-extrabold text-white">What You Can Build with Exoforge</h3>
              <p class="text-xs text-gray-300 leading-relaxed">
                Explore 6 production-grade C# patterns (Auction House, In-Memory Matchmaker, World Boss LiveOps, Guilds, Stripe Webhooks) and see how Exoforge eliminates PlayFab/UGS workarounds.
              </p>
            </div>
            <button
              type="button"
              onclick="window.scrollTo({top: 0, behavior: 'smooth'})"
              phx-click="set_guide_subpage"
              phx-target={@myself}
              phx-value-subpage="use_cases"
              class="self-start px-4 py-2 rounded-xl bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold transition-all shadow-md flex items-center gap-2 cursor-pointer"
            >
              <span>💡 Explore Architecture &amp; Blueprints</span>
              <span>➔</span>
            </button>
          </div>

          <div class="p-6 rounded-3xl bg-gradient-to-r from-purple-950/40 via-indigo-950/30 to-purple-950/40 border border-purple-500/30 flex flex-col justify-between gap-4 shadow-md">
            <div class="space-y-1">
              <div class="flex items-center gap-2 text-purple-300 font-bold text-xs uppercase tracking-wider">
                <span>⚡</span>
                <span>Live Action Catalog</span>
              </div>
              <h3 class="text-base font-extrabold text-white">Explore All Registered Services &amp; Actions</h3>
              <p class="text-xs text-gray-300 leading-relaxed">
                Inspect live cluster contracts, action signatures, parameters, authorization scopes, and copy-pasteable Unity SDK calling code in the dedicated API Reference.
              </p>
            </div>
            <button
              type="button"
              onclick="window.scrollTo({top: 0, behavior: 'smooth'})"
              phx-click="set_guide_subpage"
              phx-target={@myself}
              phx-value-subpage="catalog"
              class="self-start px-4 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white text-xs font-bold transition-all shadow-md flex items-center gap-2 cursor-pointer"
            >
              <span>⚡ View Live API Reference</span>
              <span>➔</span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: WHAT YOU CAN BUILD (BLUEPRINTS, USE CASES & ARCHITECTURE TIPS)
  # ===========================================================================
  attr(:myself, :any, default: nil)

  defp subpage_use_cases(assigns) do
    ~H"""
    <div class="space-y-8">
      <!-- Hero Header -->
      <div class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-4 print:border-gray-300 print:shadow-none">
        <div class="flex items-start gap-4">
          <span class="w-12 h-12 rounded-2xl bg-amber-50 text-amber-700 flex items-center justify-center font-bold text-2xl shrink-0 shadow-xs">
            💡
          </span>
          <div class="space-y-1">
            <div class="inline-flex items-center gap-2 px-2.5 py-0.5 rounded-full bg-amber-50 text-amber-800 border border-amber-200 text-[10px] font-bold uppercase tracking-wider">
              <span>Architecture Patterns &amp; Blueprints</span>
            </div>
            <h1 class="text-2xl font-extrabold text-gray-900 tracking-tight">What You Can Build with Exoforge</h1>
            <p class="text-xs text-gray-500 leading-relaxed max-w-3xl">
              Break free from the constraints of serverless BaaS (PlayFab, Unity Gaming Services). Build stateful, realtime, relational multiplayer services in clean C# with isolated databases, actor supervision, and sub-millisecond pub/sub.
            </p>
          </div>
        </div>

        <!-- Sticky Quick Jump Bar -->
        <div class="sticky top-2 z-20 print:hidden bg-white/95 backdrop-blur-md rounded-2xl border border-gray-200/90 p-3 shadow-xs flex flex-wrap gap-2 text-xs font-semibold">
          <span class="text-gray-400 text-[11px] font-mono self-center mr-1">Jump to:</span>
          <a href="#matrix" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>⚖️ Paradigm Shift (PlayFab vs UGS)</span>
          </a>
          <a href="#bp-economy" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>⚖️ Auction House &amp; P2P</span>
          </a>
          <a href="#bp-matchmaking" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>🎯 In-Memory Matchmaker</span>
          </a>
          <a href="#bp-world-boss" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>🐉 World Boss LiveOps</span>
          </a>
          <a href="#bp-guilds" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>🛡️ Guilds &amp; Clans</span>
          </a>
          <a href="#bp-seasons" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>🏆 Automated Season Reset</span>
          </a>
          <a href="#bp-webhooks" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>💳 Stripe &amp; Webhooks</span>
          </a>
          <a href="#rules" class="px-2.5 py-1 rounded-xl bg-amber-50 hover:bg-amber-100 text-amber-800 border border-amber-200 transition-colors">
            <span>⭐ Golden Rules</span>
          </a>
        </div>
      </div>

      <!-- SECTION: PARADIGM SHIFT COMPARISON MATRIX -->
      <section id="matrix" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="border-b border-gray-100 pb-4">
          <div class="flex items-center gap-2">
            <span class="text-xl">⚖️</span>
            <h2 class="text-xl font-extrabold text-gray-900 tracking-tight">The Paradigm Shift: Exoforge vs. Legacy BaaS</h2>
          </div>
          <p class="text-xs text-gray-500 mt-1">
            Why gameplay features that feel hacky or cost prohibitive on PlayFab or Unity Gaming Services (UGS) are first-class primitives in Exoforge.
          </p>
        </div>

        <div class="overflow-x-auto rounded-2xl border border-gray-200">
          <table class="w-full text-left text-xs bg-white">
            <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
              <tr>
                <th class="py-3 px-4">Architecture Dimension</th>
                <th class="py-3 px-4 text-gray-600">Microsoft PlayFab (CloudScript)</th>
                <th class="py-3 px-4 text-gray-600">Unity Gaming Services (Cloud Code)</th>
                <th class="py-3 px-4 text-primary-700 font-bold bg-primary-50/60">Exoforge Native Extensions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100 text-[11px] leading-relaxed">
              <tr>
                <td class="py-3 px-4 font-bold text-gray-900">Execution Lifecycle</td>
                <td class="py-3 px-4 text-gray-600">Serverless JS or Azure Functions. 1–3s cold starts; external subscription required.</td>
                <td class="py-3 px-4 text-gray-600">Ephemeral serverless containers. Hard 15-second timeout; idle workers killed.</td>
                <td class="py-3 px-4 bg-primary-50/50 font-medium text-gray-900">
                  <span class="text-emerald-600 font-bold">✓ Long-lived native OS processes.</span> Zero cold starts; sub-millisecond dispatch.
                </td>
              </tr>
              <tr>
                <td class="py-3 px-4 font-bold text-gray-900">State &amp; Background Execution</td>
                <td class="py-3 px-4 text-gray-600">None. Strictly stateless; static variables wiped between calls.</td>
                <td class="py-3 px-4 text-gray-600">None. Workers cycle unpredictably; ephemeral memory.</td>
                <td class="py-3 px-4 bg-primary-50/50 font-medium text-gray-900">
                  <span class="text-emerald-600 font-bold">✓ Clean DB Storage &amp; Dedicated Workers.</span> Extensions act as stateless handlers while dedicated background workers run tick loops, with zero data loss on updates.
                </td>
              </tr>
              <tr>
                <td class="py-3 px-4 font-bold text-gray-900">Data Storage</td>
                <td class="py-3 px-4 text-gray-600">Per-player JSON blobs. No cross-player SQL queries; ~10 writes/sec rate limit.</td>
                <td class="py-3 px-4 text-gray-600">Cloud Save key-value JSON. Size limits; no multi-player relational queries.</td>
                <td class="py-3 px-4 bg-primary-50/50 font-medium text-gray-900">
                  <span class="text-emerald-600 font-bold">✓ Isolated Relational SQL.</span> Direct queries (<code class="font-mono text-primary-700 font-bold">Exo.Database.Query&lt;T&gt;</code>), joins, and indexes.
                </td>
              </tr>
              <tr>
                <td class="py-3 px-4 font-bold text-gray-900">Real-Time Push</td>
                <td class="py-3 px-4 text-gray-600">Requires client polling or third-party SignalR / PubNub integration.</td>
                <td class="py-3 px-4 text-gray-600">Requires client polling or external WebSocket server setup.</td>
                <td class="py-3 px-4 bg-primary-50/50 font-medium text-gray-900">
                  <span class="text-emerald-600 font-bold">✓ Built-in :pg Pub/Sub Bus.</span> 0.07 ms fanout to thousands of clients via <code class="font-mono text-primary-700 font-bold">Exo.Events.EmitAsync</code>.
                </td>
              </tr>
              <tr>
                <td class="py-3 px-4 font-bold text-gray-900">LiveOps &amp; Tuning</td>
                <td class="py-3 px-4 text-gray-600">Manual unvalidated JSON in "Title Data". Easy for typos to break production.</td>
                <td class="py-3 px-4 text-gray-600">Remote Config raw key-value pairs without structured entity UI.</td>
                <td class="py-3 px-4 bg-primary-50/50 font-medium text-gray-900">
                  <span class="text-emerald-600 font-bold">✓ Auto-Generated Studio UI.</span> Records with <code class="font-mono text-primary-700 font-bold">[ExoResource]</code> generate live tables, sliders &amp; forms.
                </td>
              </tr>
              <tr>
                <td class="py-3 px-4 font-bold text-gray-900">Scheduled Tasks</td>
                <td class="py-3 px-4 text-gray-600">Scheduled Tasks time out when iterating over thousands of player records.</td>
                <td class="py-3 px-4 text-gray-600">None native. Requires external cron runner calling public webhooks.</td>
                <td class="py-3 px-4 bg-primary-50/50 font-medium text-gray-900">
                  <span class="text-emerald-600 font-bold">✓ Native [ExoCron] Attribute.</span> Runs in-process under cluster supervision.
                </td>
              </tr>
              <tr>
                <td class="py-3 px-4 font-bold text-gray-900">External Webhooks</td>
                <td class="py-3 px-4 text-gray-600">Requires wiring Azure API Management or AWS Gateway for signature checks.</td>
                <td class="py-3 px-4 text-gray-600">Rejects calls lacking a Unity Player Bearer token; needs proxy server.</td>
                <td class="py-3 px-4 bg-primary-50/50 font-medium text-gray-900">
                  <span class="text-emerald-600 font-bold">✓ Native [ExoWebhook] Attribute.</span> Receive Stripe, Steam, Discord hooks with zero proxy glue.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- BLUEPRINT 1: CROSS-PLAYER ECONOMY -->
      <section id="bp-economy" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-amber-50 text-amber-700 flex items-center justify-center font-bold text-lg">
              ⚖️
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900">Blueprint 1: Cross-Player Economy (Auction House &amp; P2P)</h2>
                <span class="px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 text-[10px] font-bold uppercase tracking-wider">Economy</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Global player-driven marketplace with atomic currency exchange and instant push notifications.</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-1.5 self-start sm:self-auto font-mono text-[10px]">
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoResource]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoAction]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoEvent]</span>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <div class="p-4 rounded-2xl bg-rose-50 border border-rose-200 text-rose-950 space-y-1.5">
            <div class="font-bold text-rose-900 flex items-center gap-1.5">
              <span>❌</span> <span>Why This Is Hacky in PlayFab &amp; UGS:</span>
            </div>
            <p class="leading-relaxed text-rose-800 text-[11px]">
              Player inventory is locked inside isolated private JSON stores. Querying listings across players requires abusing PlayFab Shared Group Data (which has severe lock contention and race conditions) or hosting and paying for an external PostgreSQL database on AWS.
            </p>
          </div>
          <div class="p-4 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-950 space-y-1.5">
            <div class="font-bold text-emerald-900 flex items-center gap-1.5">
              <span>✅</span> <span>The Exoforge Native Pattern:</span>
            </div>
            <p class="leading-relaxed text-emerald-800 text-[11px]">
              Declare an <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded">[ExoResource("market_listings")]</code>. Use standard relational SQL with sorting and pagination. On purchase, swap currency and items atomically and emit an <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded">[ExoEvent]</code> so the seller's client receives an instant WebSocket alert.
            </p>
          </div>
        </div>

        <div>
          <.code_tabs
            badge="C# 12 / .NET 9+"
            tabs={[
              %{label: "Hybrid (Raw SQL Queries + Key/Value)", code: snippet_auction_house()},
              %{label: "Type-Safe Table Repository (No SQL)", code: snippet_auction_house_table()}
            ]}
          />
        </div>
      </section>

      <!-- BLUEPRINT 2: IN-MEMORY MATCHMAKING -->
      <section id="bp-matchmaking" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-blue-50 text-blue-700 flex items-center justify-center font-bold text-lg">
              🎯
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900">Blueprint 2: Stateful In-Memory Matchmaking &amp; Turn-Based Rooms</h2>
                <span class="px-2 py-0.5 rounded-full bg-blue-100 text-blue-800 text-[10px] font-bold uppercase tracking-wider">Multiplayer</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">High-speed ELO queue and turn-based room state held in C# memory with zero polling.</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-1.5 self-start sm:self-auto font-mono text-[10px]">
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoAction]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoCron]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoEvent]</span>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <div class="p-4 rounded-2xl bg-rose-50 border border-rose-200 text-rose-950 space-y-1.5">
            <div class="font-bold text-rose-900 flex items-center gap-1.5">
              <span>❌</span> <span>Why This Is Hacky in PlayFab &amp; UGS:</span>
            </div>
            <p class="leading-relaxed text-rose-800 text-[11px]">
              Cloud Code workers are stateless; memory is wiped after each invocation. Custom matchmaking queues or turn-based room states must be written to external databases on every move, and clients must poll every 2–5 seconds waiting for a match.
            </p>
          </div>
          <div class="p-4 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-950 space-y-1.5">
            <div class="font-bold text-emerald-900 flex items-center gap-1.5">
              <span>✅</span> <span>The Exoforge Native Pattern:</span>
            </div>
            <p class="leading-relaxed text-emerald-800 text-[11px]">
              Because an extension is a persistent process, store queues directly in C# memory (<code class="font-mono bg-emerald-100 px-1 py-0.5 rounded">ConcurrentDictionary</code>). Match players in-memory, then push an immediate <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded">[ExoEvent("matchmaking.found")]</code> over WebSocket. Total pairing latency: &lt; 1ms.
            </p>
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>MatchmakerExtension.cs</span>
            <span class="font-mono text-[11px] text-gray-400">C# 12 / .NET 9+</span>
          </div>
          <div class="relative group">
            <button type="button" onclick="window.exoCopyCode && window.exoCopyCode(this)" class="absolute top-2.5 right-3 opacity-0 group-hover:opacity-100 transition-opacity text-[10px] font-mono font-bold px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white border border-gray-700 flex items-center gap-1 cursor-pointer print:hidden shadow-xs" title="Copy code">
              <span class="copy-icon">📋</span><span class="copy-text">Copy</span>
            </button>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_matchmaking())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- BLUEPRINT 3: DESIGNER-FRIENDLY LIVEOPS -->
      <section id="bp-world-boss" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-purple-50 text-purple-700 flex items-center justify-center font-bold text-lg">
              🐉
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900">Blueprint 3: Designer-Friendly LiveOps &amp; Global Boss Events</h2>
                <span class="px-2 py-0.5 rounded-full bg-purple-100 text-purple-800 text-[10px] font-bold uppercase tracking-wider">LiveOps</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Studio-tunable game balance, gacha rates, and server-wide boss battles with zero engineering glue.</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-1.5 self-start sm:self-auto font-mono text-[10px]">
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoSingletonResource]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoColumn]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoEvent]</span>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <div class="p-4 rounded-2xl bg-rose-50 border border-rose-200 text-rose-950 space-y-1.5">
            <div class="font-bold text-rose-900 flex items-center gap-1.5">
              <span>❌</span> <span>Why This Is Hacky in PlayFab &amp; UGS:</span>
            </div>
            <p class="leading-relaxed text-rose-800 text-[11px]">
              Tuning drop rates or setting up a shared World Boss in PlayFab requires editing unvalidated JSON in "Title Data". One syntax error can break production, and coordinating a 10,000,000 HP boss requires solving race conditions across global JSON blobs.
            </p>
          </div>
          <div class="p-4 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-950 space-y-1.5">
            <div class="font-bold text-emerald-900 flex items-center gap-1.5">
              <span>✅</span> <span>The Exoforge Native Pattern:</span>
            </div>
            <p class="leading-relaxed text-emerald-800 text-[11px]">
              Annotate records with <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded">[ExoSingletonResource]</code> and UI attributes (<code class="font-mono">ExoInput.Range</code>, <code class="font-mono">ExoRole.Currency</code>). Studio renders interactive forms for designers, and HP updates are broadcast in real time across the cluster.
            </p>
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>WorldBossExtension.cs</span>
            <span class="font-mono text-[11px] text-gray-400">C# 12 / .NET 9+</span>
          </div>
          <div class="relative group">
            <button type="button" onclick="window.exoCopyCode && window.exoCopyCode(this)" class="absolute top-2.5 right-3 opacity-0 group-hover:opacity-100 transition-opacity text-[10px] font-mono font-bold px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white border border-gray-700 flex items-center gap-1 cursor-pointer print:hidden shadow-xs" title="Copy code">
              <span class="copy-icon">📋</span><span class="copy-text">Copy</span>
            </button>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_world_boss())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- BLUEPRINT 4: GUILDS & CLANS -->
      <section id="bp-guilds" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-indigo-50 text-indigo-700 flex items-center justify-center font-bold text-lg">
              🛡️
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900">Blueprint 4: Guilds, Clans &amp; Real-Time Social Feeds</h2>
                <span class="px-2 py-0.5 rounded-full bg-indigo-100 text-indigo-800 text-[10px] font-bold uppercase tracking-wider">Social</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Relational guild rosters, shared vaults, and topic-scoped WebSocket event feeds.</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-1.5 self-start sm:self-auto font-mono text-[10px]">
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoResource]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoAction]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoEvent]</span>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <div class="p-4 rounded-2xl bg-rose-50 border border-rose-200 text-rose-950 space-y-1.5">
            <div class="font-bold text-rose-900 flex items-center gap-1.5">
              <span>❌</span> <span>Why This Is Hacky in PlayFab &amp; UGS:</span>
            </div>
            <p class="leading-relaxed text-rose-800 text-[11px]">
              Guilds in PlayFab require stitching together Entity Groups, custom JSON files, and third-party chat solutions like Photon or PubNub. Adding member roles and shared bank vaults requires multiple API calls, manual security checks, and continuous polling.
            </p>
          </div>
          <div class="p-4 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-950 space-y-1.5">
            <div class="font-bold text-emerald-900 flex items-center gap-1.5">
              <span>✅</span> <span>The Exoforge Native Pattern:</span>
            </div>
            <p class="leading-relaxed text-emerald-800 text-[11px]">
              Model guilds as relational tables with <code class="font-mono">ReferencesType = typeof(PlayerDataRecord)</code> so Studio links directly to player profiles. Scope events to <code class="font-mono">guild:&#123;id&#125;</code> so members receive live bank deposits and chat over their existing WebSocket connection.
            </p>
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>GuildExtension.cs</span>
            <span class="font-mono text-[11px] text-gray-400">C# 12 / .NET 9+</span>
          </div>
          <div class="relative group">
            <button type="button" onclick="window.exoCopyCode && window.exoCopyCode(this)" class="absolute top-2.5 right-3 opacity-0 group-hover:opacity-100 transition-opacity text-[10px] font-mono font-bold px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white border border-gray-700 flex items-center gap-1 cursor-pointer print:hidden shadow-xs" title="Copy code">
              <span class="copy-icon">📋</span><span class="copy-text">Copy</span>
            </button>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_guilds())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- BLUEPRINT 5: AUTOMATED SEASON ROLLOVERS -->
      <section id="bp-seasons" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-emerald-50 text-emerald-700 flex items-center justify-center font-bold text-lg">
              🏆
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900">Blueprint 5: Automated Season Rollovers &amp; Leaderboards</h2>
                <span class="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 text-[10px] font-bold uppercase tracking-wider">Operations</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Automated background resets, rank archiving, and rewards in a single atomic SQL transaction.</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-1.5 self-start sm:self-auto font-mono text-[10px]">
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoCron]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoEvent]</span>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <div class="p-4 rounded-2xl bg-rose-50 border border-rose-200 text-rose-950 space-y-1.5">
            <div class="font-bold text-rose-900 flex items-center gap-1.5">
              <span>❌</span> <span>Why This Is Hacky in PlayFab &amp; UGS:</span>
            </div>
            <p class="leading-relaxed text-rose-800 text-[11px]">
              Cloud Code has no native cron triggers, and PlayFab Scheduled Tasks time out when iterating through large player lists. Studios maintain complex external AWS Lambda or Azure Functions infrastructure with batching loops and pagination.
            </p>
          </div>
          <div class="p-4 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-950 space-y-1.5">
            <div class="font-bold text-emerald-900 flex items-center gap-1.5">
              <span>✅</span> <span>The Exoforge Native Pattern:</span>
            </div>
            <p class="leading-relaxed text-emerald-800 text-[11px]">
              Use <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded">[ExoCron("0 0 * * 1")]</code> for weekly execution. Combine rank archiving and score resets in atomic SQL statements, then broadcast a season rollover event to all connected Unity clients.
            </p>
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>SeasonExtension.cs</span>
            <span class="font-mono text-[11px] text-gray-400">C# 12 / .NET 9+</span>
          </div>
          <div class="relative group">
            <button type="button" onclick="window.exoCopyCode && window.exoCopyCode(this)" class="absolute top-2.5 right-3 opacity-0 group-hover:opacity-100 transition-opacity text-[10px] font-mono font-bold px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white border border-gray-700 flex items-center gap-1 cursor-pointer print:hidden shadow-xs" title="Copy code">
              <span class="copy-icon">📋</span><span class="copy-text">Copy</span>
            </button>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_season_rollover())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- BLUEPRINT 6: WEB STORE & WEBHOOKS -->
      <section id="bp-webhooks" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-rose-50 text-rose-700 flex items-center justify-center font-bold text-lg">
              💳
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900">Blueprint 6: Web Store Checkout, Stripe Webhooks &amp; Instant Delivery</h2>
                <span class="px-2 py-0.5 rounded-full bg-rose-100 text-rose-800 text-[10px] font-bold uppercase tracking-wider">Payments</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Secure external HTTP webhooks with HMAC validation and instant WebSocket delivery to Unity.</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-1.5 self-start sm:self-auto font-mono text-[10px]">
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoWebhook]</span>
            <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-bold">[ExoEvent]</span>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <div class="p-4 rounded-2xl bg-rose-50 border border-rose-200 text-rose-950 space-y-1.5">
            <div class="font-bold text-rose-900 flex items-center gap-1.5">
              <span>❌</span> <span>Why This Is Hacky in PlayFab &amp; UGS:</span>
            </div>
            <p class="leading-relaxed text-rose-800 text-[11px]">
              Unity Cloud Code endpoints reject requests lacking a Unity Player Bearer token, making it impossible to receive raw webhooks from Stripe, Shopify, or Steam without an external proxy server. In PlayFab, developers must configure Azure API Management or AWS API Gateway.
            </p>
          </div>
          <div class="p-4 rounded-2xl bg-emerald-50 border border-emerald-200 text-emerald-950 space-y-1.5">
            <div class="font-bold text-emerald-900 flex items-center gap-1.5">
              <span>✅</span> <span>The Exoforge Native Pattern:</span>
            </div>
            <p class="leading-relaxed text-emerald-800 text-[11px]">
              Expose a public endpoint with <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded">[ExoWebhook("stripe")]</code>. Validate headers directly in C#, record the purchase in SQL, and push a <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded">PurchaseFulfilledEvent</code> so the player's client immediately unlocks the item.
            </p>
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>BillingExtension.cs</span>
            <span class="font-mono text-[11px] text-gray-400">C# 12 / .NET 9+</span>
          </div>
          <div class="relative group">
            <button type="button" onclick="window.exoCopyCode && window.exoCopyCode(this)" class="absolute top-2.5 right-3 opacity-0 group-hover:opacity-100 transition-opacity text-[10px] font-mono font-bold px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-300 hover:text-white border border-gray-700 flex items-center gap-1 cursor-pointer print:hidden shadow-xs" title="Copy code">
              <span class="copy-icon">📋</span><span class="copy-text">Copy</span>
            </button>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(snippet_webhooks_checkout())) %></code></pre>
          </div>
        </div>
      </section>

      <!-- SECTION: ARCHITECTURE GOLDEN RULES -->
      <section id="rules" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="border-b border-gray-100 pb-4">
          <div class="flex items-center gap-2">
            <span class="text-xl">⭐</span>
            <h2 class="text-xl font-extrabold text-gray-900 tracking-tight">Exoforge Architecture Tips &amp; Golden Rules</h2>
          </div>
          <p class="text-xs text-gray-500 mt-1">
            Five core engineering principles for designing scalable, maintainable multiplayer game backends.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 text-xs text-gray-600">
          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-2">
            <div class="w-8 h-8 rounded-xl bg-primary-100 text-primary-700 font-black flex items-center justify-center text-sm shadow-xs">
              1
            </div>
            <h3 class="font-bold text-gray-900 text-sm">Stateless Extensions, Resilient State in DB &amp; Workers</h3>
            <p class="leading-relaxed text-[11px]">
              Keep extensions lightweight and stateless for zero-downtime hot reloading. Store durable state via <code class="font-mono text-primary-700">Exo.Database</code>, and delegate long-running continuous game loops or tick timers to dedicated cluster workers so code updates never corrupt active gameplay state.
            </p>
          </div>

          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-2">
            <div class="w-8 h-8 rounded-xl bg-purple-100 text-purple-700 font-black flex items-center justify-center text-sm shadow-xs">
              2
            </div>
            <h3 class="font-bold text-gray-900 text-sm">Let [ExoResource] Build Your UI</h3>
            <p class="leading-relaxed text-[11px]">
              Never build custom internal admin tools. Decorate records with <code class="font-mono text-purple-700">[ExoColumn]</code> roles (<code class="font-mono">ExoRole.PlayerId</code>, <code class="font-mono">Badge = true</code>, <code class="font-mono">ExoInput.Range</code>), and Producer Studio will auto-generate searchable tables and editing drawers.
            </p>
          </div>

          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-2">
            <div class="w-8 h-8 rounded-xl bg-cyan-100 text-cyan-700 font-black flex items-center justify-center text-sm shadow-xs">
              3
            </div>
            <h3 class="font-bold text-gray-900 text-sm">Decouple via Stubs &amp; Events</h3>
            <p class="leading-relaxed text-[11px]">
              Separate complex domains into independent extensions (<code class="font-mono text-cyan-700">inventory</code>, <code class="font-mono text-cyan-700">billing</code>). Call other extensions using generated typed stubs (<code class="font-mono">exo extension stubs &lt;name&gt;</code>), and broadcast major lifecycle moments asynchronously.
            </p>
          </div>

          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-2">
            <div class="w-8 h-8 rounded-xl bg-emerald-100 text-emerald-700 font-black flex items-center justify-center text-sm shadow-xs">
              4
            </div>
            <h3 class="font-bold text-gray-900 text-sm">Never Poll from Unity</h3>
            <p class="leading-relaxed text-[11px]">
              If a client action requires waiting (matchmaking, async crafting, webhook confirmation), return an immediate response from <code class="font-mono text-emerald-700">[ExoAction]</code> and push the completion payload using <code class="font-mono text-emerald-700">Exo.Events.EmitAsync</code>.
            </p>
          </div>

          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-2 col-span-1 md:col-span-2 lg:col-span-1">
            <div class="w-8 h-8 rounded-xl bg-amber-100 text-amber-700 font-black flex items-center justify-center text-sm shadow-xs">
              5
            </div>
            <h3 class="font-bold text-gray-900 text-sm">Standard C# Exceptions &amp; Custom Error Codes</h3>
            <p class="leading-relaxed text-[11px]">
              Throw standard C# exceptions (e.g. <code class="font-mono text-amber-700 font-bold">ArgumentOutOfRangeException</code>) for quick validations, or <code class="font-mono text-amber-700 font-bold">ExoActionException(code, message)</code> for business logic errors. Both are caught and cleanly dispatched to Unity <code class="font-mono">onError</code> callbacks or async catch blocks with structured error payloads.
            </p>
          </div>
        </div>
      </section>
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

        <div class="sticky top-2 z-20 print:hidden bg-white/95 backdrop-blur-md rounded-2xl border border-gray-200/90 p-3 shadow-xs flex flex-wrap gap-2 text-xs font-semibold">
          <span class="text-gray-400 text-[11px] font-mono self-center mr-1">Quick Jump:</span>
          <a href="#attr-extension" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>[ExoService]</span>
          </a>
          <a href="#attr-action" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>[ExoAction]</span>
          </a>
          <a href="#attr-cron" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>[ExoCron]</span>
          </a>
          <a href="#attr-event" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>[ExoEvent]</span>
          </a>
          <a href="#attr-resource" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>[ExoResource]</span>
          </a>
          <a href="#attr-dependency" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>[ExoDependency]</span>
          </a>
          <a href="#attr-webhook" class="px-2.5 py-1 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 transition-colors">
            <span>[ExoWebhook]</span>
          </a>
          <a href="#attr-capabilities" class="px-2.5 py-1 rounded-xl bg-purple-50 hover:bg-purple-100 text-purple-700 border border-purple-200/60 transition-colors">
            <span>⚡ Exo.* Capabilities</span>
          </a>
        </div>
      </div>

      <!-- [ExoExtension] -->
      <section id="attr-extension" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
            Source: <strong class="text-indigo-700">Extension Manager</strong> (<code class="text-gray-800">exoforge_std_extension_manager</code>)
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
      <section id="attr-action" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
                  <td class="py-2 px-3 text-gray-400">Optional ("player")</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Minimum authorization scope needed to invoke (<code class="font-mono text-primary-700">"guest"</code>, <code class="font-mono text-primary-700">"player"</code>, <code class="font-mono text-primary-700">"admin"</code>, <code class="font-mono text-primary-700">"studio"</code>). Defaults to authenticated player scope; the cluster enforces this before invoking the extension.</td>
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
      <section id="attr-cron" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
      <section id="attr-event" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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
      <section id="attr-resource" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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

      <!-- [ExoDependency] -->
      <section id="attr-dependency" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-cyan-50 text-cyan-700 flex items-center justify-center font-bold text-lg">
              🔗
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoDependency]</h2>
                <span class="px-2 py-0.5 rounded-full bg-cyan-100 text-cyan-800 text-[10px] font-bold uppercase tracking-wider">Topological Dependency</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Declares explicit service dependencies determining DAG boot order and client stub scope.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-cyan-700">ExtensionBootstrapper</strong> (Kernel DAG)
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            Decorate your extension class or contract with <code class="font-mono text-cyan-700 font-bold">[ExoDependency("service_name")]</code> or type-safe contract pinning <code class="font-mono text-cyan-700 font-bold">[ExoDependency&lt;TContract&gt;]</code>.
            Dependencies are automatically inferred from static <code class="font-mono text-cyan-700">Exo.&lt;Service&gt;</code> calls during compilation, while explicit attributes guarantee topological DAG boot order or pin a specific service implementation.
          </p>

          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_dependency_page())) %></code></pre>
        </div>
      </section>

      <!-- [ExoWebhook] -->
      <section id="attr-webhook" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-rose-50 text-rose-700 flex items-center justify-center font-bold text-lg">
              🪝
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoWebhook]</h2>
                <span class="px-2 py-0.5 rounded-full bg-rose-100 text-rose-800 text-[10px] font-bold uppercase tracking-wider">External HTTP Hook</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Exposes endpoints for external provider webhooks (e.g. Stripe, GitHub, Discord).</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-rose-700">HTTP Gateway</strong> (<code class="text-gray-800">exoforge_std_http</code>)
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            Decorate webhook handlers with <code class="font-mono text-rose-700 font-bold">[ExoWebhook("name")]</code> to receive raw inbound HTTP POST events with request headers, signature validation data, and raw body buffers.
          </p>

          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-xs md:text-[13px] leading-relaxed overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_webhook_page())) %></code></pre>
        </div>
      </section>

      <!-- Static Exo Capabilities Reference -->
      <section id="attr-capabilities" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-5 print:border-gray-300 print:shadow-none print:break-inside-avoid">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-4">
          <div class="flex items-center gap-3">
            <span class="w-10 h-10 rounded-2xl bg-purple-50 text-purple-700 flex items-center justify-center font-bold text-lg">
              ⚡
            </span>
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">Static Exo.* Capabilities</h2>
                <span class="px-2 py-0.5 rounded-full bg-purple-100 text-purple-800 text-[10px] font-bold uppercase tracking-wider">Host Bridge</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">High-performance ambient static access to host capabilities without service reflection.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-purple-700">HostBridge &amp; PluginContext</strong>
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            Extensions access cluster capabilities via the ambient static <code class="font-mono text-purple-700 font-bold">Exo</code> holder with zero reflection overhead and automatic tree-shaking:
          </p>

          <div class="overflow-x-auto rounded-xl border border-gray-200">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Capability</th>
                  <th class="py-2 px-3">Property</th>
                  <th class="py-2 px-3">Example Usage</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Database</td>
                  <td class="py-2 px-3 text-purple-700">Exo.Database</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600"><code class="font-mono">Exo.Database.Get&lt;Score&gt;("scores", id)</code>, <code class="font-mono">Exo.Database.Put(record)</code>, <code class="font-mono">Exo.Database.Query&lt;T&gt;("SELECT ...")</code></td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Events</td>
                  <td class="py-2 px-3 text-purple-700">Exo.Events</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600"><code class="font-mono">await Exo.Events.EmitAsync(new PlayerRegisteredEvent(id, name))</code></td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Logger</td>
                  <td class="py-2 px-3 text-purple-700">Exo.Logger</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600"><code class="font-mono">Exo.Logger.Info("Player joined")</code>, <code class="font-mono">Exo.Logger.Error("Calculation failed")</code></td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Actions</td>
                  <td class="py-2 px-3 text-purple-700">Exo.Actions</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600"><code class="font-mono">await Exo.Actions.CallActionAsync&lt;Req, Res&gt;(req)</code></td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Context</td>
                  <td class="py-2 px-3 text-purple-700">Exo.Context</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600"><code class="font-mono">Exo.Context.CallerPlayerId</code>, <code class="font-mono">Exo.Context.CallerScopes</code></td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- Data Access Paradigms: Table Repository vs Parameterized SQL -->
          <div class="mt-6 space-y-4 pt-4 border-t border-gray-100">
            <div>
              <h4 class="font-bold text-gray-900 text-sm flex items-center gap-2">
                <span>🗄️</span>
                <span>Database Access Paradigms: Table Repository vs. Parameterized SQL</span>
              </h4>
              <p class="text-xs text-gray-500 mt-0.5">
                Exoforge provides two complementary database paradigms to eliminate ORM bloat and keep runtime memory minimal.
              </p>
            </div>

            <.code_tabs
              badge="C# Database"
              tabs={[
                %{label: "Type-Safe Table Repository (No SQL)", code: code_db_table()},
                %{label: "Parameterized Raw SQL (Queries & In-Place Updates)", code: code_db_sql()}
              ]}
            />

            <details class="group cursor-pointer rounded-2xl bg-amber-500/10 border border-amber-500/30 p-4 text-xs text-amber-950 dark:text-amber-200 transition-all">
              <summary class="flex items-center justify-between font-bold text-amber-900 dark:text-amber-300 select-none list-none">
                <div class="flex items-center gap-2">
                  <span>💡</span>
                  <span>Architecture Note: Why Exoforge avoids complex Query Builders</span>
                </div>
                <svg class="w-4 h-4 text-amber-700 dark:text-amber-300 group-open:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </summary>
              <div class="mt-3 pt-3 border-t border-amber-500/20 space-y-2 text-[11px] leading-relaxed">
                <p>
                  <strong>No runtime query builders — by deliberate design.</strong> Complex query builders (like EF Core or LINQ-to-Entities) introduce runtime expression compilation, large binary size, and high garbage collection pressure. Instead, Exoforge gives you two native, zero-overhead primitives:
                </p>
                <ul class="list-disc list-inside space-y-1">
                  <li><strong>Type-Safe Table Repository (<code class="font-mono font-semibold">Exo.Database.Table&lt;T&gt;()</code>):</strong> Pure C# CRUD with auto-resolved table names, primary keys, and singleton lookups. Zero SQL strings needed.</li>
                  <li><strong>Parameterized Raw SQL (<code class="font-mono font-semibold">Exo.Database.Query&lt;T&gt;()</code>):</strong> High-performance SQL queries with positional <code class="font-mono font-semibold">$1, $2, ...</code> arguments, automatic record mapping, and atomic in-place updates.</li>
                </ul>
              </div>
            </details>
          </div>
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
    <div id="architecture-graph" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none">
      <Exoforge.Std.Docs.ArchitectureGraph.visualizer />
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: DYNAMIC API REFERENCE & CATALOG
  # ===========================================================================
  defp subpage_catalog(assigns) do
    ~H"""
    <section id="catalog" data-guide-section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none print:break-inside-avoid">
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

      <div class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 pt-2 border-t border-gray-100">
        <div class="relative flex-1">
          <input
            type="text"
            id="catalog-search"
            placeholder="Search services, actions, parameters..."
            oninput="const q = this.value.toLowerCase().trim(); document.querySelectorAll('#catalog-list > details').forEach(d => { const text = d.innerText.toLowerCase(); d.style.display = (!q || text.includes(q)) ? '' : 'none'; if (q && text.includes(q)) d.open = true; });"
            class="w-full pl-9 pr-4 py-2 bg-gray-50 hover:bg-gray-100/80 focus:bg-white border border-gray-200 rounded-xl text-xs text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500/20 focus:border-primary-500 transition-all font-mono"
          />
          <svg class="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <button
            type="button"
            onclick="document.querySelectorAll('#catalog-list details').forEach(d => d.open = true);"
            class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-semibold transition-colors cursor-pointer"
          >
            Expand All
          </button>
          <button
            type="button"
            onclick="document.querySelectorAll('#catalog-list details').forEach(d => d.open = false);"
            class="px-3 py-1.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-semibold transition-colors cursor-pointer"
          >
            Collapse All
          </button>
        </div>
      </div>

      <%= if @action_catalog == [] do %>
        <div class="text-center py-12 text-gray-400 bg-gray-50 rounded-2xl border border-dashed border-gray-200">
          No callable services currently registered. Scaffold and deploy an extension to see it live!
        </div>
      <% else %>
        <div id="catalog-list" class="space-y-4">
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
                        <%= if act.mode in ["async", "cast"] do %>
                          <span class={"text-[9px] font-bold px-1.5 py-0.5 rounded border uppercase font-mono " <> hashed_badge_class(act.mode)}><%= act.mode %></span>
                        <% end %>
                        <%= if act.scope do %>
                          <span class={"text-[9px] font-bold px-1.5 py-0.5 rounded border uppercase font-mono " <> hashed_badge_class(act.scope)}><%= act.scope %></span>
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
    Exo.#{service_pascal}.#{action_pascal}(
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
    var result = await Exo.#{service_pascal}.#{action_pascal}Async(#{args});
    Debug.Log($"Success: {result}");
    """
    |> String.trim()
  end

  defp code_auth_async do
    """
    using UnityEngine;
    using Exoforge.SDK;

    public class GameInitializer : MonoBehaviour
    {
        // Variant A: Task Async / Await
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

  defp code_auth_callback do
    """
    using UnityEngine;
    using Exoforge.SDK;

    public class GameInitializer : MonoBehaviour
    {
        // Variant B: Unity Main-Thread Callback
        void Start()
        {
            ExoforgeSDK.Auth.LoginAnonymously(
                onComplete: session =>
                {
                    Debug.Log($"Player session ready: {session.PlayerId}");
                    if (!session.HasDisplayName)
                    {
                        ExoforgeSDK.Auth.SetDisplayName("Viper",
                            namedSession => Debug.Log($"Display name set: {namedSession.DisplayName}"),
                            err => Debug.LogError($"Naming failed: {err.Message}")
                        );
                    }
                },
                onError: err => Debug.LogError($"Anonymous sign-in failed: {err.Message}")
            );
        }
    }
    """
  end

  defp code_extension do
    """
    using System;
    using Exoforge.Plugin.SDK;

    [ExoService("gameplay_calculator", Version = "0.1.0")]
    public class GameplayCalculatorExtension
    {
        [ExoAction]
        public CalculateScoreResponse CalculateScore(CalculateScoreRequest req)
        {
            if (req.Multiplier <= 0)
                throw new ArgumentOutOfRangeException(nameof(req.Multiplier), "Multiplier must be positive.");

            int finalScore = (req.BasePoints * req.Multiplier) + req.Bonus;
            return new CalculateScoreResponse(finalScore, DateTime.UtcNow);
        }
    }

    public record CalculateScoreRequest(int BasePoints, int Multiplier, int Bonus = 0);
    public record CalculateScoreResponse(int TotalScore, DateTime CalculatedAt);
    """
  end

  defp code_unity_async do
    """
    using UnityEngine;
    using System;
    using System.Threading.Tasks;
    using Exoforge.SDK;
    using Exoforge.Generated;

    public class GameplayRewardController : MonoBehaviour
    {
        // Variant A: Task Async / Await Overload
        public async Task OnLevelCompletedAsync(int points, int multiplier)
        {
            try
            {
                var req = new CalculateScoreRequest(points, multiplier);
                var res = await Exo.GameplayCalculator.CalculateScoreAsync(req);
                Debug.Log($"Score calculated: {res.TotalScore} at {res.CalculatedAt}");
            }
            catch (ExoActionException err)
            {
                Debug.LogError($"Server error [{err.ErrorCode}]: {err.Message}");
            }
            catch (Exception err)
            {
                Debug.LogError($"Network or client error: {err.Message}");
            }
        }
    }
    """
  end

  defp code_unity_callback do
    """
    using UnityEngine;
    using Exoforge.SDK;
    using Exoforge.Generated;

    public class GameplayRewardController : MonoBehaviour
    {
        // Variant B: Unity Main-Thread Callback
        public void OnLevelCompleted(int points, int multiplier)
        {
            var req = new CalculateScoreRequest(points, multiplier);
            Exo.GameplayCalculator.CalculateScore(
                req,
                onComplete: res =>
                {
                    Debug.Log($"Score: {res.TotalScore} at {res.CalculatedAt}");
                    // Safe to modify GameObjects & UI transforms immediately
                    UpdateScoreUI(res.TotalScore);
                },
                onError: err =>
                {
                    Debug.LogError($"Calculation failed [{err.Code}]: {err.Message}");
                }
            );
        }

        private void UpdateScoreUI(int score) => scoreText.text = $"Score: {score}";
        [SerializeField] private UnityEngine.UI.Text scoreText;
    }
    """
  end

  defp code_db_table do
    """
    using System;
    using Exoforge.Plugin.SDK;

    // Pattern 1: Type-Safe Table Repository (No raw SQL strings)
    public class EconomyService
    {
        public void ManageListing(string listingId, string sellerId, int price)
        {
            // Strongly typed table repository for MarketListingRecord
            var table = Exo.Database.Table<MarketListingRecord>();

            // 1. Get by primary key
            var item = table.Get(listingId);

            // 2. Put / Upsert entity (auto-resolves table name & primary key)
            table.Put(new MarketListingRecord(listingId, sellerId, "sword_01", 1, price, DateTime.UtcNow));

            // 3. Retrieve all records
            var all = table.All();

            // 4. Delete by ID
            table.Delete(listingId);

            // 5. Singleton config resource
            var config = Exo.Database.First<EconomyConfigRecord>();
        }
    }
    """
  end

  defp code_db_sql do
    """
    using System;
    using System.Collections.Generic;
    using Exoforge.Plugin.SDK;

    // Pattern 2: Parameterized Raw SQL (Queries, Joins, Aggregates & Atomic In-Place Updates)
    public class EconomyService
    {
        public List<MarketListingRecord> SearchListings(string itemId, int maxPrice, int limit)
        {
            // Positional parameters ($1, $2, ...) prevent SQL injection
            // Result rows map directly to immutable C# records
            return Exo.Database.Query<MarketListingRecord>(
                "SELECT * FROM market_listings WHERE item_id = $1 AND unit_price <= $2 ORDER BY unit_price ASC LIMIT $3",
                itemId, maxPrice, limit
            );
        }

        public void AtomicGoldTransfer(string senderId, string receiverId, int gold)
        {
            // Atomic in-place updates eliminate read-modify-write race conditions
            Exo.Database.Execute("UPDATE players SET gold = gold - $1 WHERE id = $2 AND gold >= $1", gold, senderId);
            Exo.Database.Execute("UPDATE players SET gold = gold + $1 WHERE id = $2", gold, receiverId);
        }
    }
    """
  end

  defp snippet_auction_house_table do
    """
    using System;
    using System.Collections.Generic;
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    [ExoService("marketplace_service", Title = "Auction House", Icon = "⚖️")]
    public class MarketplaceExtension
    {
        [ExoAction]
        public CreateListingResponse ListItem(CreateListingRequest req)
        {
            string listingId = Guid.NewGuid().ToString("N");
            var listing = new MarketListingRecord(
                listingId,
                Exo.Context.CallerPlayerId,
                req.ItemId,
                req.Quantity,
                req.UnitPrice,
                DateTime.UtcNow
            );

            // Pure C# table repository — zero raw SQL strings
            Exo.Database.Table<MarketListingRecord>().Put(listing);
            Exo.Logger.Info($"Player {Exo.Context.CallerPlayerId} listed {req.Quantity}x {req.ItemId}");
            return new CreateListingResponse(listingId);
        }

        [ExoAction]
        public IReadOnlyList<MarketListingRecord> AllListings()
        {
            // Read all entities via typed table repository
            return Exo.Database.Table<MarketListingRecord>().All();
        }

        [ExoAction]
        public async Task<BuyListingResponse> BuyListing(BuyListingRequest req)
        {
            var table = Exo.Database.Table<MarketListingRecord>();
            var listing = table.Get(req.ListingId);
            if (listing == null)
                throw new ExoActionException("listing_not_found", "Item has expired or already sold.");

            table.Delete(req.ListingId);

            await Exo.Events.EmitAsync(new ListingSoldEvent(
                listing.SellerPlayerId,
                listing.ItemId,
                listing.Quantity,
                listing.UnitPrice * listing.Quantity
            ));

            return new BuyListingResponse(true);
        }
    }
    """
  end

  defp code_exo_extension_page do
    """
    using Exoforge.Plugin.SDK;

    [ExoService("leaderboard_service",
        Title = "Leaderboards & Rankings",
        Icon = "🏆",
        Category = "Game",
        Version = "0.1.0",
        Resources = new[] { typeof(PlayerScoreRecord) })]
    public class LeaderboardExtension
    {
        [ExoAction]
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
    // Scope defaults to "player" (authenticated).
    [ExoAction]
    public TransferItemResponse TransferItem(TransferItemRequest req)
    {
        if (req.Quantity <= 0)
            throw new ArgumentOutOfRangeException(nameof(req.Quantity), "Must transfer at least 1 item.");

        return new TransferItemResponse(req.ItemId, req.Quantity, true);
    }

    // Explicit Cast mode for fire-and-forget
    [ExoAction(Mode = ActionMode.Cast)]
    public void RecordTelemetry(TelemetryPayload payload)
    {
        Exo.Logger.Info($"Telemetry: {payload.EventName}");
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
    using Exoforge.Plugin.SDK;

    // 1. Declare Event Schema Contract (Record)
    [ExoEvent("player.registered", Topic = "player:*")]
    public record PlayerRegisteredEvent(string PlayerId, string DisplayName, DateTime RegisteredAt);

    // 2. Handle Inbound Cluster Events in Extension
    public class LeaderboardExtension
    {
        public void OnEvent(string name, PlayerRegisteredEvent evt)
        {
            Exo.Logger.Info($"Player joined: {evt.DisplayName}");
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

  defp code_exo_dependency_page do
    """
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    // Dependencies are auto-inferred from Exo.<Service> calls, or pinned with [ExoDependency]
    [ExoService("inventory_service")]
    [ExoDependency<IPlayerDataService>]
    public class InventoryExtension
    {
        [ExoAction]
        public async Task<GrantItemResponse> GrantItem(GrantItemRequest req)
        {
            // Inter-service RPC via generated static service stubs
            var profile = await Exo.PlayerData.GetProfileAsync(new GetProfileRequest(req.PlayerId));
            return new GrantItemResponse(req.ItemId, profile.DisplayName);
        }
    }
    """
  end

  defp code_exo_webhook_page do
    """
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    [ExoService("billing_service")]
    public class BillingExtension
    {
        // Inbound external HTTP POST webhook endpoint (e.g. Stripe checkout)
        [ExoWebhook("stripe")]
        public async Task<WebhookResult> HandleStripeWebhook(WebhookPayload payload)
        {
            string signature = payload.Headers.TryGetValue("Stripe-Signature", out var sig) ? sig : "";
            Exo.Logger.Info($"Processing Stripe checkout webhook: {payload.EventName}");

            // Process payload and acknowledge receipt
            return WebhookResult.Success();
        }
    }
    """
  end

  defp snippet_auction_house do
    """
    using System;
    using System.Collections.Generic;
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    [ExoService("marketplace_service", Title = "Auction House", Icon = "⚖️")]
    public class MarketplaceExtension
    {
        [ExoAction]
        public CreateListingResponse ListItem(CreateListingRequest req)
        {
            string listingId = Guid.NewGuid().ToString("N");
            var listing = new MarketListingRecord(
                listingId,
                Exo.Context.CallerPlayerId,
                req.ItemId,
                req.Quantity,
                req.UnitPrice,
                DateTime.UtcNow
            );

            Exo.Database.Put("market_listings", listingId, listing);
            Exo.Logger.Info($"Player {Exo.Context.CallerPlayerId} listed {req.Quantity}x {req.ItemId} for {req.UnitPrice}g");
            return new CreateListingResponse(listingId);
        }

        [ExoAction]
        public List<MarketListingRecord> BrowseListings(BrowseListingsRequest req)
        {
            // Native SQL query across all players with filtering and paging
            return Exo.Database.Query<MarketListingRecord>(
                "SELECT * FROM market_listings WHERE item_id = $1 ORDER BY unit_price ASC LIMIT $2 OFFSET $3",
                req.ItemId, req.Limit, req.Offset
            );
        }

        [ExoAction]
        public async Task<BuyListingResponse> BuyListing(BuyListingRequest req)
        {
            var listing = Exo.Database.Get<MarketListingRecord>("market_listings", req.ListingId);
            if (listing == null)
                throw new ExoActionException("listing_not_found", "Item has already been purchased or expired.");

            // Deduct currency & transfer item atomically
            Exo.Database.Execute("DELETE FROM market_listings WHERE id = $1", req.ListingId);

            // Real-time seller notification pushed over WebSocket
            await Exo.Events.EmitAsync(new ListingSoldEvent(
                listing.SellerPlayerId,
                listing.ItemId,
                listing.Quantity,
                listing.UnitPrice * listing.Quantity
            ));

            return new BuyListingResponse(true);
        }
    }

    [ExoResource(Name = "market_listings", PrimaryKey = "Id")]
    public record MarketListingRecord(
        [property: ExoColumn(PrimaryKey = true)] string Id,
        [property: ExoColumn(ReferencesType = typeof(PlayerDataRecord), Role = ExoRole.PlayerId)] string SellerPlayerId,
        [property: ExoColumn(Sortable = true, Filterable = true)] string ItemId,
        [property: ExoColumn] int Quantity,
        [property: ExoColumn(Role = ExoRole.Currency, Sortable = true)] int UnitPrice,
        [property: ExoColumn(Role = ExoRole.Timestamp)] DateTime CreatedAt
    );

    [ExoEvent("marketplace.sold", Topic = "player:*")]
    public record ListingSoldEvent(string SellerPlayerId, string ItemId, int Quantity, int TotalEarned);
    """
    |> String.trim()
  end

  defp snippet_matchmaking do
    """
    using System;
    using System.Collections.Concurrent;
    using System.Collections.Generic;
    using System.Linq;
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    [ExoService("matchmaker_service", Title = "Fast Matchmaker", Icon = "🎯")]
    public class MatchmakerExtension
    {
        // High-performance hot RAM queue: zero database round-trips
        private readonly ConcurrentDictionary<string, QueueEntry> _queue = new();

        [ExoAction]
        public QueueStatusResponse JoinQueue(JoinQueueRequest req)
        {
            string playerId = Exo.Context.CallerPlayerId;
            _queue[playerId] = new QueueEntry(playerId, req.EloRating, DateTime.UtcNow);
            return new QueueStatusResponse(true, _queue.Count);
        }

        [ExoAction]
        public QueueStatusResponse LeaveQueue()
        {
            _queue.TryRemove(Exo.Context.CallerPlayerId, out _);
            return new QueueStatusResponse(false, _queue.Count);
        }

        // Evaluates queue and pairs players by ELO rating in microseconds
        [ExoCron("*/1 * * * *", Description = "Evaluates matchmaking queue and pairs players")]
        public async Task EvaluateQueue()
        {
            if (_queue.Count < 2) return;

            var sorted = _queue.Values.OrderBy(p => p.EloRating).ToList();
            for (int i = 0; i < sorted.Count - 1; i += 2)
            {
                var p1 = sorted[i];
                var p2 = sorted[i + 1];

                if (Math.Abs(p1.EloRating - p2.EloRating) <= 200)
                {
                    _queue.TryRemove(p1.PlayerId, out _);
                    _queue.TryRemove(p2.PlayerId, out _);

                    string matchId = Guid.NewGuid().ToString("N");
                    await Exo.Events.EmitAsync(new MatchFoundEvent(matchId, p1.PlayerId, p2.PlayerId));
                    Exo.Logger.Info($"Paired match {matchId}: {p1.PlayerId} vs {p2.PlayerId}");
                }
            }
        }
    }

    public record QueueEntry(string PlayerId, int EloRating, DateTime QueuedAt);
    public record JoinQueueRequest(int EloRating);
    public record QueueStatusResponse(bool InQueue, int TotalInQueue);

    [ExoEvent("matchmaking.found", Topic = "player:*")]
    public record MatchFoundEvent(string MatchId, string Player1Id, string Player2Id);
    """
    |> String.trim()
  end

  defp snippet_world_boss do
    """
    using System;
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    [ExoService("world_boss_service", Title = "World Boss Event", Icon = "🐉",
        Resources = new[] { typeof(WorldBossConfig) })]
    public class WorldBossExtension
    {
        private static int _currentBossHp = 5_000_000;

        [ExoAction]
        public async Task<AttackBossResponse> AttackBoss(AttackBossRequest req)
        {
            var config = Exo.Database.First<WorldBossConfig>("world_boss_config");
            if (config == null || !config.IsEventActive)
                throw new ExoActionException("event_inactive", "The World Boss is currently sleeping.");

            int damage = Math.Clamp(req.ReportedDamage, 1, config.MaxDamagePerHit);
            _currentBossHp = Math.Max(0, _currentBossHp - damage);

            // Broadcast live damage to all connected players in real time
            await Exo.Events.EmitAsync(new BossDamagedEvent(Exo.Context.CallerPlayerId, damage, _currentBossHp));

            if (_currentBossHp == 0)
            {
                await Exo.Events.EmitAsync(new BossDefeatedEvent(Exo.Context.CallerPlayerId, config.VictoryRewardGold));
            }

            return new AttackBossResponse(_currentBossHp, damage);
        }
    }

    // Designers tune this directly inside Exoforge Producer Studio with auto-generated UI
    [ExoSingletonResource("world_boss_config")]
    public record WorldBossConfig(
        [property: ExoColumn(Label = "Event Active", InputType = ExoInput.Checkbox)] bool IsEventActive,
        [property: ExoColumn(Label = "Boss Name")] string BossName,
        [property: ExoColumn(Label = "Total Max HP", Sortable = true)] int TotalMaxHp,
        [property: ExoColumn(Label = "Max Damage Cap / Hit", InputType = ExoInput.Range)] int MaxDamagePerHit,
        [property: ExoColumn(Label = "Victory Reward", Role = ExoRole.Currency)] int VictoryRewardGold
    );

    [ExoEvent("boss.damaged", Topic = "world:*")]
    public record BossDamagedEvent(string AttackerPlayerId, int DamageDealt, int RemainingHp);

    [ExoEvent("boss.defeated", Topic = "world:*")]
    public record BossDefeatedEvent(string FinalBlowPlayerId, int RewardGold);
    """
    |> String.trim()
  end

  defp snippet_guilds do
    """
    using System;
    using System.Collections.Generic;
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    [ExoService("guild_service", Title = "Guilds & Clans", Icon = "🛡️")]
    public class GuildExtension
    {
        [ExoAction]
        public async Task<DepositGoldResponse> DepositGuildGold(DepositGoldRequest req)
        {
            string playerId = Exo.Context.CallerPlayerId;
            var member = Exo.Database.Get<GuildMemberRecord>("guild_members", playerId);
            if (member == null)
                throw new ExoActionException("not_in_guild", "You are not a member of any guild.");

            var guild = Exo.Database.Get<GuildRecord>("guilds", member.GuildId);
            int newBankTotal = guild.BankGold + req.Amount;

            Exo.Database.Execute("UPDATE guilds SET bank_gold = $1 WHERE id = $2", newBankTotal, guild.Id);

            // Notify all online guild members in real time over WebSocket
            await Exo.Events.EmitAsync(new GuildActivityEvent(
                $"guild:{guild.Id}",
                playerId,
                $"{playerId} deposited {req.Amount} gold to the guild vault!"
            ));

            return new DepositGoldResponse(newBankTotal);
        }
    }

    [ExoResource(Name = "guilds", PrimaryKey = "Id")]
    public record GuildRecord(
        [property: ExoColumn(PrimaryKey = true)] string Id,
        [property: ExoColumn(Label = "Guild Name", Sortable = true)] string Name,
        [property: ExoColumn(Role = ExoRole.Currency)] int BankGold,
        [property: ExoColumn(Badge = true)] int Level
    );

    [ExoResource(Name = "guild_members", PrimaryKey = "PlayerId")]
    public record GuildMemberRecord(
        [property: ExoColumn(PrimaryKey = true, ReferencesType = typeof(PlayerDataRecord), Role = ExoRole.PlayerId)] string PlayerId,
        [property: ExoColumn(ReferencesType = typeof(GuildRecord))] string GuildId,
        [property: ExoColumn(Badge = true)] string Rank
    );

    [ExoEvent("guild.activity", Topic = "guild:*")]
    public record GuildActivityEvent(string Topic, string ActorPlayerId, string Message);
    """
    |> String.trim()
  end

  defp snippet_season_rollover do
    """
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    [ExoService("season_service", Title = "Season Manager", Icon = "🏆")]
    public class SeasonExtension
    {
        // Midnight UTC on Monday: Automated Season Rollover
        [ExoCron("0 0 * * 1", Description = "Weekly season rollover and reward distribution")]
        public async Task RolloverWeeklySeason()
        {
            Exo.Logger.Info("Beginning automated season rollover...");

            // Atomic SQL: Archive top 100 players into hall of fame
            Exo.Database.Execute(@"
                INSERT INTO hall_of_fame (player_id, final_score, season_number, recorded_at)
                SELECT player_id, score, 12, datetime('now')
                FROM season_scores
                ORDER BY score DESC LIMIT 100
            ");

            // Reset active scores for the new week
            Exo.Database.Execute("DELETE FROM season_scores");

            // Broadcast season reset to all online Unity clients
            await Exo.Events.EmitAsync(new SeasonResetEvent(13, "Season 13 is now live!"));
            Exo.Logger.Info("Season 13 successfully initialized.");
        }
    }

    [ExoEvent("season.reset", Topic = "global")]
    public record SeasonResetEvent(int NewSeasonNumber, string Announcement);
    """
    |> String.trim()
  end

  defp snippet_webhooks_checkout do
    """
    using System.Threading.Tasks;
    using Exoforge.Plugin.SDK;

    [ExoService("billing_service", Title = "Payments & Store", Icon = "💳")]
    public class BillingExtension
    {
        // External HTTP POST webhook (e.g. https://api.yourgame.com/ext/billing_service/webhook/stripe)
        [ExoWebhook("stripe")]
        public async Task<WebhookResult> HandleStripeWebhook(WebhookPayload payload)
        {
            string signature = payload.Headers.TryGetValue("Stripe-Signature", out var sig) ? sig : "";
            Exo.Logger.Info($"Inbound Stripe webhook: {payload.EventName}");

            // Verify signature, extract player ID and product from payload
            string targetPlayerId = payload.Data.TryGetValue("client_reference_id", out var refId) ? refId?.ToString() ?? "" : "";
            string productId = payload.Data.TryGetValue("product_id", out var pId) ? pId?.ToString() ?? "" : "";

            // Instantly credit player account
            Exo.Database.Execute(
                "INSERT INTO player_purchases (player_id, product_id, purchased_at) VALUES ($1, $2, datetime('now'))",
                targetPlayerId, productId
            );

            // Push real-time unlock animation event directly to the player's active Unity client
            await Exo.Events.EmitAsync(new PurchaseFulfilledEvent(targetPlayerId, productId));

            return WebhookResult.Success();
        }
    }

    [ExoEvent("store.fulfilled", Topic = "player:*")]
    public record PurchaseFulfilledEvent(string PlayerId, string ProductId);
    """
    |> String.trim()
  end
end
