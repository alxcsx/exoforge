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

    assigns = assign(assigns, :action_catalog, action_catalog)

    ~H"""
    <div class="space-y-6 max-w-6xl mx-auto pb-16 print:p-0 print:max-w-none print:pb-0">
      <!-- Print Stylesheet -->
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
        <div class="relative z-10 space-y-4 max-w-3xl">
          <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/10 backdrop-blur border border-white/10 text-xs font-bold text-primary-200">
            <span>⚡</span>
            <span>Developer Quickstart &amp; Architecture Reference</span>
          </div>
          <h1 class="text-3xl lg:text-4xl font-extrabold tracking-tight text-white leading-tight">
            From Zero to Live Online Multiplayer Features in 60 Seconds
          </h1>
          <p class="text-base text-gray-300 leading-relaxed">
            Exoforge allows Unity and game developers to write clean, strongly-typed native C# extensions that compile locally, hot-reload into distributed Erlang/OTP nodes, and sync seamlessly into client code without manual networking boilerplate.
          </p>

          <!-- Flow Stepper Pills -->
          <div class="print:hidden pt-4 flex flex-wrap items-center gap-2 text-xs font-semibold">
            <a href="#step-auth" class="px-3 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 transition-colors flex items-center gap-1.5 text-white">
              <span class="w-5 h-5 rounded-full bg-primary-500 text-white flex items-center justify-center text-[10px] font-black">1</span>
              <span>Connect &amp; Auth</span>
            </a>
            <span class="text-white/40">➔</span>
            <a href="#step-scaffold" class="px-3 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 transition-colors flex items-center gap-1.5 text-white">
              <span class="w-5 h-5 rounded-full bg-primary-500 text-white flex items-center justify-center text-[10px] font-black">2</span>
              <span>Scaffold Extension</span>
            </a>
            <span class="text-white/40">➔</span>
            <a href="#step-deploy" class="px-3 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 transition-colors flex items-center gap-1.5 text-white">
              <span class="w-5 h-5 rounded-full bg-primary-500 text-white flex items-center justify-center text-[10px] font-black">3</span>
              <span>Build &amp; Deploy</span>
            </a>
            <span class="text-white/40">➔</span>
            <a href="#step-stubs" class="px-3 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 transition-colors flex items-center gap-1.5 text-white">
              <span class="w-5 h-5 rounded-full bg-primary-500 text-white flex items-center justify-center text-[10px] font-black">4</span>
              <span>Sync Client Stubs</span>
            </a>
            <span class="text-white/40">➔</span>
            <a href="#step-gameplay" class="px-3 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 transition-colors flex items-center gap-1.5 text-white">
              <span class="w-5 h-5 rounded-full bg-primary-500 text-white flex items-center justify-center text-[10px] font-black">5</span>
              <span>Call from Unity</span>
            </a>
            <span class="text-white/40">|</span>
            <a href="#catalog" class="px-3 py-1.5 rounded-xl bg-purple-500/20 hover:bg-purple-500/30 text-purple-200 border border-purple-500/30 transition-colors flex items-center gap-1.5">
              <span>📖</span>
              <span>Live API Reference</span>
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
            Extensions execute as native .NET processes under OTP supervision. Use modern C# records, type-safe APIs, and throw canonical <code class="font-mono text-primary-700 bg-primary-50 px-1 py-0.5 rounded">ExoActionException</code>.
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
            <ol class="list-decimal list-inside space-y-2 text-gray-600 leading-relaxed">
              <li>In your game's first scene, click <strong class="text-gray-900">Exoforge ▸ Add Exoforge to Scene</strong>. This creates the persistent <code class="font-mono bg-gray-100 px-1 py-0.5 rounded">Exoforge.prefab</code>.</li>
              <li>By default, <code class="font-mono bg-gray-100 px-1 py-0.5 rounded text-primary-700">anonymousOnConnect: true</code> automatically mints an anonymous player session using the unique device identifier (<code class="font-mono bg-gray-100 px-1 py-0.5 rounded">ExoDeviceId.Get()</code>) without requiring passwords.</li>
              <li>Or call <code class="font-mono bg-gray-100 px-1 py-0.5 rounded text-primary-700 font-bold">Exoforge.Auth.LoginAnonymously()</code> programmatically from script.</li>
              <li>Once authenticated, the session is cached locally in <code class="font-mono bg-gray-100 px-1 py-0.5 rounded">ExoTokenStore</code> and <code class="font-mono bg-gray-100 px-1 py-0.5 rounded">Exoforge.IsReady</code> becomes true.</li>
            </ol>
          </div>

          <div class="space-y-2">
            <div class="flex items-center justify-between text-gray-400 font-bold text-xs pb-1">
              <span>Unity Anonymous Sign-In</span>
              <span class="text-emerald-400 font-mono text-[10px]">C# Client</span>
            </div>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_auth())) %></code></pre>
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
          <p class="leading-relaxed">
            In Unity Studio, navigate to the <strong class="text-gray-900">Extensions</strong> tab and click <strong class="text-gray-900">⚡ New Extension...</strong> (or run <code class="font-mono bg-gray-100 text-primary-700 px-1.5 py-0.5 rounded font-bold">exo extension new &lt;name&gt;</code>).
            This creates an isolated solution in <code class="font-mono bg-gray-100 px-1.5 py-0.5 rounded">Exoforge/extensions/&lt;name&gt;/</code>.
          </p>

          <div class="space-y-2">
            <div class="flex items-center justify-between text-gray-400 font-bold text-xs pb-1">
              <span>Exoforge/extensions/gameplay_calculator/src/GameplayCalculatorExtension.cs</span>
              <span class="text-xs text-primary-400 font-mono">C# 12 / .NET 9+</span>
            </div>
            <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_extension())) %></code></pre>
          </div>

          <!-- Tree-Shaking Architectural Callout -->
          <div class="p-5 rounded-2xl bg-amber-950/30 border border-amber-500/40 text-amber-200 space-y-2 print:bg-amber-50 print:text-amber-900 print:border-amber-300">
            <div class="flex items-center gap-2 font-bold text-sm text-amber-300 print:text-amber-900">
              <span>✂️</span>
              <span>Tree-Shaking &amp; Native Compilation Architecture</span>
            </div>
            <p class="leading-relaxed text-xs text-amber-200/90 print:text-amber-800">
              When publishing an extension, Exoforge leverages <strong>.NET IL Trimming &amp; Ahead-Of-Time (AOT) tree-shaking</strong>. All unused base class library (BCL) methods and reflection overhead are stripped at compile time.
            </p>
            <ul class="list-disc list-inside space-y-1 text-xs text-amber-200/80 print:text-amber-800 pl-1">
              <li><strong>Zero Reflection at Runtime:</strong> Contracts, actions, and parameter types are analyzed and serialized into a lightweight <code class="font-mono bg-amber-900/60 text-amber-200 print:bg-amber-100 print:text-amber-900 px-1 py-0.5 rounded">manifest.json</code> at build time.</li>
              <li><strong>Minimal Memory Footprint:</strong> Stripped extension binaries load in milliseconds with predictable memory usage under Erlang/OTP supervision.</li>
              <li><strong>Binary Isolation:</strong> Each extension operates in an isolated worker process without polluting cluster dependencies.</li>
            </ul>
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
          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-2">
            <h4 class="font-bold text-gray-900 text-sm flex items-center gap-2">
              <span>🚀</span>
              <span>1-Click Deploy in Studio</span>
            </h4>
            <p class="leading-relaxed">
              In Exoforge Studio or the Extensions Window, find your extension card and click <strong class="text-gray-900">🚀 Build &amp; Deploy</strong>.
              Your local .NET compiler publishes the binary and uploads it directly to the cluster.
            </p>
          </div>

          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200/80 space-y-2">
            <h4 class="font-bold text-gray-900 text-sm flex items-center gap-2">
              <span>💻</span>
              <span>CLI Deployment</span>
            </h4>
            <pre class="bg-gray-900 text-emerald-400 p-3 rounded-xl font-mono text-[11px] overflow-x-auto"><code>exo extension push gameplay_calculator&#10;exo extension logs gameplay_calculator</code></pre>
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
          <p>
            Whenever an extension action or schema changes, click <strong class="text-gray-900">🔄 Sync Client</strong> in the Unity toolbar (or run <code class="font-mono bg-gray-100 text-primary-700 px-1 py-0.5 rounded font-bold">exo sync</code>).
          </p>

          <div class="p-4 rounded-2xl bg-purple-950/30 border border-purple-500/40 text-purple-200 space-y-1.5 print:bg-purple-50 print:text-purple-900 print:border-purple-300">
            <span class="font-bold text-xs text-purple-300 print:text-purple-900">What this does:</span>
            <p class="text-purple-200/90 print:text-purple-800 text-[11px] leading-relaxed">
              It queries live cluster contracts and generates <code class="font-mono bg-purple-900/60 print:bg-purple-100 px-1 py-0.5 rounded">Assets/Exoforge/Generated/ExoforgeServices.g.cs</code>.
              Your Unity project immediately gains strongly-typed methods for every action (both main-thread callbacks and async overloads) and typed models for every return record!
            </p>
          </div>
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

        <div class="space-y-2">
          <div class="flex items-center justify-between text-gray-400 font-bold text-xs pb-1">
            <span>Assets/Scripts/GameplayRewardController.cs</span>
            <span class="text-xs text-emerald-400 font-mono">Unity C#</span>
          </div>
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_unity())) %></code></pre>
        </div>
      </section>

      <!-- DYNAMIC API CATALOG EMBED -->
      <.subpage_catalog action_catalog={@action_catalog} />
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
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoExtension]</h2>
                <span class="px-2 py-0.5 rounded-full bg-indigo-100 text-indigo-800 text-[10px] font-bold uppercase tracking-wider">Service Root</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Identifies a C# class as a cluster-supervised native headless service.</p>
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
                  <th class="py-2 px-3">Default</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">id (positional)</td>
                  <td class="py-2 px-3 text-primary-700">string</td>
                  <td class="py-2 px-3 text-gray-400">Required</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Unique identifier of the extension (e.g. <code class="font-mono text-primary-700">"inventory_service"</code>). Used for RPC routing and log grouping.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Version</td>
                  <td class="py-2 px-3 text-primary-700">string</td>
                  <td class="py-2 px-3 text-gray-400">"0.1.0"</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Semantic version string. Checked during client synchronization and hot-reload.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Resources</td>
                  <td class="py-2 px-3 text-primary-700">Type[]</td>
                  <td class="py-2 px-3 text-gray-400">[]</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Array of C# record types managed by this extension. Auto-creates database schemas and exposes entries in the Studio dashboard.</td>
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
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_extension_page())) %></code></pre>
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
            Source: <strong class="text-amber-700">Exoforge.Plugin.SDK</strong> (routed via <code class="text-gray-800">exoforge_std_ws</code>)
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            Decorate any public method with <code class="font-mono text-amber-700 font-bold">[ExoAction]</code> to make it callable from Unity clients, Web UI, and CLI. Method arguments are automatically deserialized from incoming payloads, and return values are serialized back to the caller.
          </p>

          <div class="overflow-x-auto rounded-xl border border-gray-200 mt-3">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Property</th>
                  <th class="py-2 px-3">Type</th>
                  <th class="py-2 px-3">Default</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Mode</td>
                  <td class="py-2 px-3 text-primary-700">string</td>
                  <td class="py-2 px-3 text-gray-400">"sync"</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600"><code class="font-mono text-primary-700">"sync"</code> awaits execution and returns a result payload. <code class="font-mono text-primary-700">"async"</code> triggers background processing and returns immediately.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Scope</td>
                  <td class="py-2 px-3 text-primary-700">string</td>
                  <td class="py-2 px-3 text-gray-400">"guest"</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Minimum authorization scope needed to invoke (<code class="font-mono text-primary-700">"guest"</code>, <code class="font-mono text-primary-700">"player"</code>, <code class="font-mono text-primary-700">"admin"</code>). The cluster enforces this before invoking the extension.</td>
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
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_action_page())) %></code></pre>
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
              <p class="text-xs text-gray-500 mt-0.5">Executes scheduled recurring background jobs via the Erlang/OTP cluster scheduler.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-amber-700">Exoforge.Plugin.SDK</strong> (scheduled by cluster worker runtime)
          </div>
        </div>

        <div class="space-y-2">
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_cron_page())) %></code></pre>
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
              <p class="text-xs text-gray-500 mt-0.5">Subscribes to cluster-wide real-time events published via EventDispatcher.</p>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_event_page())) %></code></pre>
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_event_unity())) %></code></pre>
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
                <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoResource]</h2>
                <span class="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 text-[10px] font-bold uppercase tracking-wider">Database Entity</span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">Declares a typed entity record mapped directly to SQLite / PostgreSQL storage.</p>
            </div>
          </div>
          <div class="text-[11px] font-mono bg-gray-100 px-3 py-1.5 rounded-xl text-gray-600 self-start sm:self-auto">
            Source: <strong class="text-emerald-700">Exoforge.Plugin.SDK</strong> (managed by <code class="text-gray-800">exoforge_std_resources</code>)
          </div>
        </div>

        <div class="p-4 rounded-2xl bg-emerald-50 border border-emerald-200/80 text-emerald-900 text-xs space-y-1">
          <div class="font-bold flex items-center gap-1.5 text-emerald-800 text-[11px] uppercase tracking-wider">
            <span>✨</span> <span>Automatic Table Name Inference</span>
          </div>
          <p class="leading-relaxed">
            By default, resource record classes map directly to database tables without manual migrations.
          </p>
        </div>

        <div class="space-y-2">
          <pre class="bg-gray-950 text-gray-200 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto border border-gray-800"><code><%= Phoenix.HTML.raw(Markdown.highlight_csharp(code_exo_resource_page())) %></code></pre>
        </div>
      </section>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: ARCHITECTURE
  # ===========================================================================
  defp subpage_architecture(assigns) do
    content =
      case Exoforge.Std.Docs.get_chapter(%{id: "03_architecture"}) do
        {:ok, %{chapter: %{content: raw}}} -> raw
        _ -> "# Exoforge Architecture\n\nNative C# Process runtime with OTP Supervision."
      end

    assigns = assign(assigns, :html_content, Markdown.to_html(content))

    ~H"""
    <div class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6 print:border-gray-300 print:shadow-none">
      <div class="prose prose-sm max-w-none text-gray-800">
        <%= @html_content %>
      </div>
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
            <details class="group bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden transition-all duration-200 print:border-gray-300 print:shadow-none print:break-inside-avoid" open>
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
                  <details class="group/act bg-white rounded-xl border border-gray-200/80 p-4 space-y-3 shadow-2xs transition-all print:border-gray-300 print:break-inside-avoid" open>
                    <summary class="flex items-center justify-between gap-2 cursor-pointer select-none list-none">
                      <div class="flex items-center gap-2">
                        <span class="font-bold text-primary-800 text-xs font-mono">
                          .<%= act.name %>()
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
        [ExoAction(Mode = "sync")]
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
    using Exoforge.SDK;
    using Exoforge.Generated;

    public class GameplayRewardController : MonoBehaviour
    {
        void OnLevelCompleted(int points, int multiplier)
        {
            var client = ExoforgeSDK.Client.GameplayCalculator();

            client.CalculateScore(
                new CalculateScoreRequest(points, multiplier),
                onComplete: res => Debug.Log($"Final Score: {res.TotalScore}"),
                onError: err => Debug.LogError($"Calculation failed: {err.Message}")
            );
        }
    }
    """
  end

  defp code_exo_extension_page do
    """
    using Exoforge.SDK;

    [ExoExtension("leaderboard_service", Version = "1.0.0", Resources = new[] { typeof(ScoreEntry) })]
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
    [ExoAction(Mode = "sync", Scope = "player")]
    public TransferItemResponse TransferItem(TransferItemRequest req)
    {
        if (req.Quantity <= 0)
            throw new ExoActionException("invalid_quantity", "Must transfer at least 1 item.");

        return new TransferItemResponse(req.ItemId, req.Quantity, true);
    }
    """
  end

  defp code_exo_cron_page do
    """
    [ExoCron("0 0 * * *")]
    public void RolloverDailyLeaderboards()
    {
        // Executes automatically at midnight UTC under cluster supervisor
    }
    """
  end

  defp code_exo_event_page do
    """
    [ExoEvent("player.registered")]
    public void OnPlayerRegistered(PlayerRegisteredEvent evt)
    {
        // Handle incoming cluster broadcast
    }
    """
  end

  defp code_exo_event_unity do
    """
    ExoforgeSDK.Events.Subscribe<PlayerRegisteredEvent>("player.registered", evt => {
        Debug.Log($"Welcome {evt.DisplayName}!");
    });
    """
  end

  defp code_exo_resource_page do
    """
    [ExoResource(Name = "player_scores", PrimaryKey = "id")]
    public record PlayerScoreRecord(string Id, string PlayerId, int Score, DateTime CreatedAt);
    """
  end
end
