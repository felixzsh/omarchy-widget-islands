# Omarchy Bar with Rails

Quickshell **bar → bar with rails** — a single always-visible main bar wrapped by 3 thin rails that form a frame around the workspace. Built for when `omarchy bar` is full: instead of cramming more widgets into one bar, you distribute them around the perimeter without clutter.

> Seeded from upstream `omarchy.bar` via `git subtree split --prefix=shell/plugins/bar`. Keeps full compatibility with `bar.layout`. The main bar behaves exactly like the native bar; the rails are additive.

- `manifest.json` declares `id: felixzsh.rails`, `kinds: ["bar"]`, `entryPoints.bar: "Bar.qml"`.
- `Bar.qml` + `RailModel.js` + `Rails/RailPanel.qml` form the bar with rails. The `omarchy-shell` host injects `barConfig` (the `bar:` subtree from `shell.json`).
- `RailModel.js` normalizes `bar.rails` and exposes `railThickness`, per-section helpers.
- Rails base (`8px`) are `WlrLayer.Top` + `ExclusionMode.Auto` — they reserve `exclusive_zone` and windows re-adjust. Future deformations (pin/island/half-moon) are overlay `Ignore` and never touch `reserved` (Celestia pattern for the deformable part).

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
- `pinned:true` is valid from MVP (e.g. `{ "id": "omarchy.tray", "pinned": true }`) but has no effect in MVP — reserved for post-MVP pin per section.
- `enabled:false` or missing → main bar only (safe fallback).

> The main bar inherits everything from `omarchy.bar` (see `README.orig.md` for the full catalogue). Rails inherit ~90% — see differences below.

## Rails — thickness, placement and rounding

- **Thickness** `railCollapsedSize = RailModel.railThickness(barSize)` → `~1/3` of `barSize` (`Style.qml:341` `bar.sizeHorizontal 26` / `sizeVertical 28` with `scale-with-font`). No token in MVP.
- **Placement** The frame wraps the workspace and reserves its thin base:
  - `main top` → main `0,0 1280x24` full, side rails `0,24 8x672` and `1256,24 8x672` (start after `barSize`, never steal width from main), parallel `0,696 1280x24` full.
  - Analogous for `bottom/left/right` (`railMainInset` + `railAnchors`).
  - Rails base are `WlrLayer.Top` + `ExclusionMode.Auto` with `exclusive_zone = 8px` — they **do** reserve and windows re-adjust (`reserved` e.g. `[8,24,8,24]`). Any future deformation (pin/island/half-moon) is overlay `Ignore` and never touches `reserved`.
- **Rounding** `Style.cornerRadius` (`decoration:rounding`) does not affect main/parallel (straight). Only the side rails draw a half-moon at both ends (intersection with main and with parallel) via `BorderSurface`/`Shape` with `PathArc` radius `cornerRadius`. If `cornerRadius==0` they stay straight. It's the simplest hack to look rounded without clipping the main bar.

## Interaction MVP — dots per section → container panel

Rails never show widgets directly. Only **dots** are visible:

- Per rail, **max 3 dots**, one per `left/center/right` **that has widgets** (`sectionHasWidgets`). If a section is empty, its dot is not drawn. Empty rail → 0 dots.
- Horizontal (`top/bottom`) → centered `Row`; vertical (`left/right`) → centered `Column`; `2x2` `radius 1`, `opacity 0.35`, `barForeground`.
- **Click** (or hover) on a dot opens a **small container panel** anchored to the dot (`PopupWindow` + `BorderSurface`, `Slide`, `WlrLayer.Top` `Ignore`):
  - Content: the widgets of that section (`railEntries(edge, section)`) in a row parallel to the rail (`Row` for `top/bottom`, `Column` for `left/right`), each in `RailModuleSlot`.
  - Click a widget in the panel → fires its real action (`pressModuleClickTarget`) and the panel closes (mimics a click from the main bar at that position). Click outside / `onExited` also closes it.

After MVP we will explore a pinned-fixed mode per section where the rail visually widens in that section to `barSize` with a half-moon, still `Ignore`.

## Widgets & compatibility

- Any `id` that works in `bar.layout` works in `rails` (`omarchy.*`, `type: "command"` with `exec`, `type: "qml"` with `source`). See `README.orig.md#custom-user-modules`.
- The same widget can be in main and in a rail at the same time (duplicated) — useful for testing. To move it, use `omarchy bar move` or edit `shell.json` directly.

## Properties available to widgets

Same as the native bar (`README.orig.md#bar-properties-available-to-widgets`), injected as `bar`, `moduleName`, `settings`:

- `bar.foreground`, `bar.background`, `bar.urgent`, `bar.fontFamily`, `bar.position`, `bar.vertical`, `bar.barSize`, `bar.railCollapsedSize`, `bar.railExpandedSize`, `bar.run(command)`, `bar.showTooltip`/`hideTooltip`, `bar.requestPopout`/`releasePopout`

Rail widgets additionally receive `railEdge`/`railSection` via `RailModuleSlot` if they need to adapt to vertical/horizontal layout.

## Development

See `cmds.md` (cheatsheet) and `plan.md` (design + checkboxes). Validation:

```bash
qmllint Bar.qml
test/rails-test.sh
test/run-upstream.sh  # 6 stable bar tests, overlay without reservation
```

To pull upstream changes: `cmds.md#3` (`git subtree split --prefix=shell/plugins/bar upstream/quattro -b bar-update && git merge bar-update`).

## Differences from `omarchy.bar`

| Aspect | `omarchy.bar` | `felixzsh.rails` |
|---|---|---|
| Surfaces | 1 `BarPanel` per monitor | 1 `BarPanel` + 3 `RailPanel` per monitor |
| Hyprland reservation | `top`/`bottom`/`left`/`right` per `position` | `main` + 3 rails base (`8px`) reserve; deformations overlay |
| Main width | Full when no side rails | Always full (`0,0 1280x24` if top), side rails start after `barSize` |
| Rail content | N/A | Only dots per section → overlay container panel |
| Rounding | `Style.cornerRadius` on bar | Main/parallel straight, side rails half-moon at ends |

Original docs kept in `README.orig.md`.
