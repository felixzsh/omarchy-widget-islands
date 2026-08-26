import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../BarModel.js" as BarModel
import "../RailModel.js" as RailModel

// RailPanel — transparent edge indicator surface. Islands are floating HUDs.
PanelWindow {
    id: railWindow

    required property var screen
    required property string edge
    // Provided by RailsBar
    property string mainPosition: "top"
    property int thickness: 8
    property int barSize: 26
    property bool barHidden: false
    // Whether this rail has widgets; markers remain visible for empty rails too.
    property bool hasWidgets: true
    // Colors from innerBar
    property color backgroundColor: Color.bar.background
    property bool transparent: false
    // Hints data — per-edge layout for 3 thirds
    property var railLayout: ({ left: [], center: [], right: [] })
    property color foregroundColor: Color.bar.text
    // Shared host for widget drag coordination (RailsBar root)
    property var moveHost: null
    // Section under the pointer (left/center/right), fed by railHover
    property string hoveredSection: ""
    // Host-injected API for island widgets.
    property var barApi: null
    property var widgetRegistry: null
    property string fontFamily: ""
    // The section whose island is currently revealed ("" = none).
    property string activeSection: ""

    function sectionHasEntries(section) {
        return RailModel.sectionHasWidgets(railLayout, section)
    }

    // Register so the source panel can resolve peer claims
    // at release and so RailsBar can coordinate drags across edges.
    Component.onCompleted: if (moveHost && moveHost.registerRailPanel) moveHost.registerRailPanel(railWindow)
    Component.onDestruction: if (moveHost && moveHost.unregisterRailPanel) moveHost.unregisterRailPanel(railWindow)

    // Derived
    readonly property bool isHorizontal: edge === "top" || edge === "bottom"
    // No enabled flag is needed: the panel is visible while the plugin runs and
    // the main bar isn't hiding the frame (the bar toggle hides rails too).
    readonly property bool shouldShow: edge !== mainPosition && !barHidden
    onShouldShowChanged: if (!shouldShow) activeSection = ""

    // Intra-rail widget drag and drop state (mirrors Bar.qml's barDrag*).
    property var railDragSourceSlot: null
    property var railDragTargetSlot: null
    property bool railDragAfter: false
    property var railDragTargetGeometry: null
    property url railDragImageUrl: ""
    property real railDragScreenX: 0
    property real railDragScreenY: 0
    property real railDragOffsetX: 0
    property real railDragOffsetY: 0
    readonly property bool railDragActive: railDragSourceSlot !== null
    readonly property bool canMutateRail: barApi !== null && barApi.shell !== null
        && typeof barApi.shell.mutateShellConfig === "function"

    // BAR -> RAIL: while the native bar drags one
    // of ITS widgets, this rail reveals all islands and tracks the cursor to
    // offer drop targets. The bar's own intra-bar behavior is untouched; we
    // only observe public state (barDragSource/barDragScreenX/Y).
    readonly property bool barDragging: barApi !== null && barApi.barDragSource !== null
    // Another rail's widget is being dragged: reveal OUR
    // islands too and offer drop targets when the cursor enters our zone.
    readonly property bool foreignRailDrag: moveHost !== null
        && moveHost.universalDragEdge !== "" && moveHost.universalDragEdge !== edge
    readonly property bool dragModeActive: railDragActive || barDragging || foreignRailDrag

    // Source identity captured CONTINUOUSLY while the bar drags — the bar
    // clears barDragSource before deciding its own drop, so reading it at
    // release time would already be too late.
    property var barCrossSource: null
    property var barDropTargetSlot: null
    property bool barDropAfter: false
    property var barDropGeometry: null

    // OUR rail drag hovering the NATIVE BAR strip (source
    // panel only). Line is drawn by our ghost overlay, deterministic above
    // the bar's Top layer.
    property var railToBarTargetSlot: null
    property bool railToBarAfter: false
    property var railToBarGeometry: null
    // Destination identity resolved geometrically (immune to moduleSlots
    // registration order): which occurrence of this module the cursor meant.
    property string railToBarTargetName: ""
    property int railToBarTargetOrdinal: 0

    function barSurfaceWindow() {
        var b = barApi
        var slots = typeof b.moduleSlots !== "undefined" ? b.moduleSlots : []
        for (var i = 0; i < slots.length; i++) {
            var sl = slots[i]
            if (sl && sl.QsWindow && sl.QsWindow.window) return sl.QsWindow.window
        }
        return null
    }

    function barOrigin() {
        var b = barApi
        var w = barSurfaceWindow()
        var ox = 0
        var oy = 0
        if (w && w.screen) {
            if (b.position === "bottom") oy = Math.max(0, w.screen.height - w.height)
            else if (b.position === "right") ox = Math.max(0, w.screen.width - w.width)
        }
        return { x: ox, y: oy }
    }

    function pointInBarStrip(px, py) {
        var b = barApi
        if (!b || !screen) return false
        var t = Math.max(b.barSize, 8)
        var sw = screen.width
        var sh = screen.height
        if (b.position === "top") return py <= t
        if (b.position === "bottom") return py >= sh - t
        if (b.position === "left") return px <= t
        return px >= sw - t
    }

    function updateRailToBarTarget(px, py) {
        railToBarTargetSlot = null
        railToBarAfter = false
        railToBarGeometry = null
        railToBarTargetName = ""
        railToBarTargetOrdinal = 0
        var b = barApi
        if (!b || !pointInBarStrip(px, py)) return

        var o = barOrigin()
        var slots = typeof b.moduleSlots !== "undefined" ? b.moduleSlots : []
        var cands = []
        for (var i = 0; i < slots.length; i++) {
            var s = slots[i]
            if (!s || !s.visible || s.width <= 0 || s.height <= 0) continue
            var sp = { x: 0, y: 0 }
            try { sp = s.mapToItem(null, 0, 0) } catch (e) { continue }
            cands.push({ slot: s, x: o.x + sp.x, y: o.y + sp.y, width: s.width, height: s.height })
        }

        var drop = BarModel.nearestDropTarget(cands, { x: px, y: py }, b.vertical === true)
        if (!drop) return
        railToBarTargetSlot = drop.slot
        railToBarAfter = drop.after

        var c = null
        for (var j = 0; j < cands.length; j++) if (cands[j].slot === drop.slot) { c = cands[j]; break }
        if (!c) return

        // Which occurrence of this module is under the cursor? Count same-id
        // same-region candidates strictly BEFORE it along the drag axis.
        railToBarTargetName = String(drop.slot.moduleName || "")
        var ord = 0
        for (var m = 0; m < cands.length; m++) {
            var oc = cands[m]
            if (!oc.slot || oc.slot === drop.slot) continue
            if (oc.slot.region !== drop.slot.region || oc.slot.moduleName !== drop.slot.moduleName) continue
            var before = b.vertical === true ? oc.y < c.y : oc.x < c.x
            if (before) ord++
        }
        railToBarTargetOrdinal = ord

        var th = Style.spacing.xs
        railToBarGeometry = b.vertical === true
            ? { x: Math.round(c.x), y: Math.round(c.y + (drop.after ? c.height : 0) - th / 2),
                width: Math.round(c.width), height: th }
            : { x: Math.round(c.x + (drop.after ? c.width : 0) - th / 2), y: Math.round(c.y),
                width: th, height: Math.round(c.height) }
    }

    function clearBarDrop() {
        barCrossSource = null
        barDropTargetSlot = null
        barDropAfter = false
        barDropGeometry = null
    }

    // The core's own barDragScreenX/Y silently lose the edge offset whenever
    // its internal window lookup fails (observed: bottom/right bars report raw
    // window-local coords — masked when the bar sits at top, where local ==
    // screen). Derive the screen point ourselves from the always-correct
    // LOCAL coords plus the real surface via QsWindow.
    function barDragScreenPoint() {
        var b = barApi
        var lx = b.barDragSceneX
        var ly = b.barDragSceneY
        var w = b.barDragWindow || (b.barDragSource ? b.barDragSource.QsWindow.window : null)
        var ox = 0
        var oy = 0
        if (w && w.screen) {
            if (b.position === "bottom") oy = Math.max(0, w.screen.height - w.height)
            else if (b.position === "right") ox = Math.max(0, w.screen.width - w.width)
        }
        return { x: ox + lx, y: oy + ly }
    }

    function updateBarDropTarget() {
        if (!barDragging || !barApi.barDragSource) { clearBarDrop(); return }
        var sp = barDragScreenPoint()
        var src = barApi.barDragSource
        barCrossSource = { region: String(src.region || ""), moduleName: String(src.moduleName || "") }

        updateIncomingOffers(sp.x, sp.y)
    }

    // A RAIL-initiated drag from another edge hovering near us.
    function updateForeignTarget() {
        if (!foreignRailDrag || !moveHost) return
        updateIncomingOffers(moveHost.universalDragX, moveHost.universalDragY)
    }

    // Shared core for both incoming-drag flavors (bar-initiated and foreign
    // rail): every visible island's slots (+ empty-tab placeholders) compete
    // by proximity inside this rail's zone; the zone gate is the only
    // containment. Between two tabs the line pins to the nearest island.
    function updateIncomingOffers(px, py) {
        barDropTargetSlot = null
        barDropAfter = false
        barDropGeometry = null
        if (!pointerInRailZone(edge, px, py)) return

        var cands = []
        for (var i = 0; i < islands.length; i++) {
            var isl = islands[i]
            if (!isl || !isl.visible) continue
            var bio = isl.screenOrigin()
            for (var j = 0; j < isl.moduleSlots.length; j++) {
                var s = isl.moduleSlots[j]
                if (!s || !s.visible || s.width <= 0 || s.height <= 0) continue
                var sp = { x: 0, y: 0 }
                try { sp = s.mapToItem(null, 0, 0) } catch (e) { continue }
                cands.push({ slot: s, x: bio.x + sp.x, y: bio.y + sp.y, width: s.width, height: s.height })
            }
            if (isl.moduleSlots.length === 0) {
                var tp = isl.tabPoint()
                cands.push({ slot: isl.placeholderTarget, x: bio.x + tp.x, y: bio.y + tp.y,
                             width: isl.placeholderTarget.width, height: isl.placeholderTarget.height })
            }
        }

        var drop = BarModel.nearestDropTarget(cands, { x: px, y: py }, !isHorizontal)
        // Canonicalize interior seams like the intra-rail path does.
        if (drop && drop.after && !drop.slot.isPlaceholder) {
            var cIsl = drop.slot.host
            var cIdx = slotIndexIn(cIsl ? cIsl.moduleSlots : [], drop.slot)
            if (cIdx >= 0 && cIdx + 1 < cIsl.moduleSlots.length) {
                var nxt = cIsl.moduleSlots[cIdx + 1]
                if (nxt && nxt.visible) drop = { slot: nxt, after: false }
            }
        }
        if ((drop ? drop.slot : null) !== barDropTargetSlot)
            console.warn("[RAIL] bar-drop-target:", edge,
                drop ? ((drop.slot.isPlaceholder ? "PH@" : drop.slot.moduleName + "@") + drop.slot.section
                    + " after=" + drop.after) : "null")
        barDropTargetSlot = drop ? drop.slot : null
        barDropAfter = drop ? drop.after : false
        barDropGeometry = drop ? railDropMarkerRect(drop.slot, drop.after) : null
    }

    // The insertion line is painted INSIDE the owning island's window.
    // Islands and the ghost window share WlrLayer.Overlay and same-layer
    // stacking is map-order dependent (bar drags map everything at once →
    // line ended up under the tabs). Drawing locally is deterministic.
    // Returns window-local rect when THIS island owns the drop target.
    function localDropGeometry(isl) {
        var g = railDragTargetGeometry || barDropGeometry
        var tgt = railDragTargetSlot || barDropTargetSlot
        if (!g || !tgt || tgt.host !== isl) return null
        var io = isl.screenOrigin()
        return { x: g.x - io.x, y: g.y - io.y, width: g.width, height: g.height }
    }

    function finishBarDropToRail() {
        var tgt = barDropTargetSlot
        var after = barDropAfter
        var srcInfo = barCrossSource
        clearBarDrop()
        if (!tgt || !srcInfo || !srcInfo.region || !srcInfo.moduleName) return
        if (!canMutateRail) return

        // Destination index within the target island's slot order mirrors the
        // section layout (same protocol as finishRailDrag). Placeholder = append.
        var isl = tgt.host
        var tgtIdx = tgt.isPlaceholder ? -1 : slotIndexIn(isl ? isl.moduleSlots : [], tgt)

        console.warn("[RAIL] bar-drop:", edge,
            srcInfo.moduleName + "@" + srcInfo.region,
            "->", (tgt.isPlaceholder ? "append@" + tgt.section
                : tgt.moduleName + "@" + tgt.section + "[" + tgtIdx + "]"),
            "after=" + after)

        barApi.shell.mutateShellConfig(function(config) {
            var changed = RailModel.moveBarEntryToRail(
                config, srcInfo.moduleName, srcInfo.region, edge, tgt.section, tgtIdx, after)
            console.warn("[RAIL] bar-drop result:", changed ? "MOVED" : "NOT MOVED")
        })
    }

    // React to the cross-panel drag coordinator (RailsBar).
    Connections {
        target: railWindow.moveHost
        function onUniversalDragXChanged() { if (railWindow.foreignRailDrag) railWindow.updateForeignTarget() }
        function onUniversalDragYChanged() { if (railWindow.foreignRailDrag) railWindow.updateForeignTarget() }
        function onUniversalDragEdgeChanged() {
            if (railWindow.foreignRailDrag) {
                // First cursor sample may already sit inside our zone.
                railWindow.updateForeignTarget()
            } else if (!railWindow.railDragActive && !railWindow.barDragging) {
                railWindow.clearBarDrop()
            }
        }
    }

    Connections {
        target: barApi
        function onBarDragSourceChanged() {
            if (barApi && barApi.barDragSource) railWindow.updateBarDropTarget()
            else railWindow.finishBarDropToRail()
        }
        function onBarDragScreenXChanged() { if (railWindow.barDragging) railWindow.updateBarDropTarget() }
        function onBarDragScreenYChanged() { if (railWindow.barDragging) railWindow.updateBarDropTarget() }
    }

    // Acceptance zone: drops and empty-tab reveals only count while the
    // dragged pointer sits at THIS rail's edge.
    // (+grace). Mirrors the native bar, which ignores releases outside its
    // window — without this, every release lands somewhere.
    readonly property int zoneGrace: Style.space(6)
    function pointerInRailZone(pEdge, px, py) {
        var sw = screen ? screen.width : 0
        var sh = screen ? screen.height : 0
        var depth = Math.max(thickness + 2, Math.round(barSize * 0.85)) + zoneGrace
        if (pEdge === "top") return py <= depth && px >= -zoneGrace && px <= sw + zoneGrace
        if (pEdge === "bottom") return py >= sh - depth && px >= -zoneGrace && px <= sw + zoneGrace
        if (pEdge === "left") return px <= depth && py >= -zoneGrace && py <= sh + zoneGrace
        return px >= sw - depth && py >= -zoneGrace && py <= sh + zoneGrace
    }

    function clearRailDrag() {
        railDragSourceSlot = null
        railDragTargetSlot = null
        railDragAfter = false
        railDragTargetGeometry = null
        railDragImageUrl = ""
        railDragScreenX = 0
        railDragScreenY = 0
        railDragOffsetX = 0
        railDragOffsetY = 0
        railToBarTargetSlot = null
        railToBarAfter = false
        railToBarGeometry = null
        railToBarTargetName = ""
        railToBarTargetOrdinal = 0
        if (moveHost && moveHost.universalDragEdge === edge) {
            moveHost.universalDragEdge = ""
            moveHost.universalDragX = 0
            moveHost.universalDragY = 0
        }
    }

    function beginRailDrag(slot, pressedX, pressedY) {
        if (!slot || railDragActive) return
        railDragOffsetX = pressedX
        railDragOffsetY = pressedY
        railDragImageUrl = ""
        var item = slot.activeItem
        if (item && typeof item.grabToImage === "function") {
            var gw = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
            var gh = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
            item.grabToImage(function(result) {
                if (railDragSourceSlot !== slot || !result || !result.url) return
                railDragImageUrl = result.url
            }, Qt.size(gw, gh))
        }
        console.warn("[RAIL]", edge, "widget-drag begin:", slot.moduleName)
        railDragSourceSlot = slot
        if (moveHost) moveHost.universalDragEdge = edge
    }

    function updateRailDrag(slot, scenePoint) {
        if (!railDragActive || slot !== railDragSourceSlot) return

        var srcIsl = railDragSourceSlot.host
        var so = srcIsl ? srcIsl.screenOrigin() : { x: 0, y: 0 }
        railDragScreenX = so.x + scenePoint.x
        railDragScreenY = so.y + scenePoint.y
        // Live cursor for peer panels computing their own island offers.
        if (moveHost && moveHost.universalDragEdge === edge) {
            moveHost.universalDragX = railDragScreenX
            moveHost.universalDragY = railDragScreenY
        }

        // Drop candidates: every visible slot across this rail's islands,
        // expressed in SCREEN coords (islands are separate windows but all
        // flush with their edge, so origin + local == screen).
        var candidates = []
        for (var i = 0; i < islands.length; i++) {
            var isl = islands[i]
            if (!isl || !isl.visible) continue
            var io = isl.screenOrigin()
            var islandCandidates = 0
            for (var j = 0; j < isl.moduleSlots.length; j++) {
                var s = isl.moduleSlots[j]
                if (!s || s === slot || !s.visible || s.width <= 0 || s.height <= 0) continue
                var sp = { x: 0, y: 0 }
                try { sp = s.mapToItem(null, 0, 0) } catch (e) { continue }
                candidates.push({ slot: s, x: io.x + sp.x, y: io.y + sp.y, width: s.width, height: s.height })
                islandCandidates++
            }
            // No droppable slot left (empty section, or source was the only
            // widget): whole tab is the append zone; dropping back home is a
            // no-op.
            if (islandCandidates === 0) {
                var tp = isl.tabPoint()
                candidates.push({
                    slot: isl.placeholderTarget,
                    x: io.x + tp.x, y: io.y + tp.y,
                    width: isl.placeholderTarget.width, height: isl.placeholderTarget.height
                })
            }
        }

        var drop = BarModel.nearestDropTarget(
            candidates, { x: railDragScreenX, y: railDragScreenY }, !isHorizontal)
        // Outside this rail's zone nothing is a target: releasing there
        // cancels the move, same as releasing off the native bar.
        if (drop && !pointerInRailZone(edge, railDragScreenX, railDragScreenY)) drop = null

        // Canonicalize interior seams: "after slot N" commits identically to
        // "before slot N+1", but as two rival representations they tie at the
        // seam and the line flip-flops between them. Pin it to the "before"
        // side whenever a visible next sibling exists — real appends (last
        // slot), placeholders and cross-section seams stay as-is.
        if (drop && drop.after && !drop.slot.isPlaceholder) {
            var cIsl = drop.slot.host
            var cIdx = slotIndexIn(cIsl ? cIsl.moduleSlots : [], drop.slot)
            if (cIdx >= 0 && cIdx + 1 < cIsl.moduleSlots.length) {
                var nxt = cIsl.moduleSlots[cIdx + 1]
                if (nxt && nxt.visible) drop = { slot: nxt, after: false }
            }
        }

        // DEBUG: log only on target transitions (low frequency) + candidate
        // geometry snapshot, so a journal excerpt shows exactly why the line
        // hopped where it hopped.
        if ((drop ? drop.slot : null) !== railDragTargetSlot
            || (drop ? drop.after : false) !== railDragAfter) {
            var dbgParts = []
            for (var d = 0; d < candidates.length; d++) {
                var cd = candidates[d]
                var nm = cd.slot.isPlaceholder ? ("PH@" + cd.slot.section)
                    : (cd.slot.moduleName + "@" + cd.slot.section)
                dbgParts.push(nm + ":" + Math.round(cd.x) + "," + Math.round(cd.y)
                    + " " + Math.round(cd.width) + "x" + Math.round(cd.height))
            }
            console.warn("[RAIL] drag-target:",
                drop ? ((drop.slot.isPlaceholder ? "PH@" + drop.slot.section : drop.slot.moduleName + "@" + drop.slot.section)
                    + " after=" + drop.after) : "null",
                "· cursor=" + Math.round(railDragScreenX) + "," + Math.round(railDragScreenY),
                "· axis=" + (!isHorizontal ? "y" : "x"))
            console.warn("[RAIL] candidates:", dbgParts.join(" | "))
        }

        railDragTargetSlot = drop ? drop.slot : null
        railDragAfter = drop ? drop.after : false
        railDragTargetGeometry = drop ? railDropMarkerRect(drop.slot, drop.after) : null

        // Outside our zone the native bar strip may offer a
        // landing spot (rail -> bar). Cleared automatically on each update.
        updateRailToBarTarget(railDragScreenX, railDragScreenY)
    }

    function railDropMarkerRect(targetSlot, after) {
        if (!targetSlot || !targetSlot.host) return null
        var isl = targetSlot.host
        var io = isl.screenOrigin()
        var p
        if (targetSlot.isPlaceholder) p = isl.tabPoint()
        else {
            try { p = targetSlot.mapToItem(null, 0, 0) } catch (e) { return null }
        }
        var sx = io.x + p.x
        var sy = io.y + p.y
        var th = Style.spacing.xs
        if (!isl.horizontal) {
            return { x: sx, y: sy + (after ? targetSlot.height : 0) - th / 2,
                     width: targetSlot.width, height: th }
        }
        return { x: sx + (after ? targetSlot.width : 0) - th / 2, y: sy,
                 width: th, height: targetSlot.height }
    }

    function finishRailDrag() {
        var src = railDragSourceSlot
        var homeTgt = railDragTargetSlot
        var homeAfter = railDragAfter

        // Cross-surface claims, mutually exclusive by geometry:
        // a peer panel's island offer (rail -> other rail) or our own native-
        // bar strip target (rail -> bar).
        var peer = null
        if (moveHost) {
            for (var pi = 0; pi < moveHost.railPanels.length; pi++) {
                var pp = moveHost.railPanels[pi]
                if (pp !== railWindow && pp.barDropTargetSlot) { peer = pp; break }
            }
        }
        var peerTgt = peer ? peer.barDropTargetSlot : null
        var peerAfter = peer ? peer.barDropAfter : false
        var barTgt = railToBarTargetSlot
        var barAfter = railToBarAfter
        var barName = railToBarTargetName
        var barOrd = railToBarTargetOrdinal

        clearRailDrag()   // also resets hub cursor/edge + railToBar*
        if (peer && peer.clearBarDrop) peer.clearBarDrop()

        if (!src || !canMutateRail) {
            console.warn("[RAIL] drop: CANCEL",
                "src=", src ? (src.moduleName + "@" + src.section) : "null",
                "peer=", peer ? peer.edge : "-", "bar=", !!barTgt, "home=", !!homeTgt)
            return
        }

        // Index-addressed moves: slot order in moduleSlots mirrors the section
        // layout, so resolve positions by identity — duplicate ids can't
        // hijack name lookups.
        var srcIdx = slotIndexIn(src.host ? src.host.moduleSlots : [], src)
        if (srcIdx < 0) return

        if (peerTgt) {
            var pIsl = peerTgt.host
            var pIdx = peerTgt.isPlaceholder ? -1 : slotIndexIn(pIsl ? pIsl.moduleSlots : [], peerTgt)
            console.warn("[RAIL] cross-rail drop:", edge,
                src.moduleName + "@" + src.section + "[" + srcIdx + "]",
                "->", peer.edge, (peerTgt.isPlaceholder ? "append@" + peerTgt.section
                    : peerTgt.moduleName + "@" + peerTgt.section + "[" + pIdx + "]"),
                "after=" + peerAfter)
            barApi.shell.mutateShellConfig(function(config) {
                var changed = RailModel.moveRailEntryBetweenEdges(
                    config, edge, src.section, srcIdx, peer.edge, peerTgt.section, pIdx, peerAfter)
                console.warn("[RAIL] cross-rail result:", changed ? "MOVED" : "IDENTITY (no write)")
            })
            return
        }

        if (barTgt) {
            var region = String(barTgt.region || "")
            var tName = barName
            var tOrd = barOrd
            console.warn("[RAIL] rail->bar drop:", edge,
                src.moduleName + "@" + src.section + "[" + srcIdx + "]",
                "-> bar." + region, tName + "#" + tOrd, "after=" + barAfter)
            barApi.shell.mutateShellConfig(function(config) {
                // Resolve against the REAL layout array inside the mutation:
                // moduleSlots order diverges from layout after live changes,
                // so position by name + occurrence ordinal (upstream parity).
                var entries = RailModel.barLayoutSection(config, region)
                var idx = RailModel.barEntryIndexOfOccurrence(entries, tName, tOrd)
                console.warn("[RAIL][DBG] resolve:", region,
                    "entries=", entries.map(function(e) { return RailModel.entryId(e) }).join("|"),
                    "name=", tName, "ord=", tOrd, "-> idx=", idx)
                var destIdx = idx < 0 ? entries.length : idx + (barAfter ? 1 : 0)
                var changed = RailModel.moveRailEntryToBarAt(
                    config, edge, src.section, srcIdx, region, destIdx)
                console.warn("[RAIL] rail->bar result:", changed ? "MOVED" : "NOT MOVED")
            })
            return
        }

        if (!homeTgt) {
            console.warn("[RAIL] drop: CANCEL (no targets)")
            return
        }

        var tgt = homeTgt
        var after = homeAfter
        var tgtIdx = tgt.isPlaceholder ? -1 : slotIndexIn(tgt.host ? tgt.host.moduleSlots : [], tgt)

        console.warn("[RAIL] drop:", edge,
            src.moduleName + "@" + src.section + "[" + srcIdx + "]",
            "->", (tgt.isPlaceholder ? "append@" + tgt.section
                : tgt.moduleName + "@" + tgt.section + "[" + tgtIdx + "]"),
            "after=" + after)

        barApi.shell.mutateShellConfig(function(config) {
            var changed = RailModel.moveRailEntryAt(
                config, edge, src.section, srcIdx, tgt.section, tgtIdx, after)
            console.warn("[RAIL] drop result:", changed ? "MOVED" : "IDENTITY (no write)")
        })
    }

    function slotIndexIn(slots, target) {
        for (var i = 0; i < slots.length; i++) {
            if (slots[i] === target) return i
        }
        return -1
    }

    visible: shouldShow && !remapGuard.remapping
    // Keep Ignore: Auto breaks the frame fit and never helped the drag tracking.
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-rails-" + edge
    WlrLayershell.layer: WlrLayer.Top

    color: "transparent"
    surfaceFormat.opaque: false

    // Full-edge hover surface with no visible rail and no reservation.
    implicitWidth: isHorizontal ? 0 : thickness
    implicitHeight: isHorizontal ? thickness : 0

    anchors {
        top: edge === "top" || edge === "left" || edge === "right"
        bottom: edge === "bottom" || edge === "left" || edge === "right"
        left: edge === "left" || edge === "top" || edge === "bottom"
        right: edge === "right" || edge === "top" || edge === "bottom"
    }

    margins {
        top: 0
        bottom: 0
        left: 0
        right: 0
    }

    ScreenMoveRemap {
        id: remapGuard
        window: railWindow
    }

    // 3.3 — hints: one dot per widget centered in each third, hitbox = whole third
    RailHints {
        anchors.fill: parent
        edge: railWindow.edge
        railLayout: railWindow.railLayout
        hoveredSection: railWindow.hoveredSection
        dotColor: railWindow.foregroundColor
    }

        HoverHandler {
        id: railHover
        onHoveredChanged: {
            if (!hovered) {
                railWindow.hoveredSection = ""
                hoverCloseTimer.restart()
            } else {
                hoverCloseTimer.stop()
            }
        }
        onPointChanged: {
            if (!railHover.hovered) return
            var p = railHover.point.position
            var sec = ""
            if (railWindow.isHorizontal) {
                var thirdW = railWindow.width / 3
                if (p.x < thirdW) sec = "left"
                else if (p.x < thirdW * 2) sec = "center"
                else sec = "right"
            } else {
                var thirdH = railWindow.height / 3
                if (p.y < thirdH) sec = "left"
                else if (p.y < thirdH * 2) sec = "center"
                else sec = "right"
            }
            railWindow.hoveredSection = sec
            // Reveal the island for a dotful section on hover.
            // (frozen while a widget is being dragged)
            if (sec !== "" && !railWindow.dragModeActive
                && sec !== railWindow.activeSection
                && RailModel.sectionHasWidgets(railWindow.railLayout, sec)) {
                console.warn("[RAIL]", railWindow.edge, "hover-activate:", sec)
                railWindow.activeSection = sec
                hoverCloseTimer.stop()
            }
        }
    }

    Timer {
        id: hoverCloseTimer
        interval: 180
        onTriggered: {
            if (railWindow.dragModeActive) return
            if (railHover.hovered) return
            for (var i = 0; i < islands.length; i++) {
                var isl = islands[i]
                if (isl && (isl.pointerInside || isl.pinnedByPanel)) return
            }
            railWindow.activeSection = ""
        }
    }

    // Islands registry — Variants can't enumerate its own instances, so
    // islands self-register here (same pattern as moduleSlots).
    property var islands: []
    function registerIsland(isl) {
        if (!isl) return
        var next = islands.slice()
        if (next.indexOf(isl) !== -1) return
        next.push(isl)
        islands = next
    }
    function unregisterIsland(isl) {
        var next = islands.filter(function(t) { return t !== isl })
        if (next.length === islands.length) return
        islands = next
    }

    // One island per section. Normal mode reveals only activeSection; during a
    // rail widget drag ALL populated sections reveal at once — the affordance
    // that says "you can drop it there".
    //
    // Variants, not Repeater: these are PANEL WINDOWS, and Quickshell only
    // creates real layer surfaces through Variants (same as Bar.qml per-screen
    // windows). A Repeater of PanelWindows silently never maps.
    Variants {
        model: ["left", "center", "right"]

        delegate: Component {
            RailIsland {
                required property string modelData

                screen: railWindow.screen
                edge: railWindow.edge
                section: modelData
                centerFrac: (["left", "center", "right"].indexOf(modelData) + 0.5) / 3
                entries: railWindow.railLayout ? (railWindow.railLayout[modelData] || []) : []
                registry: railWindow.widgetRegistry
                barApi: railWindow.barApi
                thickness: railWindow.thickness
                barSize: railWindow.barSize
                backgroundColor: railWindow.backgroundColor
                foregroundColor: railWindow.foregroundColor
                transparent: railWindow.transparent
                fontFamily: railWindow.fontFamily
                dragHost: railWindow
                // Parked windows: mapped whenever the rail exists; reveal
                // logic lives inside the island (revealed property).
                visible: railWindow.shouldShow && !remapGuard.remapping
                onCloseRequested: if (!railWindow.railDragActive) railWindow.activeSection = ""
                onPointerInsideChanged: {
                    if (pointerInside) hoverCloseTimer.stop()
                    else if (!railHover.hovered && !pinnedByPanel)
                        hoverCloseTimer.restart()
                }
                onPinnedByPanelChanged: {
                    // Panel closed → resume normal dismissal only if pointer is gone
                    if (pinnedByPanel) hoverCloseTimer.stop()
                    else if (!railHover.hovered && !pointerInside)
                        hoverCloseTimer.restart()
                }
            }
        }
    }

    // Drag feedback overlay (mirrors Bar.qml's DragGhostPanel): the
    // grabbed widget follows the cursor and an accent line marks where it
    // would land. Visual-only: empty input region keeps the pointer grab with
    // the MouseArea that started the drag.
    component RailDragGhostPanel: PanelWindow {
        id: ghostWindow

        readonly property bool active: railWindow.railDragActive
        readonly property var sourceItem: railWindow.railDragSourceSlot
            ? railWindow.railDragSourceSlot.activeItem : null
        readonly property int ghostPadding: Style.space(1)
        readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
        readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

        // Rail-initiated drags ONLY: the bar paints its own ghost natively,
        // and insertion lines now live inside the island windows. Keeping this
        // unmapped during bar drags removes 4 pointless fullscreen mappings
        // from every bar-drag start.
        visible: active && sourceItem !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-rails-drag-ghost-" + railWindow.edge
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        surfaceFormat.opaque: false

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {}

        Item {
            visible: railWindow.railDragImageUrl !== ""
            x: Math.round(railWindow.railDragScreenX - railWindow.railDragOffsetX - ghostWindow.ghostPadding)
            y: Math.round(railWindow.railDragScreenY - railWindow.railDragOffsetY - ghostWindow.ghostPadding)
            width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
            height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

            BorderSurface {
                anchors.fill: parent
                color: railWindow.transparent ? "transparent" : railWindow.backgroundColor
                borderSpec: Border.flat(railWindow.foregroundColor, 1)
                radius: Math.min(Style.cornerRadius, height / 2)
                opacity: railWindow.transparent ? 0.45 : 0.94
            }

            Image {
                anchors.fill: parent
                anchors.margins: ghostWindow.ghostPadding
                source: railWindow.railDragImageUrl
                fillMode: Image.Stretch
                smooth: true
                opacity: 0.84
            }
        }

        // NOTE: island targets paint their own segment inside the island
        // window (localDropGeometry). This window only draws the NATIVE BAR
        // target line for rail->bar drags — Overlay deterministically sits
        // above the bar's Top layer, and the strip never overlaps islands.
        Rectangle {
            readonly property var targetRect: railWindow.railToBarGeometry

            visible: ghostWindow.active && targetRect !== null
            x: targetRect ? Math.round(targetRect.x) : 0
            y: targetRect ? Math.round(targetRect.y) : 0
            width: targetRect ? targetRect.width : 0
            height: targetRect ? targetRect.height : 0
            color: Color.accent
            radius: Math.min(width, height) / 2
        }
    }

    RailDragGhostPanel {
        screen: railWindow.screen
    }

}
