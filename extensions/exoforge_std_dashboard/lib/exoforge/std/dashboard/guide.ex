defmodule Exoforge.Std.Dashboard.Guide do
  @moduledoc """
  Comprehensive Quickstart Guide & Live API Reference for Exoforge developers.
  Renders interactive steps, copyable C# snippets, and a live catalog of all
  cluster services, actions, and resources.
  """
  use Phoenix.Component

  attr(:action_catalog, :list, default: [])
  attr(:extensions, :list, default: [])
  attr(:project_name, :string, default: "Game")
  attr(:studio_name, :string, default: "Studio")

  def view(assigns) do
    ~H"""
    <div class="space-y-8 max-w-6xl mx-auto pb-16">
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
            Extensions run as native .NET processes under supervision. Use clean C# records, generic database helpers, and throw structured <code class="font-mono text-primary-700 bg-primary-50 px-1 py-0.5 rounded">ExoActionException</code>.
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
          <h3 class="font-bold text-gray-900 text-sm">Strongly-Typed Client Stubs</h3>
          <p class="text-xs text-gray-500 leading-relaxed">
            The client sync engine generates strongly-typed methods in <code class="font-mono text-purple-700 bg-purple-50 px-1 py-0.5 rounded">Exoforge.Client.&lt;Service&gt;()</code> with full autocomplete and zero manual JSON serialization.
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
                Click <strong class="text-gray-900">Sign in to Exoforge</strong> and enter your staff account credentials (e.g. administrator or developer account created during setup).
              </li>
              <li>
                In your game's first scene, click <strong class="text-gray-900">Exoforge ▸ Add Exoforge to Scene</strong>. This places the persistent <code class="font-mono bg-gray-100 px-1 py-0.5 rounded">Exoforge.prefab</code> into the hierarchy.
              </li>
              <li>
                The prefab ensures background WebSocket reconnects, main-thread callback dispatching, and persistent player state (<code class="font-mono bg-gray-100 px-1 py-0.5 rounded">DontDestroyOnLoad</code>).
              </li>
            </ol>
          </div>

          <div class="bg-gray-950 text-gray-200 rounded-2xl p-5 font-mono text-[11px] space-y-2 border border-gray-800">
            <div class="text-gray-400 font-bold border-b border-gray-800 pb-2">Unity Gameplay Lifecycle</div>
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
              <span>Exoforge/extensions/daily_rewards/src/DailyRewardsExtension.cs</span>
              <span class="text-xs text-primary-400">C# 12 / .NET 9+</span>
            </div>
            <pre class="overflow-x-auto text-gray-300"><code><%= code_extension() %></code></pre>
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
            <pre class="bg-gray-900 text-emerald-400 p-3 rounded-xl font-mono text-[11px] overflow-x-auto"><code>exo extension push daily_rewards&#10;exo extension logs daily_rewards</code></pre>
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
              Your Unity project immediately gains typed methods for every action and models for every return record!
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
            <p class="text-xs text-gray-500">Fully type-safe calls with built-in canonical error handling.</p>
          </div>
        </div>

        <div class="bg-gray-950 text-gray-200 rounded-2xl p-5 font-mono text-[11px] space-y-2 border border-gray-800">
          <div class="flex items-center justify-between text-gray-400 font-bold border-b border-gray-800 pb-2">
            <span>Assets/Scripts/DailyRewardsUI.cs</span>
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

      <!-- SECTION 7: LIVE ACTION & RESOURCE CATALOG (DYNAMIC) -->
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
              Dynamically extracted from currently loaded extensions on this cluster.
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
          <div class="space-y-6">
            <%= for svc <- @action_catalog do %>
              <div class="border border-gray-200/90 rounded-2xl p-5 hover:border-primary-400 transition-colors bg-white shadow-xs space-y-4">
                <div class="flex items-center justify-between gap-3 border-b border-gray-100 pb-3">
                  <div class="flex items-center gap-2.5">
                    <span class="w-8 h-8 rounded-lg bg-primary-50 text-primary-700 flex items-center justify-center font-bold text-sm">
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
                  <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-gray-100 text-gray-600 font-mono">
                    <%= length(svc.actions) %> actions
                  </span>
                </div>

                <!-- Actions List -->
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
                  <%= for act <- svc.actions do %>
                    <div class="p-3 rounded-xl bg-gray-50/80 border border-gray-200/60 space-y-2">
                      <div class="flex items-center justify-between gap-2">
                        <span class="font-bold text-primary-800 text-xs font-mono">
                          .<%= act.name %>()
                        </span>
                        <span class="text-[9px] font-bold px-1.5 py-0.5 rounded bg-gray-200/70 text-gray-600 uppercase">
                          <%= act.mode %>
                        </span>
                      </div>
                      <p class="text-[11px] text-gray-500"><%= act.doc %></p>

                      <!-- Parameters -->
                      <%= if is_list(act.params) and act.params != [] do %>
                        <div class="pt-1 flex flex-wrap gap-1">
                          <%= for p <- act.params do %>
                            <span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-mono bg-white border border-gray-200 text-gray-700">
                              <span class="text-gray-400"><%= p.type %></span>
                              <span class="font-bold text-gray-900"><%= p.name %></span>
                            </span>
                          <% end %>
                        </div>
                      <% end %>

                      <!-- Copyable C# Call Sample -->
                      <div class="pt-2">
                        <pre class="bg-gray-900 text-gray-300 p-2 rounded-lg font-mono text-[10px] overflow-x-auto"><code>await Exoforge.Client.<%= Macro.camelize(to_string(svc.name)) %>().<%= Macro.camelize(to_string(act.name)) %>Async(<%= Enum.map_join(act.params || [], ", ", fn p -> "#{p.name}: ..." end) %>);</code></pre>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp code_auth do
    """
    // 1. Wait for Exoforge to connect & authenticate
    await Exoforge.Ready;

    // 2. Access the authenticated player's identity
    string playerId = Exoforge.Client.PlayerId;
    Debug.Log($"Connected as {playerId}");
    """
    |> String.trim()
  end

  defp code_extension do
    """
    using System;
    using Exoforge.Plugin.SDK;

    namespace Exoforge.Extensions;

    [ExoExtension("daily_rewards", Version = "0.1.0", Resources = [typeof(DailyRewardsClaim)])]
    public class DailyRewardsExtension
    {
        [ExoAction]
        public DailyRewardsReward ClaimDailyReward(int level)
        {
            var playerId = ExoServices.Context.CurrentPlayerId;
            if (string.IsNullOrEmpty(playerId))
                throw new ExoActionException("unauthorized", "Player session is required.");

            var existing = ExoServices.Database.Get<DailyRewardsClaim>(playerId);
            if (existing != null)
                throw new ExoActionException("already_claimed", "Daily reward has already been claimed.");

            var reward = new DailyRewardsReward("coins", 100 + level * 10);
            ExoServices.Database.Put(new DailyRewardsClaim(playerId, DateTime.UtcNow));
            return reward;
        }
    }

    public record DailyRewardsReward(string Kind, int Amount);
    public record DailyRewardsClaim(string Id, DateTime ClaimedAt);
    """
    |> String.trim()
  end

  defp code_unity do
    """
    using UnityEngine;
    using Exoforge.Client.Unity;
    using Exoforge.Plugin.SDK;

    public class DailyRewardsUI : MonoBehaviour
    {
        public async void OnClaimButtonClicked()
        {
            // 1. Wait for connection & session
            await Exoforge.Ready;

            try
            {
                // 2. Invoke action via strongly-typed stub
                var reward = await Exoforge.Client.DailyRewards()
                    .ClaimDailyRewardAsync(level: 5);

                Debug.Log($"Reward claimed: {reward.Amount} {reward.Kind}!");
            }
            catch (ExoActionException ex)
            {
                // 3. Canonical error handling for any server-side failure
                Debug.LogWarning($"Failed [{ex.Code}]: {ex.Message}");
            }
        }
    }
    """
    |> String.trim()
  end
end
