defmodule Exoforge.Std.Dashboard.Guide do
  @moduledoc """
  Comprehensive Quickstart Guide, Attribute Reference & Live API Reference for Exoforge developers.
  Renders interactive steps, dedicated attribute deep dives ([ExoAction], [ExoEvent], [ExoResource], [ExoExtension]),
  copyable C# snippets, and a live catalog of all cluster services, actions, and resources.
  """
  use Phoenix.Component

  attr(:action_catalog, :list, default: [])
  attr(:extensions, :list, default: [])
  attr(:project_name, :string, default: "Game")
  attr(:studio_name, :string, default: "Studio")
  attr(:subpage, :string, default: "flow")

  def view(assigns) do
    ~H"""
    <div class="space-y-6 max-w-6xl mx-auto pb-16">
      <!-- Top Guide Navigation Sub-Menu -->
      <div class="flex flex-wrap items-center justify-between gap-3 bg-white p-3 rounded-2xl border border-gray-200/90 shadow-2xs">
        <div class="flex items-center gap-2">
          <span class="w-8 h-8 rounded-xl bg-primary-50 text-primary-700 flex items-center justify-center font-bold text-sm">
            📖
          </span>
          <div>
            <span class="font-extrabold text-sm text-gray-900 block leading-tight">Exoforge Developer Guide</span>
            <span class="text-[10px] text-gray-400">Architecture, SDK attributes &amp; live cluster catalog</span>
          </div>
        </div>

        <!-- Subpage Pills -->
        <div class="flex flex-wrap items-center gap-1.5 p-1 bg-gray-100/80 rounded-xl text-xs font-semibold">
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
            phx-value-subpage="exo_extension"
            class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "exo_extension", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
          >
            <span>🧩</span>
            <span>[ExoExtension]</span>
          </button>
          <button
            type="button"
            phx-click="set_guide_subpage"
            phx-value-subpage="exo_action"
            class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "exo_action", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
          >
            <span>⚡</span>
            <span>[ExoAction]</span>
          </button>
          <button
            type="button"
            phx-click="set_guide_subpage"
            phx-value-subpage="exo_event"
            class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "exo_event", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
          >
            <span>📡</span>
            <span>[ExoEvent]</span>
          </button>
          <button
            type="button"
            phx-click="set_guide_subpage"
            phx-value-subpage="exo_resource"
            class={"px-3 py-1.5 rounded-lg transition-all flex items-center gap-1.5 #{if @subpage == "exo_resource", do: "bg-white text-primary-700 shadow-xs font-bold", else: "text-gray-600 hover:text-gray-900"}"}
          >
            <span>💾</span>
            <span>[ExoResource]</span>
          </button>
        </div>
      </div>

      <%= case @subpage do %>
        <% "exo_extension" -> %>
          <.subpage_exo_extension />
        <% "exo_action" -> %>
          <.subpage_exo_action />
        <% "exo_event" -> %>
          <.subpage_exo_event />
        <% "exo_resource" -> %>
          <.subpage_exo_resource />
        <% _default -> %>
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
  # SUBPAGE: QUICKSTART FLOW & LIVE CATALOG
  # ===========================================================================
  defp subpage_flow(assigns) do
    ~H"""
    <div class="space-y-8">
      <!-- Hero Banner -->
      <div class="relative overflow-hidden bg-gradient-to-br from-gray-900 via-primary-950 to-indigo-950 text-white rounded-3xl p-8 lg:p-10 shadow-xl border border-primary-500/20">
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
          <div class="pt-4 flex flex-wrap items-center gap-2 text-xs font-semibold">
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
      <div class="grid grid-cols-1 md:grid-cols-3 gap-5">
        <div class="bg-white p-6 rounded-2xl border border-gray-200/90 shadow-sm space-y-2">
          <div class="w-10 h-10 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center text-lg font-bold">
            🔌
          </div>
          <h3 class="font-bold text-gray-900 text-sm">Native C# Headless Services</h3>
          <p class="text-xs text-gray-500 leading-relaxed">
            Extensions execute as native .NET processes under OTP supervision. Use modern C# records, type-safe APIs, and throw canonical <code class="font-mono text-primary-700 bg-primary-50 px-1 py-0.5 rounded">ExoActionException</code>.
          </p>
        </div>

        <div class="bg-white p-6 rounded-2xl border border-gray-200/90 shadow-sm space-y-2">
          <div class="w-10 h-10 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center text-lg font-bold">
            🔄
          </div>
          <h3 class="font-bold text-gray-900 text-sm">1-Click Hot Deployment</h3>
          <p class="text-xs text-gray-500 leading-relaxed">
            Build and hot-load extensions into the running server from Unity Studio or CLI without stopping player sessions or restarting clusters.
          </p>
        </div>

        <div class="bg-white p-6 rounded-2xl border border-gray-200/90 shadow-sm space-y-2">
          <div class="w-10 h-10 rounded-xl bg-purple-50 text-purple-600 flex items-center justify-center text-lg font-bold">
            🛡️
          </div>
          <h3 class="font-bold text-gray-900 text-sm">Familiar Unity Callbacks</h3>
          <p class="text-xs text-gray-500 leading-relaxed">
            Generated client stubs provide standard Unity main-thread callbacks (<code class="font-mono text-purple-700 bg-purple-50 px-1 py-0.5 rounded">onComplete</code> / <code class="font-mono text-purple-700 bg-purple-50 px-1 py-0.5 rounded">onError</code>) alongside async/await, with zero boilerplate.
          </p>
        </div>
      </div>

      <!-- STEP 1: Connect & Auth -->
      <section id="step-auth" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-2xl bg-primary-600 text-white font-extrabold flex items-center justify-center shrink-0 shadow-md">
            1
          </div>
          <div class="space-y-1">
            <h2 class="text-xl font-bold text-gray-900 tracking-tight">Connect &amp; Authenticate</h2>
            <p class="text-xs text-gray-500">Setting up credentials and attaching the Exoforge manager to your Unity project.</p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 text-xs text-gray-700">
          <div class="space-y-3">
            <h4 class="font-bold text-gray-900 text-sm flex items-center gap-2">
              <span>🎮</span>
              <span>In the Unity Editor</span>
            </h4>
            <ol class="list-decimal list-inside space-y-2 text-gray-600 leading-relaxed">
              <li>
                Open <strong class="text-gray-900">Exoforge ▸ Studio</strong> from the Unity top menu.
              </li>
              <li>
                Click <strong class="text-gray-900">Sign in to Exoforge</strong> and enter your staff account credentials.
              </li>
              <li>
                In your game's first scene, click <strong class="text-gray-900">Exoforge ▸ Add Exoforge to Scene</strong>. This places the persistent <code class="font-mono bg-gray-100 px-1 py-0.5 rounded">Exoforge.prefab</code> into the hierarchy.
              </li>
              <li>
                The runtime exposes synchronous <code class="font-mono bg-gray-100 text-primary-700 px-1 py-0.5 rounded font-bold">Exoforge.IsReady</code> and the <code class="font-mono bg-gray-100 text-primary-700 px-1 py-0.5 rounded font-bold">Exoforge.OnReady</code> event callback.
              </li>
            </ol>
          </div>

          <div class="bg-gray-950 text-gray-200 rounded-2xl p-5 font-mono text-[11px] space-y-2 border border-gray-800">
            <div class="text-gray-400 font-bold border-b border-gray-800 pb-2">Unity Readiness Check</div>
            <pre class="overflow-x-auto text-emerald-400"><code><%= code_auth() %></code></pre>
          </div>
        </div>
      </section>

      <!-- STEP 2: Scaffold Extension -->
      <section id="step-scaffold" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6">
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

          <div class="bg-gray-950 text-gray-200 rounded-2xl p-5 font-mono text-[11px] space-y-2 border border-gray-800">
            <div class="flex items-center justify-between text-gray-400 font-bold border-b border-gray-800 pb-2">
              <span>Exoforge/extensions/gameplay_calculator/src/GameplayCalculatorExtension.cs</span>
              <span class="text-xs text-primary-400">C# 12 / .NET 9+</span>
            </div>
            <pre class="overflow-x-auto text-gray-300"><code><%= code_extension() %></code></pre>
          </div>

          <!-- Tree-Shaking Architectural Callout -->
          <div class="p-5 rounded-2xl bg-gradient-to-r from-amber-50 to-orange-50 border border-amber-200/80 space-y-2 text-amber-900">
            <div class="flex items-center gap-2 font-bold text-sm text-amber-950">
              <span>✂️</span>
              <span>Tree-Shaking &amp; Native Compilation Architecture</span>
            </div>
            <p class="leading-relaxed text-xs text-amber-900">
              When publishing an extension, Exoforge leverages <strong>.NET IL Trimming &amp; Ahead-Of-Time (AOT) tree-shaking</strong>. All unused base class library (BCL) methods and reflection overhead are stripped at compile time.
            </p>
            <ul class="list-disc list-inside space-y-1 text-xs text-amber-800 pl-1">
              <li><strong>Zero Reflection at Runtime:</strong> Contracts, actions, and parameter types are analyzed and serialized into a lightweight <code class="font-mono bg-amber-100 px-1 py-0.5 rounded">manifest.json</code> at build time.</li>
              <li><strong>Minimal Memory Footprint:</strong> Stripped extension binaries load in milliseconds with predictable memory usage under Erlang/OTP supervision.</li>
              <li><strong>Binary Isolation:</strong> Each extension operates in an isolated worker process without polluting cluster dependencies.</li>
            </ul>
          </div>
        </div>
      </section>

      <!-- STEP 3: Build & Deploy -->
      <section id="step-deploy" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6">
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
      <section id="step-stubs" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6">
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
          <div class="p-4 bg-purple-50 text-purple-900 border border-purple-200 rounded-2xl space-y-1">
            <span class="font-bold">What this does:</span>
            <p class="text-purple-800 text-[11px]">
              It queries the live cluster contracts and generates <code class="font-mono bg-purple-100 px-1 py-0.5 rounded">Assets/Exoforge/Generated/ExoforgeServices.g.cs</code>.
              Your Unity project immediately gains typed methods for every action (both main-thread callbacks and async overloads) and models for every return record!
            </p>
          </div>
        </div>
      </section>

      <!-- STEP 5: Call from Unity -->
      <section id="step-gameplay" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6">
        <div class="flex items-start gap-4">
          <div class="w-10 h-10 rounded-2xl bg-primary-600 text-white font-extrabold flex items-center justify-center shrink-0 shadow-md">
            5
          </div>
          <div class="space-y-1">
            <h2 class="text-xl font-bold text-gray-900 tracking-tight">Call from Unity Gameplay Code</h2>
            <p class="text-xs text-gray-500">Standard main-thread callbacks without mandatory async/await.</p>
          </div>
        </div>

        <div class="bg-gray-950 text-gray-200 rounded-2xl p-5 font-mono text-[11px] space-y-2 border border-gray-800">
          <div class="flex items-center justify-between text-gray-400 font-bold border-b border-gray-800 pb-2">
            <span>Assets/Scripts/GameplayRewardController.cs</span>
            <span class="text-xs text-emerald-400">Unity C#</span>
          </div>
          <pre class="overflow-x-auto text-gray-300"><code><%= code_unity() %></code></pre>
        </div>
      </section>

      <!-- SECTION 6: Built-in C# Extension API Cheat Sheet -->
      <section class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6">
        <div>
          <h2 class="text-xl font-bold text-gray-900 tracking-tight flex items-center gap-2">
            <span>📚</span>
            <span>C# Extension API Cheat Sheet</span>
          </h2>
          <p class="text-xs text-gray-500 mt-1">Key methods available in <code class="font-mono bg-gray-100 text-primary-700 px-1 py-0.5 rounded">Exoforge.Plugin.SDK</code>.</p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <!-- Database -->
          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200 space-y-2">
            <h4 class="font-bold text-gray-900 flex items-center gap-1.5 text-sm">
              <span>💾</span>
              <span>ExoServices.Database</span>
            </h4>
            <ul class="space-y-1.5 text-gray-600 font-mono text-[11px]">
              <li><strong class="text-primary-700">Get&lt;T&gt;(id)</strong>: Query entity by PK (inferred table)</li>
              <li><strong class="text-primary-700">Put(entity)</strong>: Upsert entity record</li>
              <li><strong class="text-primary-700">Delete&lt;T&gt;(id)</strong>: Delete entity by PK</li>
              <li><strong class="text-primary-700">All&lt;T&gt;()</strong>: Return all records of table</li>
              <li><strong class="text-primary-700">First&lt;T&gt;()</strong>: Read singleton game config</li>
            </ul>
          </div>

          <!-- Events & Context -->
          <div class="p-5 rounded-2xl bg-gray-50 border border-gray-200 space-y-2">
            <h4 class="font-bold text-gray-900 flex items-center gap-1.5 text-sm">
              <span>📡</span>
              <span>Events &amp; Context</span>
            </h4>
            <ul class="space-y-1.5 text-gray-600 font-mono text-[11px]">
              <li><strong class="text-primary-700">ExoServices.Events.EmitAsync(evt)</strong>: Broadcast event</li>
              <li><strong class="text-primary-700">ExoServices.Context.CurrentPlayerId</strong>: Caller verified ID</li>
              <li><strong class="text-primary-700">ExoServices.Context.CurrentScopes</strong>: Caller roles</li>
              <li><strong class="text-primary-700">throw new ExoActionException(code, msg)</strong>: Throw action error</li>
            </ul>
          </div>
        </div>
      </section>

      <!-- SECTION 7: LIVE ACTION & RESOURCE CATALOG (DYNAMIC & FOLDABLE) -->
      <section id="catalog" class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-6">
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
              Dynamically extracted from currently loaded extensions. Foldable by extension and individual action.
            </p>
          </div>
          <span class="text-xs font-bold text-gray-500 bg-gray-100 px-3 py-1.5 rounded-xl self-start md:self-auto">
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
              <!-- Foldable Extension Group -->
              <details class="group bg-white rounded-2xl border border-gray-200/90 shadow-sm overflow-hidden transition-all duration-200" open>
                <summary class="flex items-center justify-between gap-3 p-5 cursor-pointer select-none bg-white hover:bg-gray-50/80 transition-colors list-none">
                  <div class="flex items-center gap-3">
                    <span class="w-9 h-9 rounded-xl bg-primary-50 text-primary-700 flex items-center justify-center font-bold text-base shadow-xs">
                      <%= svc.icon || "⚙️" %>
                    </span>
                    <div>
                      <h3 class="font-extrabold text-gray-900 text-sm tracking-tight font-mono">
                        <%= svc.name %>
                      </h3>
                      <%= if svc.title do %>
                        <p class="text-[11px] text-gray-500"><%= svc.title %></p>
                      <% end %>
                    </div>
                  </div>

                  <div class="flex items-center gap-3">
                    <span class="text-[11px] font-bold px-2.5 py-1 rounded-full bg-gray-100 text-gray-600 font-mono">
                      <%= length(svc.actions) %> <%= if length(svc.actions) == 1, do: "action", else: "actions" %>
                    </span>
                    <svg class="w-5 h-5 text-gray-400 group-open:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </div>
                </summary>

                <!-- Actions List inside Service -->
                <div class="p-5 pt-2 border-t border-gray-100 space-y-3 bg-gray-50/30">
                  <%= for act <- svc.actions do %>
                    <!-- Foldable Action Card -->
                    <details class="group/act bg-white rounded-xl border border-gray-200/70 p-4 space-y-3 shadow-2xs transition-all" open>
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
                          <svg class="w-4 h-4 text-gray-400 group-open/act:rotate-180 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                          </svg>
                        </div>
                      </summary>

                      <div class="pt-2 border-t border-gray-100 space-y-3">
                        <p class="text-xs text-gray-600 leading-relaxed"><%= act.doc %></p>

                        <!-- Parameter Details Table -->
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

                        <!-- Dual C# Code Calling Previews -->
                        <div class="space-y-2 pt-1">
                          <div class="text-[10px] font-bold uppercase tracking-wider text-gray-400">Unity Calling Styles</div>
                          
                          <!-- Callback Style (Main Thread) -->
                          <div class="space-y-1">
                            <div class="text-[10px] text-gray-500 font-semibold">Unity Callback (Non-Async / Main Thread):</div>
                            <pre class="bg-gray-900 text-emerald-400 p-2.5 rounded-xl font-mono text-[10px] overflow-x-auto"><code><%= snippet_callback(svc.name, act) %></code></pre>
                          </div>

                          <!-- Async Style -->
                          <div class="space-y-1">
                            <div class="text-[10px] text-gray-500 font-semibold">Task Async/Await:</div>
                            <pre class="bg-gray-900 text-gray-300 p-2.5 rounded-xl font-mono text-[10px] overflow-x-auto"><code><%= snippet_async(svc.name, act) %></code></pre>
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
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: [ExoExtension] ATTRIBUTE REFERENCE
  # ===========================================================================
  defp subpage_exo_extension(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-4">
        <div class="flex items-center gap-3 border-b border-gray-100 pb-4">
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

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            The <code class="font-mono text-indigo-700 font-bold">[ExoExtension]</code> attribute is the root entry point for any backend feature in Exoforge. Classes marked with this attribute are automatically registered into the server extension supervisor, inspected for exported RPC actions, and linked into client code generators.
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
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Unique identifier of the extension (e.g. <code class="font-mono text-primary-700">"gameplay_calculator"</code>). Used for RPC addressing and log grouping.</td>
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

        <div class="pt-2 space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>Extension Class Declaration Pattern</span>
            <span class="font-mono text-[11px] text-gray-400">C# 12 / .NET 9+</span>
          </div>
          <pre class="bg-gray-950 text-gray-300 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto"><code><%= code_exo_extension_page() %></code></pre>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 pt-2">
          <div class="p-4 rounded-xl bg-gray-50 border border-gray-200/80 space-y-1">
            <span class="font-bold text-gray-900 text-xs">🛡️ OTP Supervision</span>
            <p class="text-[11px] text-gray-500">Each extension executes inside an isolated worker process. Uncaught exceptions or crashes restart in milliseconds without impacting other players or cluster services.</p>
          </div>
          <div class="p-4 rounded-xl bg-gray-50 border border-gray-200/80 space-y-1">
            <span class="font-bold text-gray-900 text-xs">✂️ Treeshaked Binaries</span>
            <p class="text-[11px] text-gray-500">Dead code trimming removes all unreferenced .NET BCL types, producing lightweight binaries with instant cold start times.</p>
          </div>
          <div class="p-4 rounded-xl bg-gray-50 border border-gray-200/80 space-y-1">
            <span class="font-bold text-gray-900 text-xs">🔄 Zero-Reflection</span>
            <p class="text-[11px] text-gray-500">Manifests and type tables are evaluated at build time. Runtime dispatching does not incur reflection overhead.</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: [ExoAction] ATTRIBUTE REFERENCE
  # ===========================================================================
  defp subpage_exo_action(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-4">
        <div class="flex items-center gap-3 border-b border-gray-100 pb-4">
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

        <!-- C# Action Example -->
        <div class="pt-2 space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>Server Action Implementation</span>
            <span class="font-mono text-[11px] text-gray-400">C# Backend</span>
          </div>
          <pre class="bg-gray-950 text-gray-300 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto"><code><%= code_exo_action_page() %></code></pre>
        </div>

        <!-- Error Handling Callout -->
        <div class="p-4 rounded-2xl bg-rose-50 border border-rose-200 space-y-2 text-rose-900 text-xs">
          <div class="flex items-center gap-2 font-bold text-rose-950 text-sm">
            <span>🚨</span>
            <span>Standardized Error Throwing with ExoActionException</span>
          </div>
          <p class="leading-relaxed">
            Do not throw raw exceptions. Throwing <code class="font-mono bg-rose-100 text-rose-800 px-1 py-0.5 rounded font-bold">new ExoActionException(code, message)</code> ensures structured error payloads propagate through the WebSocket layer with consistent error codes and clear user-facing messages.
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: [ExoEvent] ATTRIBUTE REFERENCE
  # ===========================================================================
  defp subpage_exo_event(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-4">
        <div class="flex items-center gap-3 border-b border-gray-100 pb-4">
          <span class="w-10 h-10 rounded-2xl bg-purple-50 text-purple-700 flex items-center justify-center font-bold text-lg">
            📡
          </span>
          <div>
            <div class="flex items-center gap-2">
              <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoEvent]</h2>
              <span class="px-2 py-0.5 rounded-full bg-purple-100 text-purple-800 text-[10px] font-bold uppercase tracking-wider">Real-Time Messaging</span>
            </div>
            <p class="text-xs text-gray-500 mt-0.5">Declares real-time event schemas and pub/sub topics across the distributed cluster.</p>
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            Decorate record models with <code class="font-mono text-purple-700 font-bold">[ExoEvent("topic.name")]</code>. Emit events from backend services using <code class="font-mono bg-purple-50 text-purple-700 px-1 py-0.5 rounded">ExoServices.Events.EmitAsync(evt)</code>. All subscribed Unity game clients and cluster listeners receive the payload over WebSocket in sub-millisecond time.
          </p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 pt-2">
          <!-- Backend Emit -->
          <div class="space-y-2">
            <div class="text-xs text-gray-500 font-bold">1. Backend Event Declaration &amp; Emission</div>
            <pre class="bg-gray-950 text-gray-300 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto"><code><%= code_exo_event_page() %></code></pre>
          </div>

          <!-- Unity Receive -->
          <div class="space-y-2">
            <div class="text-xs text-gray-500 font-bold">2. Unity Client Realtime Listener</div>
            <pre class="bg-gray-950 text-emerald-400 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto"><code><%= code_exo_event_unity() %></code></pre>
          </div>
        </div>

        <div class="p-4 rounded-2xl bg-purple-50/70 border border-purple-200 text-xs text-purple-900 space-y-1">
          <span class="font-bold">Topic Filtering &amp; Routing:</span>
          <p class="leading-relaxed text-purple-800 text-[11px]">
            Topics follow standard dot-notation (<code class="font-mono bg-purple-100 px-1 py-0.2 rounded font-bold">match.player_joined</code>, <code class="font-mono bg-purple-100 px-1 py-0.2 rounded font-bold">economy.item_traded</code>). Unity subscriptions dispatch handlers onto the main thread via <code class="font-mono bg-purple-100 px-1 py-0.2 rounded">ExoDispatcher</code>, ensuring UI updates and GameObject manipulation remain safe.
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # SUBPAGE: [ExoResource] ATTRIBUTE REFERENCE
  # ===========================================================================
  defp subpage_exo_resource(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white rounded-3xl border border-gray-200/90 p-8 shadow-sm space-y-4">
        <div class="flex items-center gap-3 border-b border-gray-100 pb-4">
          <span class="w-10 h-10 rounded-2xl bg-emerald-50 text-emerald-700 flex items-center justify-center font-bold text-lg">
            💾
          </span>
          <div>
            <div class="flex items-center gap-2">
              <h2 class="text-xl font-extrabold text-gray-900 font-mono">[ExoResource]</h2>
              <span class="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 text-[10px] font-bold uppercase tracking-wider">Persistence Schema</span>
            </div>
            <p class="text-xs text-gray-500 mt-0.5">Type-safe entity modeling with automatic table inference and generic database helpers.</p>
          </div>
        </div>

        <div class="space-y-3 text-xs text-gray-700 leading-relaxed">
          <p>
            Exoforge simplifies persistence: you do not write raw SQL or manual migration scripts. Declare clean C# records, register them on your extension's <code class="font-mono text-emerald-700 font-bold">[ExoExtension(Resources = [...])]</code>, and interact with storage using generic helpers.
          </p>

          <div class="p-4 rounded-2xl bg-emerald-50 border border-emerald-200 space-y-1.5 text-emerald-950">
            <span class="font-bold text-xs flex items-center gap-1.5">
              <span>✨</span>
              <span>Automatic Table Name Inference</span>
            </span>
            <p class="text-[11px] leading-relaxed text-emerald-900">
              When calling <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded text-emerald-950 font-bold">ExoServices.Database.Get&lt;PlayerProfile&gt;(id)</code>, the database engine automatically infers the underlying table name as <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded text-emerald-950 font-bold">"player_profiles"</code>. You can optionally override this with <code class="font-mono bg-emerald-100 px-1 py-0.5 rounded text-emerald-950 font-bold">[ExoResource("custom_name")]</code>.
            </p>
          </div>

          <div class="overflow-x-auto rounded-xl border border-gray-200 mt-3">
            <table class="w-full text-left text-xs bg-white">
              <thead class="bg-gray-50 border-b border-gray-200 text-gray-500 font-semibold text-[10px] uppercase">
                <tr>
                  <th class="py-2 px-3">Database Helper</th>
                  <th class="py-2 px-3">Parameters</th>
                  <th class="py-2 px-3">Returns</th>
                  <th class="py-2 px-3">Description</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 font-mono text-[11px]">
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Get&lt;T&gt;</td>
                  <td class="py-2 px-3 text-primary-700">string id</td>
                  <td class="py-2 px-3 text-primary-700">T?</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Queries entity by primary key from inferred table. Returns null if not found.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Put</td>
                  <td class="py-2 px-3 text-primary-700">T entity</td>
                  <td class="py-2 px-3 text-primary-700">void</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Upserts the entity record into storage (creates or overwrites based on <code class="font-mono">Id</code>).</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">Delete&lt;T&gt;</td>
                  <td class="py-2 px-3 text-primary-700">string id</td>
                  <td class="py-2 px-3 text-primary-700">void</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Deletes entity by primary key.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">All&lt;T&gt;</td>
                  <td class="py-2 px-3 text-primary-700">—</td>
                  <td class="py-2 px-3 text-primary-700">List&lt;T&gt;</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Returns all records present in the entity table.</td>
                </tr>
                <tr>
                  <td class="py-2 px-3 font-bold text-gray-900">First&lt;T&gt;</td>
                  <td class="py-2 px-3 text-primary-700">—</td>
                  <td class="py-2 px-3 text-primary-700">T?</td>
                  <td class="py-2 px-3 font-sans text-xs text-gray-600">Reads the first record (ideal for singleton server configuration records).</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="pt-2 space-y-2">
          <div class="flex items-center justify-between text-xs text-gray-500 font-bold">
            <span>Resource Record Declaration &amp; Database CRUD</span>
            <span class="font-mono text-[11px] text-gray-400">C# 12 / .NET 9+</span>
          </div>
          <pre class="bg-gray-950 text-gray-300 p-4 rounded-2xl font-mono text-[11px] overflow-x-auto"><code><%= code_exo_resource_page() %></code></pre>
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # HELPER CODE BLOCKS & SNIPPETS
  # ===========================================================================

  defp snippet_callback(svc_name, act) do
    service_pascal = Macro.camelize(to_string(svc_name))
    action_pascal = Macro.camelize(to_string(act.name))
    params = act.params || []

    args =
      if params == [] do
        "onComplete: res => { Debug.Log($\"Success: {res}\"); }, onError: ex => { Debug.LogWarning(ex.Message); }"
      else
        param_args = Enum.map_join(params, ", ", fn p -> "#{p.name}: #{sample_value(p.type)}" end)
        "#{param_args}, onComplete: res => { Debug.Log($\"Success: {res}\"); }, onError: ex => { Debug.LogWarning(ex.Message); }"
      end

    "Exoforge.Client.#{service_pascal}().#{action_pascal}(#{args});"
  end

  defp snippet_async(svc_name, act) do
    service_pascal = Macro.camelize(to_string(svc_name))
    action_pascal = Macro.camelize(to_string(act.name))
    params = act.params || []

    args =
      if params == [] do
        ""
      else
        Enum.map_join(params, ", ", fn p -> "#{p.name}: #{sample_value(p.type)}" end)
      end

    "var result = await Exoforge.Client.#{service_pascal}().#{action_pascal}Async(#{args});"
  end

  defp sample_value(:integer), do: "1"
  defp sample_value(:float), do: "1.0f"
  defp sample_value(:boolean), do: "true"
  defp sample_value(:map), do: "new { }"
  defp sample_value(_), do: "\"value\""

  defp code_auth do
    """
    void Start()
    {
        // 1. Listen for readiness (dispatched on Unity's main thread)
        Exoforge.OnReady += () =>
        {
            Debug.Log($"Connected & authenticated as {Exoforge.Client.PlayerId}");
        };

        // Or inspect synchronously at any time:
        if (Exoforge.IsReady)
        {
            Debug.Log($"Already ready! Player: {Exoforge.Client.PlayerId}");
        }
    }
    """
    |> String.trim()
  end

  defp code_extension do
    """
    using System;
    using Exoforge.Plugin.SDK;

    namespace Exoforge.Extensions;

    [ExoExtension("gameplay_calculator", Version = "0.1.0")]
    public class GameplayCalculatorExtension
    {
        [ExoAction]
        public LevelReward CalculateReward(int currentLevel, int addedXp)
        {
            if (currentLevel < 1)
                throw new ExoActionException("invalid_level", "Current level must be >= 1.");

            if (addedXp < 0)
                throw new ExoActionException("invalid_xp", "Added XP cannot be negative.");

            int xpThreshold = currentLevel * 100;
            int newLevel = currentLevel + (addedXp / xpThreshold);
            int bonusGems = (newLevel > currentLevel) ? (newLevel - currentLevel) * 25 : 5;

            return new LevelReward(
                NewLevel: newLevel,
                BonusGems: bonusGems,
                UnlockedTier: newLevel >= 10 ? "Veteran" : "Novice"
            );
        }
    }

    public record LevelReward(int NewLevel, int BonusGems, string UnlockedTier);
    """
    |> String.trim()
  end

  defp code_unity do
    """
    using UnityEngine;
    using Exoforge.Client.Unity;
    using Exoforge.Plugin.SDK;

    public class GameplayRewardController : MonoBehaviour
    {
        void Start()
        {
            // Subscribe to the connection event
            Exoforge.OnReady += OnExoforgeReady;
        }

        void OnDestroy()
        {
            Exoforge.OnReady -= OnExoforgeReady;
        }

        private void OnExoforgeReady()
        {
            Debug.Log($"Connected to Exoforge cluster as {Exoforge.Client.PlayerId}");
        }

        public void OnCalculateButtonClicked()
        {
            // Verify readiness synchronously before calling
            if (!Exoforge.IsReady)
            {
                Debug.LogWarning("Exoforge connection is still initializing.");
                return;
            }

            // Standard Unity callback overload (automatically executed on Main Thread!)
            Exoforge.Client.GameplayCalculator().CalculateReward(
                currentLevel: 5,
                addedXp: 150,
                onComplete: reward =>
                {
                    Debug.Log($"Level Up! New Level: {reward.NewLevel}, Gems: {reward.BonusGems}");
                },
                onError: ex =>
                {
                    Debug.LogWarning($"Calculation failed [{ex.Code}]: {ex.Message}");
                }
            );
        }
    }
    """
    |> String.trim()
  end

  defp code_exo_extension_page do
    """
    using System;
    using Exoforge.Plugin.SDK;

    namespace Exoforge.Extensions;

    // Declares an extension with its version and managed resource entity types
    [ExoExtension("inventory_service", Version = "1.0.0", Resources = [typeof(InventoryItem)])]
    public class InventoryExtension
    {
        public InventoryExtension()
        {
            // Worker initialization lifecycle
            Console.WriteLine("Inventory service initialized under OTP supervision.");
        }

        [ExoAction(Mode = "sync", Scope = "player")]
        public InventoryItem GrantItem(string itemId, int count = 1)
        {
            string playerId = ExoServices.Context.CurrentPlayerId;
            var item = new InventoryItem(Guid.NewGuid().ToString(), playerId, itemId, count);
            ExoServices.Database.Put(item);
            return item;
        }
    }

    public record InventoryItem(string Id, string PlayerId, string ItemId, int Quantity);
    """
    |> String.trim()
  end

  defp code_exo_action_page do
    """
    using System;
    using Exoforge.Plugin.SDK;

    namespace Exoforge.Extensions;

    [ExoExtension("matchmaker")]
    public class MatchmakerExtension
    {
        [ExoAction(Mode = "sync", Scope = "player")]
        public MatchTicket RequestMatch(string queueType, int playerRating)
        {
            // 1. Verify caller context
            string playerId = ExoServices.Context.CurrentPlayerId;
            if (string.IsNullOrEmpty(playerId))
                throw new ExoActionException("unauthorized", "Player session required.");

            // 2. Validate input arguments
            if (playerRating < 0)
                throw new ExoActionException("invalid_rating", "Rating cannot be negative.");

            // 3. Return structured record response
            string ticketId = Guid.NewGuid().ToString();
            return new MatchTicket(ticketId, playerId, queueType, "Searching");
        }
    }

    public record MatchTicket(string TicketId, string PlayerId, string Queue, string Status);
    """
    |> String.trim()
  end

  defp code_exo_event_page do
    """
    using System;
    using Exoforge.Plugin.SDK;

    namespace Exoforge.Extensions;

    // 1. Declare event schema with topic name
    [ExoEvent("player.leveled_up")]
    public record PlayerLeveledUp(string PlayerId, int NewLevel, long TotalXp);

    [ExoExtension("progression")]
    public class ProgressionExtension
    {
        [ExoAction]
        public async System.Threading.Tasks.Task<bool> LevelUp(int xpGained)
        {
            string playerId = ExoServices.Context.CurrentPlayerId;
            int newLevel = 10;

            // 2. Broadcast event to all cluster subscribers and Unity clients
            await ExoServices.Events.EmitAsync(new PlayerLeveledUp(playerId, newLevel, 25000));
            return true;
        }
    }
    """
    |> String.trim()
  end

  defp code_exo_event_unity do
    """
    using UnityEngine;
    using Exoforge.Client.Unity;

    public class ProgressionUI : MonoBehaviour
    {
        private System.IDisposable? _subscription;

        void Start()
        {
            // Subscribe to the real-time event topic
            // Handlers are automatically dispatched on Unity's Main Thread!
            _subscription = Exoforge.Client.On<PlayerLeveledUp>("player.leveled_up", evt =>
            {
                Debug.Log($"[Realtime] Player {evt.PlayerId} reached Level {evt.NewLevel}!");
            });
        }

        void OnDestroy()
        {
            // Clean up subscription
            _subscription?.Dispose();
        }
    }
    """
    |> String.trim()
  end

  defp code_exo_resource_page do
    """
    using System;
    using System.Collections.Generic;
    using Exoforge.Plugin.SDK;

    namespace Exoforge.Extensions;

    // Database table inferred automatically as "player_profiles"
    public record PlayerProfile(
        string Id,           // Primary key (always named 'Id')
        string DisplayName,
        int Level,
        long Gold,
        DateTime LastLogin
    );

    [ExoExtension("profile_service", Resources = [typeof(PlayerProfile)])]
    public class ProfileExtension
    {
        [ExoAction]
        public PlayerProfile GetProfile()
        {
            string playerId = ExoServices.Context.CurrentPlayerId;

            // 1. Query by primary key (table name inferred from <PlayerProfile>)
            var profile = ExoServices.Database.Get<PlayerProfile>(playerId);
            if (profile != null)
                return profile;

            // 2. Upsert entity if not found
            var newProfile = new PlayerProfile(playerId, "New Recruit", 1, 50, DateTime.UtcNow);
            ExoServices.Database.Put(newProfile);
            return newProfile;
        }
    }
    """
    |> String.trim()
  end
end
