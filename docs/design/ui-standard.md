# Exoforge Studio UI Standard — Colour, Radius, Motion & Layout

> Applies to `extensions/exoforge_std_dashboard` and `extensions/exoforge_std_dashboard_views`.
> Enforced by `test/ui_standard_test.exs` — read the test if this page and the code disagree.

---

## 1. The one convention

> **Templates are authored in light-theme Tailwind classes or semantic `.exo-*` classes.
> The remap in `priv/static/vendor/exoforge-studio.css` is the only dark-mode mechanism.**

`dark:` variants are forbidden. Two mechanisms is how the theme drifted in the first place.

The remap is a list: `html:not(.light) .bg-white { … }`. A class a template uses and the list does
not cover renders as a light box with light text on the dark theme. So:

- **A new tinted background needs its exact alpha step added to the remap in the same change.**
  `bg-amber-500/10` is a different selector from `bg-amber-50`; both must be listed. The test diffs
  the tinted backgrounds templates use against the remap and fails on a miss.
- **Solid fills need no entry** — `bg-primary-600`, `bg-emerald-500`, `bg-red-600` are the same
  colour in both themes. A button is the same button.
- **Intentionally-dark chrome** (log console, code blocks, event dock) uses the
  `gray-800/900/950` and `slate-800/900/950` families, which the remap deliberately does not touch.
  `.exo-terminal` is available for new chrome that should stay dark in both themes.
- Theme toggle flips `html.light` / `html.dark` (see `Layouts.root/1` and `LoginController`).

---

## 2. Colour

One hue, one name. The palette is unchanged; only the vocabulary is.

| Role | Prefix | Use for |
| :--- | :--- | :--- |
| **Brand** | `primary` | Primary buttons, active nav, focus ring, selection, links |
| **Success** | `emerald` | Healthy, confirmed, live |
| **Warning** | `amber` | Degraded, needs attention |
| **Danger** | `red` | Errors, destructive actions |
| **Info** | `blue` | Neutral informational accents, secondary data series |

Retired aliases (the test fails on them): `purple`, `violet`, `indigo`, `sky`, `cyan`, `rose`,
`yellow`, `green`, `pink`, `fuchsia`. They were the same rendered colour under a second name, which
is how two screens ended up with two different violets.

Contrast rules:

- Tinted surfaces pair **tinted bg + tinted text + tinted border** from the same hue:
  `bg-emerald-50 text-emerald-800 border-emerald-200`. Never `text-gray-900` on a tinted box.
- `text-white` only on solid fills (`bg-primary-600`, `bg-red-600`, dark panels).
- No hexes in HEEx class or style attributes. Charts may hold literal hexes for canvas rendering,
  from one palette map, not ad-hoc.

Surfaces and text come from tokens (`--exo-surface*`, `--exo-text*`, `--exo-border*`,
`--exo-status*`, `--exo-info`). The remap maps template classes onto them.

---

## 3. Radius

Radius belongs to the component kind, not to the viewport or the mood. Four values, no responsive
radius classes — a card is the same object at every screen size; screen size changes the grid.

| Kind | Class | rem |
| :--- | :--- | :--- |
| Chips, kbd, inline code, tiny icon tiles | `rounded` | 0.25 |
| Buttons, inputs, selects, small controls | `rounded-lg` | 0.5 |
| Cards, panels, modals, drawers, menus | `rounded-xl` | 0.75 |
| Pills, status dots, avatars | `rounded-full` | — |

`rounded-md`, `rounded-sm`, `rounded-2xl`, `rounded-3xl` are retired. The CSS variables
(`--exo-radius-*`) mirror this scale, so `.exo-btn` and `rounded-lg` are the same number.

---

## 4. Motion

One easing, three durations.

| Token | Value | Use for |
| :--- | :--- | :--- |
| `--exo-ease` | `cubic-bezier(0.16, 1, 0.3, 1)` | Everything |
| `--exo-dur-fast` | 150 ms | Hover, focus, colour changes |
| `--exo-dur-enter` | 200 ms | Modals, drawers, toasts, menus, tabs |

300 ms is `duration-300` in a template — full-screen overlays and console collapse only.

- Prefer `transition-colors`. `transition-all` only when width, height, shadow or transform
  genuinely animates.
- Looping animations (`animate-pulse`, `animate-ping`) are for live indicators only.
- Every `@keyframes` must be listed in the `prefers-reduced-motion` block in the same file.
- No parallax, no scroll-jacking, no spring libraries. This is a dense operations UI.

---

## 5. Typography & density

- **`text-xs` (12 px) is the floor** for anything a user reads.
- `text-[10px]` only for uppercase tracked micro-labels (badges, column headers, units).
  `text-[8px]`, `text-[9px]`, `text-[13px]` are banned — the test fails on them.
- Body `text-xs`/`text-sm`; page titles `text-lg`/`text-xl`. Card headings are `text-sm` bold with a
  `text-xs` muted subtitle — that is what `.exo-title` / `.exo-subtitle` are.
- The font is the `--exo-font` system stack. No webfont: it loads instantly, works offline, and
  reads native on each OS.

---

## 6. Layout — keeping it from looking generated

The palette is the product's; the tells are in how it is applied. In priority order:

1. **Flat surfaces, border first.** Dark separates layers by tone; light by border plus the soft
   card shadow. Not both as decoration.
2. **Depth budget.** `shadow-2xl` only on true top layers (modal, drawer, toast, popover). Cards use
   `--exo-shadow-card` in light; on dark the remap zeroes `shadow-sm/md/card` because a drop shadow
   on a dark surface is haze.
3. **Ring budget.** `ring-*` for `focus-visible` and explicit selection only (grid edit mode, active
   filter). A decorative halo is a border.
4. **No gradients.** Brand colour is an accent, not a background wash. The two gradient banners were
   replaced with flat `bg-white` cards and a `border-primary-200` edge.
5. **One accent per view.** A screen gets one hue doing accent work, plus status colours in badges.
   Charts are exempt — data series need distinct hues.
6. **Cards calm down.** One border, one radius, one padding step. Reach for `.exo-card` instead of
   re-stacking `bg-white border rounded-xl p-6 shadow-card` per view.
7. **Icons over emoji** in navigation, card headers and buttons (`Components.icon/1`). Empty states
   may keep emoji. No new emoji in interactive UI — still being migrated, not yet enforced.

---

## 7. What the test enforces

`extensions/exoforge_std_dashboard/test/ui_standard_test.exs`, runs in `just test`:

| Check | Catches |
| :--- | :--- |
| Retired hue aliases | a second name for a colour we already have |
| `dark:` variants | a second dark-mode mechanism |
| `rounded-2xl/3xl/md/sm` | radius drift |
| `text-[8px]/[9px]/[13px]` | the type floor |
| `bg-gradient-` | background washes |
| Tinted backgrounds not in the remap | **the actual theming bug** — light box, light text |

It is a grep over `class=` attributes, not a parser. A violation fails with a `file:line` and the
offending line, so the fix is local.
