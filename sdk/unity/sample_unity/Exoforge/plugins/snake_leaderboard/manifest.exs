%{
  id: :snake_leaderboard,
  name: "snake_leaderboard",
  type: :native,
  version: "1.0.0+1.f9ac5087",
  context: :global,
  entry_point: "snake_leaderboard",
  dependencies: [:database],
  provides: [:snake_leaderboard],
  category: "Game",
  dashboard_view: %{id: :snake_leaderboard, title: "Snake Leaderboard", icon: "🏆"},
  services: [
    %{
      name: :snake_leaderboard,
      actions: [
        %{name: :submit_score, mode: :sync, scope: :global, transport: :auto, arity: 4, params: [player_id: :string, name: :string, score: :integer, snake_length: :integer], returns: :integer},
        %{name: :get_leaderboard, mode: :sync, scope: :global, transport: :auto, arity: 1, params: [limit: :integer], returns: :map},
      ],
      events: [
      ],
      resources: [
        %{
          name: :snake_scores,
          primary_key: :player_id,
          drawer: [:overview, :attributes],
          actions: [:submit_score, :get_leaderboard],
          columns: [
            %{name: :player_id, type: :string, label: "Player ID", sortable: true, filterable: true, badge: false},
            %{name: :name, type: :string, label: "Player", sortable: true, filterable: true, badge: false},
            %{name: :score, type: :integer, label: "High Score", sortable: true, filterable: false, badge: false},
            %{name: :snake_length, type: :integer, label: "Max Length", sortable: true, filterable: false, badge: false},
            %{name: :updated_at, type: :integer, label: "Updated", sortable: true, filterable: false, badge: false},
          ]
        },
      ]
    }
  ],
  entities: []
}
