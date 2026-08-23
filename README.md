# omarchy-rails

A frame of **rails** around your Omarchy workspace. Your main bar stays exactly as it is — the rails are three thin strips on the remaining screen edges where any widget can live.

**The whole idea in one flow:** you install widgets/plugins → they land in the main bar (as always) → you drag them into a rail. That's it. You never touch `shell.json`.

## The flow

1. **Install the plugin** — rails appear immediately as thin empty strips on the three edges not used by your main bar.
2. **Install widgets/plugins normally** — everything lands in the main bar, exactly like without rails.
3. **Drag anything from the bar into a rail** — while dragging, every rail reveals its drop zones; release and the widget lives there.

```bash
omarchy plugin add https://github.com/felixzsh/omarchy-rails --enable
```

From then on, reorder inside a rail, move widgets between rails, drag them back to the main bar — all with live insertion indicators, like the native bar's own editing experience.

## Features

- **Zero-config.** No `shell.json` section required. Rails exist while the plugin runs; sections are created automatically by your first drops.
- **Islands on demand.** Each rail has 3 sections. Hover (or click, configurable) a section's zone and an island slides out of the strip showing its real, fully interactive widgets — not previews, the same components the main bar hosts.
- **Full main-bar parity for hosted widgets.** Panels open adjacent to the island (summon adjacency), clicking another island widget swaps panels in one click, an accent mark shows which widget has its panel open. If it works in the bar, it works in the rail.
- **Universal drag & drop.** Move widgets main bar ⇄ rails and between rails. A ghost follows the cursor, the source dims, and an accent line marks exactly where the widget will land — including between two islands. Empty sections show placeholder tabs during drags so they're droppable too.
- **Third-party plugin friendly.** Non-native plugins keep working while hosted in rails: their widget components stay registered and their services stay alive, so dynamic-data plugins (live counters, trackers) keep ticking inside islands.
- **Duplicate-safe reordering.** Two copies of the same widget? Drops resolve against the exact instance under your cursor.
- **Container moves included.** Drag the rail strip itself to swap that rail's contents with another edge, or to move your main bar — rails re-arrange around it automatically.
- **One toggle hides everything.** The standard bar toggle hides the main bar and the rails together.

## Configuration (optional)

There is nothing to configure for the base experience. The only knob today is the island reveal trigger:

```json
{
  "bar": {
    "rails": {
      "trigger": "hover"
    }
  }
}
```

`"trigger"` is `"hover"` (default) or `"click"`. Everything else — sections, per-edge layout — builds itself as you drag. Legacy keys like `"enabled"` are ignored: uninstalling/disabling the plugin removes the rails.
