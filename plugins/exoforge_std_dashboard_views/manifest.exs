%{
  id: :exoforge_std_dashboard_views,
  name: "exoforge_std_dashboard_views",
  version: "0.1.0",
  type: :elixir,
  entry_point: Exoforge.Std.DashboardViews,
  provides: [:dashboard_view],
  dependencies: [Exoforge.Std.Services.Dashboard],
  category: "Studio",
  dashboard_view: nil
}
