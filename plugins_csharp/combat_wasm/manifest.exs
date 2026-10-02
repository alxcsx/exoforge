%{
  id: :combat_wasm,
  name: "combat_wasm",
  type: :wasm,
  version: "0.1.0",
  context: :global,
  entry_point: "combat_wasm.wasm",
  dependencies: [:database],
  provides: [:combat],
  services: [
    %{
      name: :combat,
      actions: [
        %{name: :ping, mode: :sync, scope: :global, arity: 0, params: [], returns: :integer},
        %{name: :attack, mode: :sync, scope: :global, arity: 3, params: [attacker_id: :integer, target_id: :integer, damage: :integer], returns: :integer},
      ],
      events: [
        %{name: :player_damaged, topic: "combat:events", scope: :global},
      ],
      resources: [
        %{
          name: :combatants,
          primary_key: :entity_id,
          drawer: [:overview, :attributes, :events],
          actions: [:ping, :attack],
          columns: [
            %{name: :entity_id, type: :integer, label: "Entity ID", sortable: true, filterable: true, badge: false},
            %{name: :health, type: :integer, label: "Health Points", sortable: true, filterable: false, badge: false},
            %{name: :status, type: :string, label: "Combat Status", sortable: false, filterable: false, badge: true},
          ]
        },
      ]
    }
  ],
  entities: [
  ]
}
