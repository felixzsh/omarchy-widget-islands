# Omarchy Bar with Rails

Quickshell **bar → bar with rails** — a single always-visible main bar wrapped by 3 thin rails that form a frame around the workspace. Built for when `omarchy bar` is full: instead of cramming more widgets into one bar, you distribute them around the perimeter without clutter.

> Seeded from upstream `omarchy.bar` via `git subtree split --prefix=shell/plugins/bar`. Keeps full compatibility with `bar.layout`. The main bar behaves exactly like the native bar; the rails are additive. **`Bar.qml` stays verbatim upstream and is never edited.**

- `manifest.json` declares `id: felixzsh.rails`, `kinds: ["bar"]`, `entryPoints.bar: "RailsBar.qml"`.
- `Bar.qml` + `BarModel.js` + `widgets/` + `indicators/` are **verbatim upstream** (`shell/plugins/bar/`). Never edit them — they exist so `git merge bar-update` stays conflict-free. Tests like `bar-test.sh` read `Bar.qml` directly.
- `RailsBar.qml` is the thin wrapper (plain props, no `required`): parses `bar.rails` via `RailModel.js`, instantiates `Bar { id: innerBar }` directly (same-dir implicit QML type, `required` satisfied at creation), and creates `Rails/RailPanel.qml` ×3 per screen (filtered by `edge !== position`). The `omarchy-shell` host injects `barConfig` (the `bar:` subtree) into `RailsBar.qml`; the wrapper forwards it to `innerBar`.
- `RailModel.js` normalizes `bar.rails` and exposes `railThickness`, per-section helpers, plus the ported `nearestScreenEdge` for drag-swap.
- `Rails/RailModuleSlot.qml` mounts rail widgets (registry/custom modules) with extra `railEdge`/`railSection` props; `Rails/RailHints.qml` paints the dots.
- Rails base (`8px`) are `WlrLayer` + `ExclusionMode.Auto` — they reserve `exclusive_zone` and windows re-adjust. Future deformations (pin/island/half-moon) are overlay `Ignore` and never touch `reserved` (Celestia pattern for the deformable part).

## Installation

```bash
omarchy plugin add https://github.com/felixzsh/omarchy-frame --enable --yes
```

## Configuration — `~/.config/omarchy/shell.json`

Lives under `bar:` alongside `position`/`transparent`/`layout`. If `bar.rails` is missing, rails are disabled (main bar only).

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "transparent": false,
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left": [{ "id": "omarchy.menu" }, { "id": "omarchy.workspaces" }],
      "center": [{ "id": "omarchy.indicators" }, { "id": "omarchy.clock", "format": "dddd HH:mm" }],
      "right": [{ "id": "omarchy.tray" }, { "id": "omarchy.audio" }]
    },
    "rails": {
      "enabled": true,
      "trigger": "hover",
      "top":    { "left": [], "center": [], "right": [] },
      "bottom": { "left": [{ "id": "omarchy.bluetooth" }], "center": [], "right": [{ "id": "omarchy.monitor", "pinned": true }] },
      "left":   { "left": [], "center": [{ "id": "omarchy.tray", "pinned": true }], "right": [] },
      "right":  { "left": [], "center": [{ "id": "omarchy.audio" }], "right": [] }
    }
  }
}
```

- `position` still drives the main bar (`top|bottom|left|right`). The edge equal to `position` is never instantiated as a rail (`RailPanel.shouldShow` filters `edge !== position`).
- `rails[edge][section]` are 3 lists per rail (`left/center/right`) with the same shape as `bar.layout` (`{id, ...settings, pinned?}`).
- `trigger` (`"hover"` | `"click"`, default `"hover"`) is single for all rails: highlight always on hover, open on hover vs on click.
- `pinned:true` is valid from MVP (e.g. `{ "id": "omarchy.tray", "pinned": true }`) but has no effect in MVP — reserved for post-MVP pin per section.
- `enabled:false` or missing → main bar only (safe fallback). Falls back gracefully even if the plugin fails to load (`shell.qml` `failedBarId` → `omarchy.bar`).

> The main bar inherits everything from `omarchy.bar` (see `README.orig.md` for the full catalogue). Rails inherit ~90% — see differences below.

## Rails — thickness, placement and rounding

- **Thickness** `railCollapsedSize = RailModel.railThickness(barSize)` → `~1/3` of `barSize` (`Style.qml:341` `bar.sizeHorizontal 26` / `sizeVertical 28` with `scale-with-font`). No token in MVP.
- **Placement** Trapped frame — no overlap: `main` (on `WlrLayer.Top` = protocol `top` 3, same as `BarPanel` `Bar.qml:1024`) gets the full `usableArea` (`0,0 1280×24` if `top` → size/position untouched). The 3 rails (also `WlrLayer.Top`, mapped **after** `main` — `Bar { id: innerBar }` before rails `Variants` in `RailsBar.qml`) are placed in the already-shrunken `usableArea` so side rails span only **between** `main` and parallel (trapped, e.g. left rail `0,24 8×696` when `main top`), touching main/parallel at the exact line. Same `background` → continuous frame with no gap and no `z` conflict. Hyprland `arrangeLayersForMonitor` (Renderer.cpp:2673) orders by protocol layer then map order. Always think relative to `position`.
- Rails base are `WlrLayer.Top` + `ExclusionMode.Auto` (`exclusive_zone = 8px`) and **do** reserve (`reserved` e.g. `main top` → `[8,24,8,8]`). Future deformations (pin/island) are overlay `Ignore`. Rails follow `innerBar.barHidden` — `omarchy bar off` hides them too (unmap — rails are 8px strips so rebuild cost is trivial).
- **Rounding** deferred in MVP: side rails straight (`radius 0`). Future half-moon will deform the trapped surface with `Shape`/`PathArc`.

## Interaction MVP — 3 thirds per rail → dot clusters centered → panel

Rails never show widgets directly. Only **dots** are visible and always centered:

- Each rail is split into **3 equal thirds** (`left` 0–33%, `center` 33–66%, `right` 66–100%) which are the **hitbox** for each section. Each third is `1/3` of the rail length and responds to `hover`/`click` anywhere in the third, not just on the `2×2` dots.
- Per section, **one dot per widget** (`sectionEntries(edge,section).length`), always **centered in its third** (`Row`/`Column` centered, `2×2` `radius 1` `opacity 0.35` `spacing 2` `barForeground`). More widgets → more dots but always centered; empty section → no dots but third still exists (doesn't open panel).
- **Highlight always, trigger configurable:** `bar.rails.trigger: "hover"|"click"` (default `hover`) is single for all rails. Entering any part of the third highlights its dots `0.35 → 0.6` always; if `trigger=="hover"` it also opens the panel immediately, if `trigger=="click"` it only highlights and waits for click in the third.
- The panel is a small container (`PopupWindow` + `BorderSurface`, `Slide`, overlay `Ignore`) anchored to the **third** (not the dot) with gravity toward the workspace:
  - Content: widgets of that section in a row parallel to the rail (`Row` for `top/bottom`, `Column` for `left/right`), each in `RailModuleSlot`.
  - Click widget → tries `shell.summon(id)` / `innerBar.summonBarWidget(id)` (host duck contract), fallback to item shape contract, then closes. Also closes when leaving third+panel (grace ~420ms) or click outside.

After MVP we will explore a pinned-fixed mode per section where the rail visually widens in that section to `barSize` with a half-moon, still `Ignore`.

## Widgets & compatibility

- Any `id` that works in `bar.layout` works in `rails` (`omarchy.*`, `type: "command"` with `exec`, `type: "qml"` with `source`). See `README.orig.md#custom-user-modules`.
- The same widget can be in main and in a rail at the same time (duplicated) — useful for testing. To move it, use `omarchy bar move` or edit `shell.json` directly.
- `widgets/` + `indicators/` in this repo are **merge anchors** (verbatim upstream) — at runtime widgets resolve via `barWidgetRegistry` from the host, not from this plugin dir.

## Properties available to widgets

Same as the native bar (`README.orig.md#bar-properties-available-to-widgets`), injected as `bar`, `moduleName`, `settings`:

- `bar.foreground`, `bar.background`, `bar.urgent`, `bar.fontFamily`, `bar.position`, `bar.vertical`, `bar.barSize`, `bar.railCollapsedSize`, `bar.railExpandedSize`, `bar.run(command)`, `bar.showTooltip`/`hideTooltip`, `bar.requestPopout`/`releasePopout`

Rail widgets receive `bar: innerBar` (full native API for free) plus `railEdge`/`railSection` via `RailModuleSlot` if they need to adapt to vertical/horizontal layout. The host also reads `shell.bar.barHidden`/`barSize`/`position` through the wrapper (aliases to `innerBar`).

## Development

See `cmds.md` (cheatsheet) and `plan.md` (design + checkboxes). Validation:

```bash
qmllint RailsBar.qml Bar.qml Rails/*.qml
test/rails-test.sh
test/run-upstream.sh  # 6 stable bar tests — Bar.qml pristine so they always pass
```

To pull upstream changes: `cmds.md#3` (`git subtree split --prefix=shell/plugins/bar upstream/quattro -b bar-update && git merge bar-update`). `Bar.qml` stays untouched by construction → pulls are trivial (only new files).

## Differences from `omarchy.bar`

| Aspect | `omarchy.bar` | `felixzsh.rails` |
|---|---|---|
| Entry point | `Bar.qml` | `RailsBar.qml` wraps `Bar.qml` (verbatim) + 3 `RailPanel` |
| Surfaces | 1 `BarPanel` per monitor | 1 `BarPanel` + 3 `RailPanel` per monitor |
| Hyprland reservation | `top`/`bottom`/`left`/`right` per `position` | `main` + 3 rails base (`8px`) reserve; deformations overlay |
| Main width | Full when no side rails | Always full (`0,0 1280×24` if top), rails trapped between main and parallel, touching at junctions |
| Rail content | N/A | 3 thirds per rail, 1 dot per widget centered in its third → overlay panel |
| Rounding | `Style.cornerRadius` on bar | Deferred in MVP (straight); future half-moon on side rails |
| `barHidden` | hides main | hides main + rails |

Original docs kept in `README.orig.md`.
