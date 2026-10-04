%{
  id: :snake_server,
  name: "snake_server",
  type: :native,
  version: "1.0.0",
  context: :global,
  entry_point: "snake_server",
  dependencies: [],
  provides: [:snake_server],
  category: "Game",
  dashboard_view: %{id: :snake_server, title: "Snake Server", icon: "🐍"},
  services: [
    %{
      name: :snake_server,
      actions: [
        %{name: :start_game, mode: :sync, scope: :global, transport: :auto, arity: 2, params: [width: :integer, height: :integer], returns: :integer},
        %{name: :move, mode: :sync, scope: :global, transport: :websocket, arity: 5, params: [current_x: :integer, current_y: :integer, direction: :integer, food_x: :integer, food_y: :integer], returns: :integer},
        %{name: :submit_score, mode: :sync, scope: :global, transport: :http, arity: 2, params: [score: :integer, snake_length: :integer], returns: :integer},
        %{name: :get_leaderboard, mode: :sync, scope: :global, transport: :http, arity: 1, params: [limit: :integer], returns: :integer},
        %{name: :send_challenge, mode: :sync, scope: :global, transport: :auto, arity: 1, params: [score_to_beat: :integer], returns: :integer},
      ],
      events: [
        %{name: :food_spawned, topic: "snake:events", scope: :global, payload: [x: :integer, y: :integer, points: :integer]},
        %{name: :game_over, topic: "snake:events", scope: :global, payload: [player_id: :string, final_score: :integer, reason: :string]},
        %{name: :challenge_received, topic: "snake:social", scope: :global, payload: [from_player: :string, score_to_beat: :integer, message: :string]},
      ],
      resources: [
        %{
          name: :snake_scores,
          primary_key: :player_id,
          drawer: [:overview, :attributes],
          actions: [:start_game, :move, :submit_score, :get_leaderboard, :send_challenge],
          columns: [
            %{name: :player_id, type: :string, label: "Player ID", sortable: true, filterable: true, badge: false},
            %{name: :score, type: :integer, label: "High Score", sortable: true, filterable: false, badge: false},
            %{name: :snake_length, type: :integer, label: "Max Length", sortable: true, filterable: false, badge: false},
            %{name: :apples_eaten, type: :integer, label: "Apples Eaten", sortable: true, filterable: false, badge: false},
          ]
        },
      ]
    }
  ],
  entities: [
  ]
}
