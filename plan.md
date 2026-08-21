# Plan — Bar with Rails (bar → bar with rails)

## 0. Principles — Always think relative to main

> **Golden rule to avoid overfitting to `main top`:** reason everything relative to the current `position` of the main bar. There is no absolute "top/bottom is parallel and left/right are side" — instead: **main** is at `position`, **parallel** is the opposite edge of `position`, and **side rails** are the two edges perpendicular to `position`. Main and parallel always span the full edge; side rails are always trapped between them. If you hardcode `top`, `swap` to `left/right` will break.

- [ ] **Main bar untouched — literally:** `Bar.qml`, `BarModel.js`, `widgets/`, `indicators/` are verbatim copies of `shell/plugins/bar/` upstream and **never edited**. The plugin entry point is `RailsBar.qml` (`manifest.json: entryPoints.bar`). `Bar.qml` stays byte-identical so `git subtree split --prefix=shell/plugins/bar` never produces conflicts. Rails are additive and live in `RailsBar.qml` + `Rails/` + `RailModel.js`.
- [ ] **Rails base reserve, deformations don't:** idle rails (`railThickness = 1/3 barSize`) are `WlrLayer` with `ExclusionMode.Auto` (`exclusive_zone = railThickness`) and reserve `reserved` (`8px` per rail with widgets). Future deformations (pin to `barSize`, island/trapezoid, half-moon `cornerRadius`) are **overlay** (`Ignore`) and never touch `reserved` (Celestia).
- [ ] **Main invariant — rails never affect main:** `main` keeps its full size/position and behavior regardless of rails (e.g. `main top` stays `0,0 1280×24`). Rails and main share the same `background` and appear as one continuous frame with no gaps. How that continuity is achieved is up to the implementer — the invariant and visual expectation are what matter.
- [ ] **Rail thickness = 1/3 main:** `RailModel.railThickness(barSize)` (`Style.qml:341` `bar.sizeHorizontal 26` / `sizeVertical 28` with `scale-with-font`). No token in MVP.
- [ ] **Rounding deferred:** half-moon on side rails requires clipping overlapped corners; in MVP side rails are straight (`radius 0`). `Style.cornerRadius` will be applied later with `Shape`/`PathArc` or trapped inner background.
- [ ] **Per-monitor like the bar:** `Variants { Quickshell.screens }` `Bar.qml:951` — 1 main + 3 rails per monitor.

### 0.1 Upstream compat — why Bar.qml stays pristine

- [ ] **No renames, no forks of the engine:** `Bar.qml` is the implicit QML type `Bar` for the whole plugin dir. `RailsBar.qml` instantiates it directly `Bar { id: innerBar }` (same-dir implicit import) and forwards host props. No `Loader`, no rename detection gamble. Pulls `git merge bar-update` never touch `Bar.qml` → zero conflicts by construction. If upstream adds `RailsBar.qml` in the future (unlikely), we would rename the wrapper without touching the engine.
- [ ] **Strict tests `bar-test.sh:12` intact:** upstream greps `$ROOT/shell/plugins/bar/Bar.qml` (`drag.target.*slot`, `centerSectionRevealHeld = true`, `BarModel.nearestDropTarget(..., root.vertical)`). With `Bar.qml` verbatim they pass without patching tests.
- [ ] **`Bar.qml:16` `required` does not break the host with direct composition:** the wrapper declares `property string omarchyPath: ""` / `property var barWidgetRegistry: null` / `property var barConfig: fallbackBarConfig` (plain, without `required`) and when instantiating `Bar { omarchyPath: root.omarchyPath; barWidgetRegistry: root.barWidgetRegistry; barConfig: root.barConfig }` satisfies the `required` at creation. No `Loader { source: ".../Bar.qml" }`.
- [ ] **`widgets/` + `indicators/` are merge anchors, not functional:** they duplicate upstream verbatim only so merges do not produce delete/modify. At runtime the engine loads widgets via `barWidgetRegistry.widgets[canonicalId]` (host) and `Indicators.qml` resolves `Qt.resolvedUrl("../indicators/" + id + ".qml")` relative to its own upstream path — never from this repo.
- [ ] **`HoverHandler` inside invisible `Loader` never fires:** `RailPanel` had `HoverHandler` inside `Loader { opacity: 0 }` when collapsed → `railHovered` never true. Put it as a direct sibling of `RailPanel` (outside `Loader`).
- [ ] **`wlr-layer-shell` and `Hyprland` — main invariant is the contract:** rails are `WlrLayer` `PanelWindow` with `ExclusionMode.Auto` and reserve `reserved` (`8px` per rail). The implementer must ensure that reservation never changes main's geometry — verify empirically with `hyprctl layers -j` (main stays `0,0 1280×24`) and `hyprctl monitors -j | reserved` (`[8,24,8,8]` for `main top`) for each `position`. The exact Hyprland mechanism (`usableArea`, layer ordering, map order) is left to the implementer to solve — the invariant is the check.

## 1. Closed Decisions

| Topic | Decision |
|---|---|
| Rail widget source | 3 lists per rail (`left/center/right`) like main. Total 12 lists. |
| Schema | `bar.rails: {enabled, trigger, top:{left,center,right:[]}, bottom:{...}, left:{...}, right:{...}}`. `enabled:false` or missing → main only. Single `trigger` for all rails. |
| Engine file | `Bar.qml` verbatim upstream, never edited. Wrapper is `RailsBar.qml` (entry point). |
| Exclusivity | Rails base reserve `8px` per rail with widgets (e.g. `main top` → `reserved` `[8,24,8,8]`); future deformations `Ignore`. |
| Rail thickness | `~1/3 barSize` (8-9px). |
| MVP Interaction | Dots per section → container panel. **Single trigger for all rails** (`bar.rails.trigger: "hover" \| "click"`, default `hover`). |
| Pin | Not in MVP. Post-MVP pin per section with visual widening to `barSize` (still `Ignore`). |
| Transparency | Inherits `bar.transparent`. |
| `barHidden` | Rails follow `innerBar.barHidden` (hide when `omarchy bar off`). `shell.bar.barHidden` is exposed from the wrapper so `notifications/Service.qml` and the host keep working. |

## 2. `shell.json` Schema

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "transparent": false,
    "centerAnchor": "omarchy.clock",
    "layout": { "left": [], "center": [], "right": [] },
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

Notes: `rails` declares 4 edges; the edge equal to `position` is never instantiated (`RailPanel.shouldShow` filters `edge !== position && railsEnabled`). `rails.trigger` is a single setting for all rails (`"hover"` | `"click"`, default `"hover"`); `RailModel.normalizeRailsConfig` normalizes it and strips unknown values. Missing `bar.rails` → rails disabled (safe fallback, main bar behaves native).

## 3. MVP — Checklist (all unchecked, from scratch)

### 3.1 Model / Config

- [ ] Create `RailModel.js` with `normalizeRailsConfig(raw, pos)`, `normalizeRailLayout`, `railThickness`, `railLayoutFor`, `hasAnyWidgets`, `sectionHasWidgets(edge,section)`, `isPinned(entry)`/`setPinned(entry,bool)` (exists from MVP so `pinned:true` is valid even though it doesn't gate anything), plus `normalizeTrigger` for `bar.rails.trigger`.
- [ ] Create `RailsBar.qml` (entry point) — plain props `omarchyPath`/`barWidgetRegistry`/`barConfig`/`shell`/`manifest` without `required`; `fallbackBarConfig` with `rails:{enabled:false, trigger:"hover", top:{...}, bottom:{...}, left:{...}, right:{...}}`; `applyBarConfig()` parses `bar.rails` via `RailModel.normalizeRailsConfig`, sets `railsEnabled`/`railsTrigger`/`railsConfig`, `barConfigSerial++`. Instantiate `Bar { id: innerBar; omarchyPath: root.omarchyPath; barWidgetRegistry: root.barWidgetRegistry; barConfig: root.barConfig; shell: root.shell; manifest: root.manifest }` directly (no `Loader`). Rails react to `barConfigSerial` + `innerBar.position`. **Do not touch `Bar.qml`.**
- [ ] `RailsBar.qml` exposes the duck contract of `shell.bar` to the host: `barHidden`/`barSize`/`position`/`vertical`/`foreground`/`background`/`fontFamily` as aliases to `innerBar.*`, and forwards `run`/`showTooltip`/`hideTooltip`/`requestPopout`/`releasePopout` + `summonBarWidget`/`hideBarWidget`/`isBarWidgetOpen`/`toggleTransparency`/`debugBarGeometry` if the host queries them (guard `typeof innerBar.fn === "function"`). `shell.configureBar` sets `shell.bar = RailsBar` automatically; rail widgets receive `bar: innerBar` (full native API).

### 3.2 Panels — Rails visual base

- [ ] `Rails/RailPanel.qml: PanelWindow` per edge (`WlrLayershell.namespace: "omarchy-rails-"+edge`), `ExclusionMode.Auto` with `exclusive_zone = railThickness` when visible and `8px` reservation per rail with widgets (e.g. `main top` → `reserved` `[8,24,8,8]`). **Expectation:** main keeps its full geometry (e.g. `0,0 1280×24` for `main top`, size/position never changes when rails appear), rails look like one frame with main (same `background`, no gaps), hidden (`barHidden` or edge has no widgets) → the panel does not reserve and does not stay visible. How the placement achieves the invariant is up to the implementer — verify empirically with `hyprctl layers -j` (geometry) and `hyprctl monitors -j | reserved` for each `position`. `rails` base are the only surfaces that touch `reserved`; future deformations stay `Ignore`.
- [ ] **Known pitfall — main must be arranged first:** if the rails' layer surfaces are mapped before main's, Hyprland insets main (`x=8` even with a correct layer). Main must be arranged first; verify order empirically via `hyprctl layers -j` (main at `x=0`). This is a constraint, not a prescribed solution — the implementer decides how to guarantee the order.
- [ ] `RailsBar.qml` instantiates `innerBar` + 3 `RailPanel` via `Variants { Quickshell.screens; delegate: Item { RailPanel edge:"top"... } }` filtered by `edge !== position && railsEnabled && hasWidgets`. Visibility also driven by `innerBar.barHidden` (hide rails when main hidden).

### 3.3 Hints — Dots per section (1 dot = 1 widget, always centered, hitbox = third)

- [ ] Each rail is split into **3 equal thirds** (`left` 0–33%, `center` 33–66%, `right` 66–100% of rail length). Each third is `parent.width/3` (`top/bottom`) or `parent.height/3` (`left/right`) and is the **hitbox** for its section: `MouseArea { anchors.fill: third; hoverEnabled: true }` fills the whole third, not just dots.
- [ ] `Rails/RailHints.qml` paints **one dot per widget** per third (`sectionEntries(edge,section).length` dots). Dots always **centered in their third** (`anchors.centerIn: parent` of third, `Row`/`Column` centered, `2×2` `radius 1` `opacity 0.35` `spacing 2`), never pinned to ends. More widgets → more dots but always centered. Empty section → third with no dots nor highlight, but hitbox still exists (doesn't open panel).
- [ ] Highlight always: when pointer enters any part of the third, its dots go `opacity 0.35 → 0.6` (or `scale 1.2`) indicating interactivity, independent of `trigger`. If `trigger=="hover"` it also opens the panel; if `trigger=="click"` it only highlights and waits for click anywhere in the third.

### 3.4 Drag & drop + Container swap (MVP) — Relative to `position`

- [ ] **Intra-main:** untouched in `innerBar` (reorder `bar.layout[section]` via `shell.mutateShellConfig`, already persists to `shell.json`).
- [ ] **Intra-rail (same edge) — MVP:** rails behave like a miniature main bar (`thickness 1/3` but same `left/center/right` logic). Dragging a widget inside the container panel of one section to another section **of the same rail** (e.g. `bottom left [bluetooth]` → `bottom center`) reorders `bar.rails[edge][section]` via `RailModel.moveModuleInConfig` + `shell.mutateShellConfig` and persists to `shell.json` in real time, just like `main`. Hitbox is the third/section, drop target is the nearest section in the same rail. Implement with `BarModel.nearestDropTarget`-like helper ported to `RailModel`.
- [ ] **Container swap (MVP):** dragging empty background of `main` or of a rail (outside dots, on the 8px rail strip itself) to another screen edge moves the **whole container** (its 3-section triplet) and swaps containers via `shell.mutateShellConfig`, persisting to `shell.json` in real time. Port `nearestScreenEdge(screenPoint,screen)` to `RailModel.js` (~15 lines, from `Bar.qml:249`) and have an own ghost in `RailsBar.qml` (do not reuse inline `BarMoveGhostPanel` from `Bar.qml`). Resolve relatively: rail(edgeA) → rail(edgeB) is `swap(rails[edgeA], rails[edgeB])`; rail(edgeA) → main(position) is `bar.position = edgeA` plus `swap(bar.layout, rails[edgeA])`; main → rail is symmetric. Verify for `main top/bottom/left/right`.

### 3.5 MVP Interaction — Container panel per third (trigger configurable)

- [ ] Single `trigger` for all (`bar.rails.trigger: "hover"|"click"`, default `hover`): **highlight always** when entering the third (`dots 0.35 → 0.6`); if `trigger=="hover"` then `hover` anywhere in the third → `showSectionPanel(edge,section)` immediately; if `trigger=="click"` hover only highlights, click anywhere in the third opens the panel. Panel stays until pointer leaves third+panel by threshold, or widget selected, or click outside.
- [ ] `showSectionPanel(edge,section)` creates `PopupWindow` + `BorderSurface` anchored to the **third** (`anchor.window = railWindow`, `anchor.rect` = third geometry, `gravity` toward workspace, `Slide`, `WlrLayer.Top`+`Ignore`).
- [ ] Content: `sectionEntries(edge, section)` in `RailModuleSlot` in a row parallel to the rail (`Row` if `top/bottom`, `Column` if `left/right`). Size = sum `implicitWidth/Height` + `Style.space`. Slots set `bar: innerBar` + `moduleName`/`settings` + `railEdge`/`railSection`.
- [ ] **Click routing:** prefer `shell.summon(id)` / `innerBar.summonBarWidget(id)` (host public/duck contract, see `shell.qml:457`, `Bar.qml:500`) with guard `typeof === "function"`; if it returns `"unknown"` (widget not registered in the engine) fallback to the item shape contract (`item.open?.()` / `item.toggle?.()`). Avoid coupling to `Bar.qml:784 pressModuleClickTarget(slot)` which requires slots registered in the engine. `hideSectionPanel()` on success. Click outside / `onExited` also closes. Rail base reserves (`Auto` 8px), container panel is overlay `Ignore` and never touches `reserved`.

### 3.6 MVP Verification — Test on all 4 `position`

- [ ] `qmllint RailsBar.qml Bar.qml Rails/*.qml` and `test/rails-test.sh` + `test/run-upstream.sh` 6/6 pass. `Bar.qml` is not edited → `bar-test.sh` keeps passing without patches.
- [ ] Visual Hyprland for `main top` and `main left` (minimum): `innerBar` at `0,0` full (`1280×24` or `28×720`), side/parallel **trapped** between main and parallel touching at junctions (no overlap), `reserved` includes `8` per rail with widgets (e.g. `main top` → `[8,24,8,8]`), windows re-adjusted without covering. Validate with `hyprctl layers -j` (positions) and `hyprctl monitors -j | reserved`.
- [ ] Click dot `left` of rail `bottom` (with `bluetooth`) opens overlay panel; click `bluetooth` fires popup and closes (without touching `reserved`). Also test with `main left` (dots offset outside overlap). Test `omarchy bar off` hides rails together with main.
- [ ] `shell.bar` contract: `notifications/Service.qml:51` (`barHidden`/`barSize`) and `shell.qml:900 summonBarWidget` keep working through the wrapper.

## 4. Post-MVP

- [ ] Rounding (half-moon): side rails with `radius = min(cornerRadius, thickness/2)` at both ends where they meet `main` and parallel. Deferred from MVP (straight `radius 0` in MVP).
- [ ] Widget drag **between** containers (post-MVP): move widgets between different rails and between `main ↔ rails` (e.g. `bottom left [bluetooth]` → `right center [audio]` or `main right [tray]` → `left center`). Intra-rail and intra-main are already MVP (3.4); this extends it across containers. Uses `slotFullRegion` (`rail:edge:section` vs `left`), `rawLayoutSection` + `moveModuleInConfig` in `RailModel`/`BarModel` and `shell.mutateShellConfig` on `bar.rails[edge][section]` or `bar.layout[section]`.
- [ ] Pin per section: fixed panel leaves rail visually widened in that section to `barSize` with half-moon, still `Ignore`.
- [ ] Theming tokens `hint-opacity`, `rail-thickness` via `Style`.
- [ ] Exclusive fallback if Hyprland reserves corners oddly: replace rails `Auto` with dedicated 1px invisible strips per edge + visual rails `Ignore` (Plan B, only if empirical `reserved` does not match).
