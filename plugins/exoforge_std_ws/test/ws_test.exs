defmodule Exoforge.Std.WsTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Exoforge.Std.Ws.Router
  alias Exoforge.Std.Ws.SocketHandler
  alias Exoforge.EventDispatcher
  alias Exoforge.PluginRegistry
  alias Exoforge.Domain.Manifest

  defmodule DummyService do
    import Exoforge.Contracts.Service

    defservice mock do
      action :greet do
        params(name: :string)
        returns(message: :string)
      end

      action :kick_user do
        scope(:admin)
        params(user_id: :string)
        returns(status: :string)
      end
    end
  end

  defmodule DummyPlugin do
    use Exoforge.Plugin, provides: [Exoforge.Std.WsTest.DummyService.Mock]

    @impl true
    defaction greet(payload) do
      name = Map.get(payload, "name") || Map.get(payload, :name, "World")
      {:ok, %{message: "Hello, #{name}!"}}
    end

    @impl true
    defaction kick_user(_payload), scope: :admin do
      {:ok, %{status: "kicked"}}
    end
  end

  setup do
    Application.put_env(:exoforge, :allow_dev_tokens, true)
    unless Process.whereis(EventDispatcher.registry_name()) do
      start_supervised!(EventDispatcher)
    end
    PluginRegistry.initialize_ets()

    unless Process.whereis(Exoforge.Std.Database.Manager) do
      start_supervised!({Exoforge.Std.Database.Manager, [driver: :sqlite]})
    end

    PluginRegistry.register(%Manifest{
      id: :exoforge_std_database,
      name: "exoforge_std_database",
      version: "0.1.0",
      entry_point: Exoforge.Std.Database,
      provides: [Exoforge.Std.Services.Database, Exoforge.Std.Services.Lldb]
    })

    PluginRegistry.register(%Manifest{
      id: :exoforge_std_auth,
      name: "exoforge_std_auth",
      version: "0.1.0",
      entry_point: Exoforge.Std.Auth,
      provides: [Exoforge.Std.Services.Auth],
      dependencies: [Exoforge.Std.Services.Database]
    })

    manifest = %Manifest{
      id: :dummy_plugin,
      name: "dummy_plugin",
      version: "1.0.0",
      entry_point: DummyPlugin,
      provides: [DummyService.Mock]
    }

    PluginRegistry.register(manifest)
    :ok
  end

  test "HTTP health endpoint returns ok" do
    conn = conn(:get, "/health")
    conn = Router.call(conn, Router.init([]))

    assert conn.status == 200
    assert %{"status" => "ok", "plugin" => "exoforge_std_ws"} = Jason.decode!(conn.resp_body)
  end

  test "GET / returns 200 ok with gateway metadata" do
    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer dev:admin")
    conn = Router.call(conn, Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "ok"
    assert body["service"] == "exoforge_std_ws"
    assert body["gateway"] == "websocket"
    assert body["ws_endpoint"] == "/ws"
  end

  test "GET / with Accept: text/html returns HTML landing page" do
    conn =
      conn(:get, "/")
      |> put_req_header("authorization", "Bearer dev:admin")
      |> put_req_header("accept", "text/html")
      |> Router.call(Router.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "Exoforge WebSocket Gateway"
    assert conn.resp_body =~ "ws://localhost:#{Exoforge.Endpoints.ws_port()}/ws"
  end

  test "GET /ws without upgrade header returns 426 Upgrade Required" do
    conn = conn(:get, "/ws")
    conn = Router.call(conn, Router.init([]))

    assert conn.status == 426
    body = Jason.decode!(conn.resp_body)
    assert body["error"] == "upgrade_required"
  end

  defp authenticate(state, token) do
    msg = Jason.encode!(%{"type" => "auth", "token" => token})
    SocketHandler.handle_in({msg, :text}, state)
  end

  test "WebSocket ping returns pong" do
    {:ok, state} = SocketHandler.init([])

    ping_msg = Jason.encode!(%{"type" => "ping"})
    assert {:push, {:text, resp_json}, _new_state} = SocketHandler.handle_in({ping_msg, :text}, state)

    assert %{"type" => "pong"} = Jason.decode!(resp_json)
  end

  test "WebSocket action call dispatches and returns action_result" do
    {:ok, state} = SocketHandler.init([])
    {:push, {:text, _}, state} = authenticate(state, "dev:admin")

    action_msg =
      Jason.encode!(%{
        "type" => "action",
        "id" => "req-42",
        "service" => "Exoforge.Std.WsTest.DummyService.Mock",
        "action" => "greet",
        "payload" => %{"name" => "Alex"}
      })

    assert {:push, {:text, resp_json}, _new_state} = SocketHandler.handle_in({action_msg, :text}, state)

    resp = Jason.decode!(resp_json)
    assert resp["type"] == "action_result"
    assert resp["id"] == "req-42"
    assert resp["status"] == "ok"
    assert resp["data"] == %{"message" => "Hello, Alex!"}
  end

  test "WebSocket subscribe and broadcast pushes event frame" do
    {:ok, state} = SocketHandler.init([])
    {:push, {:text, _}, state} = authenticate(state, "dev:admin")

    # 1. Subscribe to topic
    sub_msg = Jason.encode!(%{"type" => "subscribe", "topic" => "room:test"})
    assert {:push, {:text, sub_resp}, sub_state} = SocketHandler.handle_in({sub_msg, :text}, state)
    assert %{"type" => "subscribed", "topic" => "room:test"} = Jason.decode!(sub_resp)

    # 2. Broadcast event via EventDispatcher
    EventDispatcher.broadcast(:player_spawned, %{id: 99, x: 10.5}, topic: "room:test")

    # 3. Handle info received by socket handler process
    assert_receive {:exo_event, :player_spawned, payload, context}

    assert {:push, {:text, event_json}, _state} =
             SocketHandler.handle_info({:exo_event, :player_spawned, payload, context}, sub_state)

    event_frame = Jason.decode!(event_json)
    assert event_frame["type"] == "event"
    assert event_frame["event"] == "player_spawned"
    assert event_frame["topic"] == "room:test"
    assert event_frame["payload"] == %{"id" => 99, "x" => 10.5}

    # 4. Unsubscribe
    unsub_msg = Jason.encode!(%{"type" => "unsubscribe", "topic" => "room:test"})
    assert {:push, {:text, unsub_resp}, unsub_state} = SocketHandler.handle_in({unsub_msg, :text}, sub_state)
    assert %{"type" => "unsubscribed", "topic" => "room:test"} = Jason.decode!(unsub_resp)
    assert MapSet.size(unsub_state.subscriptions) == 0
  end

  test "WebSocket handles invalid JSON gracefully" do
    {:ok, state} = SocketHandler.init([])
    assert {:push, {:text, resp_json}, _state} = SocketHandler.handle_in({"invalid{json", :text}, state)

    resp = Jason.decode!(resp_json)
    assert resp["type"] == "error"
    assert resp["error"]["code"] == "invalid_json"
  end

  test "WebSocket rejects unauthenticated action call with unauthenticated" do
    {:ok, state} = SocketHandler.init([])

    action_msg =
      Jason.encode!(%{
        "type" => "action",
        "id" => "req-101",
        "service" => "Exoforge.Std.WsTest.DummyService.Mock",
        "action" => "kick_user",
        "payload" => %{"user_id" => "bad_actor"}
      })

    assert {:push, {:text, resp_json}, _state} = SocketHandler.handle_in({action_msg, :text}, state)

    resp = Jason.decode!(resp_json)
    assert resp["type"] == "action_result"
    assert resp["id"] == "req-101"
    assert resp["status"] == "error"
    assert resp["error"]["code"] == "unauthenticated"
  end

  test "WebSocket rejects call from authenticated guest lacking scope with forbidden_scope" do
    {:ok, state} = SocketHandler.init([])

    auth_msg = Jason.encode!(%{"type" => "auth", "token" => "guest"})
    assert {:push, {:text, auth_resp}, auth_state} = SocketHandler.handle_in({auth_msg, :text}, state)
    assert %{"status" => "ok"} = Jason.decode!(auth_resp)

    action_msg =
      Jason.encode!(%{
        "type" => "action",
        "id" => "req-102",
        "service" => "Exoforge.Std.WsTest.DummyService.Mock",
        "action" => "kick_user",
        "payload" => %{"user_id" => "bad_actor"}
      })

    assert {:push, {:text, resp_json}, _state} = SocketHandler.handle_in({action_msg, :text}, auth_state)

    resp = Jason.decode!(resp_json)
    assert resp["type"] == "action_result"
    assert resp["id"] == "req-102"
    assert resp["status"] == "error"
    assert resp["error"]["code"] == "forbidden_scope"
  end

  test "WebSocket allows call from authenticated admin with ok" do
    {:ok, state} = SocketHandler.init([])

    auth_msg = Jason.encode!(%{"type" => "auth", "token" => "dev:admin"})
    assert {:push, {:text, auth_resp}, auth_state} = SocketHandler.handle_in({auth_msg, :text}, state)
    assert %{"status" => "ok"} = Jason.decode!(auth_resp)

    action_msg =
      Jason.encode!(%{
        "type" => "action",
        "id" => "req-103",
        "service" => "Exoforge.Std.WsTest.DummyService.Mock",
        "action" => "kick_user",
        "payload" => %{"user_id" => "bad_actor"}
      })

    assert {:push, {:text, resp_json}, _state} = SocketHandler.handle_in({action_msg, :text}, auth_state)

    resp = Jason.decode!(resp_json)
    assert resp["type"] == "action_result"
    assert resp["id"] == "req-103"
    assert resp["status"] == "ok"
    assert resp["data"] == %{"status" => "kicked"}
  end

  test "studio can call a player action but not an admin action" do
    {:ok, studio} = Exoforge.Std.Auth.issue_token("stu_ws", ["studio"])
    {:ok, state} = SocketHandler.init([])
    {:push, {:text, _}, state} = authenticate(state, studio)

    greet =
      Jason.encode!(%{
        "type" => "action",
        "id" => "g1",
        "service" => "Exoforge.Std.WsTest.DummyService.Mock",
        "action" => "greet",
        "payload" => %{"name" => "Studio"}
      })

    assert {:push, {:text, resp}, state} = SocketHandler.handle_in({greet, :text}, state)
    assert Jason.decode!(resp)["status"] == "ok"

    kick =
      Jason.encode!(%{
        "type" => "action",
        "id" => "k1",
        "service" => "Exoforge.Std.WsTest.DummyService.Mock",
        "action" => "kick_user",
        "payload" => %{"user_id" => "x"}
      })

    assert {:push, {:text, resp2}, _} = SocketHandler.handle_in({kick, :text}, state)
    assert Jason.decode!(resp2)["error"]["code"] == "forbidden_scope"
  end
end
