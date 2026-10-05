%{
  id: :sample_wasm,
  name: "sample_wasm",
  type: :wasm,
  version: "1.0.0",
  context: :global,
  entry_point: "sample_wasm.wasm",
  dependencies: [:database],
  provides: [:sample_wasm],
  category: "Utility",
  dashboard_view: %{id: :sample_wasm, title: "Sample WASM Plugin", icon: "🔧"},
  services: [
    %{
      name: :sample_wasm,
      actions: [
        %{name: :ping, mode: :sync, scope: :global, transport: :auto, arity: 0, params: [], returns: :integer},
        %{name: :increment, mode: :sync, scope: :global, transport: :auto, arity: 2, params: [counter_id: :integer, amount: :integer], returns: :integer},
        %{name: :echo, mode: :sync, scope: :global, transport: :auto, arity: 1, params: [value: :integer], returns: :integer},
      ],
      events: [
        %{name: :value_changed, topic: "sample:events", scope: :global},
      ],
      resources: [
        %{
          name: :counters,
          primary_key: :counter_id,
          drawer: [:overview, :attributes],
          actions: [:ping, :increment, :echo],
          columns: [
            %{name: :counter_id, type: :integer, label: "Counter ID", sortable: true, filterable: true, badge: false},
            %{name: :value, type: :integer, label: "Value", sortable: true, filterable: false, badge: false},
            %{name: :status, type: :string, label: "Status", sortable: false, filterable: false, badge: true},
          ]
        },
      ]
    }
  ],
  entities: []
}
