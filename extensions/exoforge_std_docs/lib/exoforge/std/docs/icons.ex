defmodule Exoforge.Std.Docs.Icons do
  @moduledoc """
  The Studio icon set for the docs extension.

  Third copy, after `dashboard` and `dashboard_views`. The extensions are compile-independent by
  design, so the set is data duplicated rather than coupled; `ui_standard_test.exs` asserts all
  three are identical, so a divergence fails the build instead of showing up as a missing icon.
  """
  use Phoenix.Component

  @icons %{
    timeline:
      "M2.04 12.32a1.01 1.01 0 010-.64C3.42 7.51 7.36 4.5 12 4.5s8.57 3.01 9.96 7.18c.07.21.07.43 0 .64C20.58 16.49 16.64 19.5 12 19.5s-8.57-3.01-9.96-7.18z M15 12a3 3 0 11-6 0 3 3 0 016 0z",
    replay: "M3 3v6h6 M3.51 15a9 9 0 102.13-9.36L3 9",
    capture: "M12 3v3 M12 18v3 M3 12h3 M18 12h3 M12 8a4 4 0 100 8 4 4 0 000-8z",
    bolt: "M13 2L3 14h6l-2 8 10-12h-6l2-8z",
    pin: "M12 17v5 M9 3h6l-1 7 4 4H6l4-4-1-7z",
    search: "M21 21l-6-6 M17 11a6 6 0 11-12 0 6 6 0 0112 0z",
    download: "M12 3v12 M7 11l5 5 5-5 M4 20h16",
    upload: "M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4 M17 8l-5-5-5 5 M12 3v12",
    close: "M6 6l12 12 M18 6L6 18",
    check: "M4 12l5 5L20 6",
    alert:
      "M12 9v4 M12 17h.01 M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z",
    moon: "M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z",
    sun:
      "M12 4V2 M12 22v-2 M4 12H2 M22 12h-2 M5.64 5.64L4.22 4.22 M19.78 19.78l-1.42-1.42 M5.64 18.36l-1.42 1.42 M19.78 4.22l-1.42 1.42 M12 7a5 5 0 100 10 5 5 0 000-10z",
    gear:
      "M12 15a3 3 0 100-6 3 3 0 000 6z M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 11-4 0v-.09A1.65 1.65 0 008 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06A1.65 1.65 0 003.6 15a1.65 1.65 0 00-1.51-1H2a2 2 0 110-4h.09A1.65 1.65 0 003.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06A1.65 1.65 0 009 4.6 1.65 1.65 0 0010 3.09V3a2 2 0 114 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06A1.65 1.65 0 0020.4 9c.14.36.48.62.87.7H21a2 2 0 110 4h-.09a1.65 1.65 0 00-1.51 1z",
    trash: "M3 6h18 M8 6V4h8v2 M6 6l1 14h10l1-14 M10 11v6 M14 11v6",
    save: "M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z M17 21v-8H7v8 M7 3v5h8",
    folder: "M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z",
    graph: "M3 3v18h18 M7 14l4-4 3 3 5-6",
    console: "M4 17l6-6-6-6 M12 19h8",
    box: "M21 8l-9-5-9 5v8l9 5 9-5V8z M3 8l9 5 9-5 M12 13v8",
    radio:
      "M12 12m-2 0a2 2 0 104 0 2 2 0 10-4 0 M16.24 7.76a6 6 0 010 8.49 M7.76 16.24a6 6 0 010-8.49 M19.07 4.93a10 10 0 010 14.14 M4.93 19.07a10 10 0 010-14.14",
    chart: "M18 20V10 M12 20V4 M6 20v-6",
    trending: "M23 6l-9.5 9.5-5-5L1 18 M17 6h6v6",
    lock: "M5 11h14v10H5V11z M8 11V7a4 4 0 118 0v4",
    key:
      "M21 2l-2 2 M11.485 11.485a5.5 5.5 0 11-7.778 7.778 5.5 5.5 0 017.778-7.778z M11.485 11.485L15.5 7.5 M15.5 7.5l3 3L22 7l-3-3",
    users:
      "M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2 M9 11a4 4 0 100-8 4 4 0 000 8z M23 21v-2a4 4 0 00-3-3.87 M16 3.13a4 4 0 010 7.75",
    user: "M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2 M12 11a4 4 0 100-8 4 4 0 000 8z",
    shield: "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z",
    database:
      "M12 8c4.97 0 9-1.34 9-3s-4.03-3-9-3-9 1.34-9 3 4.03 3 9 3z M21 12c0 1.66-4 3-9 3s-9-1.34-9-3 M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5",
    book: "M2 3h6a4 4 0 014 4v14a3 3 0 00-3-3H2V3z M22 3h-6a4 4 0 00-4 4v14a3 3 0 013-3h7V3z",
    file:
      "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6z M14 2v6h6 M16 13H8 M16 17H8",
    archive: "M21 8v13H3V8 M1 3h22v5H1z M10 12h4",
    play: "M5 3l14 9-14 9V3z",
    pause: "M6 4h4v16H6z M14 4h4v16h-4z",
    globe:
      "M12 12m-10 0a10 10 0 1019.9 0 10 10 0 10-19.9 0 M2 12h20 M12 2a15.3 15.3 0 010 20 15.3 15.3 0 010-20z",
    compass:
      "M12 12m-10 0a10 10 0 1019.9 0 10 10 0 10-19.9 0 M16.24 7.76l-2.12 6.36-6.36 2.12 2.12-6.36 6.36-2.12z",
    paperclip:
      "M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48",
    monitor: "M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z M8 21h8 M12 17v4",
    clipboard:
      "M16 4h2a2 2 0 012 2v14a2 2 0 01-2 2H6a2 2 0 01-2-2V6a2 2 0 012-2h2 M9 2h6a1 1 0 011 1v2a1 1 0 01-1 1H9a1 1 0 01-1-1V3a1 1 0 011-1z",
    crown: "M3 17l-1-9 5 4 5-8 5 8 5-4-1 9H3z M3 17h18",
    mobile: "M7 2h10a2 2 0 012 2v16a2 2 0 01-2 2H7a2 2 0 01-2-2V4a2 2 0 012-2z M12 18h.01",
    gamepad:
      "M6 12h4 M8 10v4 M15 13h.01 M18 11h.01 M17.32 5H6.68a4 4 0 00-3.978 3.59c-.006.052-.01.101-.017.152C2.604 9.416 2 14.456 2 16a3 3 0 003 3c1 0 1.5-.5 2-1l1.414-1.414A2 2 0 019.828 16h4.344a2 2 0 011.414.586L17 18c.5.5 1 1 2 1a3 3 0 003-3c0-1.545-.604-6.584-.685-7.258-.007-.05-.011-.1-.017-.151A4 4 0 0017.32 5z",
    hard_drive:
      "M22 12H2 M5.45 5.11L2 12v6a2 2 0 002 2h16a2 2 0 002-2v-6l-3.45-6.89A2 2 0 0016.76 4H7.24a2 2 0 00-1.79 1.11z M6 16h.01 M10 16h.01",
    target:
      "M12 12m-10 0a10 10 0 1019.9 0 10 10 0 10-19.9 0 M12 12m-6 0a6 6 0 1012 0 6 6 0 10-12 0 M12 12m-2 0a2 2 0 104 0 2 2 0 10-4 0",
    sliders: "M4 21v-7 M4 10V3 M12 21v-9 M12 8V3 M20 21v-5 M20 12V3 M1 14h6 M9 8h6 M17 16h6"
  }

  @doc """
  An icon by name from the set above. Anything else — a glyph an extension's author chose —
  renders as text, so caller-controlled icons keep working.
  """
  attr(:icon, :string, required: true)
  attr(:class, :string, default: "w-4 h-4")

  def studio_icon(assigns) do
    path = Map.get(@icons, String.to_atom(assigns.icon))

    if path do
      assigns = assign(assigns, :path, path)

      ~H"""
      <span class={"inline-flex items-center justify-center shrink-0 #{@class}"}>
        <svg class="w-full h-full" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d={@path} />
        </svg>
      </span>
      """
    else
      ~H"""
      <span class={"inline-flex items-center justify-center shrink-0 #{@class}"}><%= @icon %></span>
      """
    end
  end

  @doc "The SVG path for a name, or nil. For modules that emit raw HTML."
  def path(name), do: Map.get(@icons, String.to_atom(name))
end
