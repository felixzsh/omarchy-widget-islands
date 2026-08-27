import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../BarModel.js" as BarModel
import "../IslandModel.js" as IslandModel

// IslandPanel — transparent edge indicator surface. Islands are floating HUDs.
PanelWindow {
    id: islandWindow

    required property var screen
    required property string edge
    // Provided by WidgetIslandsBar
    property string mainPosition: "top"
    property int thickness: 8
    property int barSize: 26
    property bool barHidden: false
    // Whether this island has widgets; markers remain visible for empty islands too.
    property bool hasWidgets: true
    // Colors from innerBar
    property color backgroundColor: Color.bar.background
    property bool transparent: false
    // Hints data — per-edge layout for 3 thirds
    property var islandLayout: ({ left: [], center: [], right: [] })
    property color foregroundColor: Color.bar.text
    // Shared host for widget drag coordination (WidgetIslandsBar root)
    property var moveHost: null
    // Section under the pointer (left/center/right), fed by islandHover
    property string hoveredSection: ""
    // Host-injected API for island widgets.
    property var barApi: null
    property var widgetRegistry: null
    property string fontFamily: ""
    // The section whose island is currently revealed ("" = none).
    property string activeSection: ""

    function sectionHasEntries(section) {
        return IslandModel.sectionHasWidgets(islandLayout, section)
    }

    // Register so the source panel can resolve peer claims
    // at release and so WidgetIslandsBar can coordinate drags across edges.
    Component.onCompleted: if (moveHost && moveHost.registerIslandPanel) moveHost.registerIslandPanel(islandWindow)
    Component.onDestruction: if (moveHost && moveHost.unregisterIslandPanel) moveHost.unregisterIslandPanel(islandWindow)

    // Derived
    readonly property bool isHorizontal: edge === "top" || edge === "bottom"
    // No enabled flag is needed: the panel is visible while the plugin runs and
    // the main bar isn't hiding the frame (the bar toggle hides islands too).
    readonly property bool shouldShow: edge !== mainPosition && !barHidden
    onShouldShowChanged: if (!shouldShow) activeSection = ""

    // Intra-island widget drag and drop state (mirrors Bar.qml's barDrag*).
    property var islandDragSourceSlot: null
    property var islandDragTargetSlot: null
    property bool islandDragAfter: false
    property var islandDragTargetGeometry: null
    property url islandDragImageUrl: ""
    property real islandDragScreenX: 0
    property real islandDragScreenY: 0
    property real islandDragOffsetX: 0
    property real islandDragOffsetY: 0
    readonly property bool islandDragActive: islandDragSourceSlot !== null
    readonly property bool canMutateIsland: barApi !== null && barApi.shell !== null
        && typeof barApi.shell.mutateShellConfig === "function"

    // BAR -> RAIL: while the native bar drags one
    // of ITS widgets, this island reveals all islands and tracks the cursor to
    // offer drop targets. The bar's own intra-bar behavior is untouched; we
    // only observe public state (barDragSource/barDragScreenX/Y).
    readonly property bool barDragging: barApi !== null && barApi.barDragSource !== null
    // Another island's widget is being dragged: reveal OUR
    // islands too and offer drop targets when the cursor enters our zone.
    readonly property bool foreignIslandDrag: moveHost !== null
        && moveHost.universalDragEdge !== "" && moveHost.universalDragEdge !== edge
    readonly property bool dragModeActive: islandDragActive || barDragging || foreignIslandDrag

    // Source identity captured CONTINUOUSLY while the bar drags — the bar
    // clears barDragSource before deciding its own drop, so reading it at
    // release time would already be too late.
    property var barCrossSource: null
    property var barDropTargetSlot: null
    property bool barDropAfter: false
    property var barDropGeometry: null

    // OUR island drag hovering the NATIVE BAR strip (source
    // panel only). Line is drawn by our ghost overlay, deterministic above
    // the bar's Top layer.
    property var islandToBarTargetSlot: null
    property bool islandToBarAfter: false
    property var islandToBarGeometry: null
    // Destination identity resolved geometrically (immune to moduleSlots
    // registration order): which occurrence of this module the cursor meant.
    property string islandToBarTargetName: ""
    property int islandToBarTargetOrdinal: 0

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

    function updateIslandToBarTarget(px, py) {
        islandToBarTargetSlot = null
        islandToBarAfter = false
        islandToBarGeometry = null
        islandToBarTargetName = ""
        islandToBarTargetOrdinal = 0
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
        islandToBarTargetSlot = drop.slot
        islandToBarAfter = drop.after

        var c = null
        for (var j = 0; j < cands.length; j++) if (cands[j].slot === drop.slot) { c = cands[j]; break }
        if (!c) return

        // Which occurrence of this module is under the cursor? Count same-id
        // same-region candidates strictly BEFORE it along the drag axis.
        islandToBarTargetName = String(drop.slot.moduleName || "")
        var ord = 0
        for (var m = 0; m < cands.length; m++) {
            var oc = cands[m]
            if (!oc.slot || oc.slot === drop.slot) continue
            if (oc.slot.region !== drop.slot.region || oc.slot.moduleName !== drop.slot.moduleName) continue
            var before = b.vertical === true ? oc.y < c.y : oc.x < c.x
            if (before) ord++
        }
        islandToBarTargetOrdinal = ord

        var th = Style.spacing.xs
        islandToBarGeometry = b.vertical === true
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
        if (!foreignIslandDrag || !moveHost) return
        updateIncomingOffers(moveHost.universalDragX, moveHost.universalDragY)
    }

    // Shared core for both incoming-drag flavors (bar-initiated and foreign
    // island): every visible island's slots (+ empty-tab placeholders) compete
    // by proximity inside this island's zone; the zone gate is the only
    // containment. Between two tabs the line pins to the nearest island.
    function updateIncomingOffers(px, py) {
        barDropTargetSlot = null
        barDropAfter = false
        barDropGeometry = null
        if (!pointerInIslandZone(edge, px, py)) return

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
        // Canonicalize interior seams like the intra-island path does.
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
        barDropGeometry = drop ? islandDropMarkerRect(drop.slot, drop.after) : null
    }

    // The insertion line is painted INSIDE the owning island's window.
    // Islands and the ghost window share WlrLayer.Overlay and same-layer
    // stacking is map-order dependent (bar drags map everything at once →
    // line ended up under the tabs). Drawing locally is deterministic.
    // Returns window-local rect when THIS island owns the drop target.
    function localDropGeometry(isl) {
        var g = islandDragTargetGeometry || barDropGeometry
        var tgt = islandDragTargetSlot || barDropTargetSlot
        if (!g || !tgt || tgt.host !== isl) return null
        var io = isl.screenOrigin()
        return { x: g.x - io.x, y: g.y - io.y, width: g.width, height: g.height }
    }

    function finishBarDropToIsland() {
        var tgt = barDropTargetSlot
        var after = barDropAfter
        var srcInfo = barCrossSource
        clearBarDrop()
        if (!tgt || !srcInfo || !srcInfo.region || !srcInfo.moduleName) return
        if (!canMutateIsland) return

        // Destination index within the target island's slot order mirrors the
        // section layout (same protocol as finishIslandDrag). Placeholder = append.
        var isl = tgt.host
        var tgtIdx = tgt.isPlaceholder ? -1 : slotIndexIn(isl ? isl.moduleSlots : [], tgt)

        console.warn("[RAIL] bar-drop:", edge,
            srcInfo.moduleName + "@" + srcInfo.region,
            "->", (tgt.isPlaceholder ? "append@" + tgt.section
                : tgt.moduleName + "@" + tgt.section + "[" + tgtIdx + "]"),
            "after=" + after)

        barApi.shell.mutateShellConfig(function(config) {
            var changed = IslandModel.moveBarEntryToIsland(
                config, srcInfo.moduleName, srcInfo.region, edge, tgt.section, tgtIdx, after)
            console.warn("[RAIL] bar-drop result:", changed ? "MOVED" : "NOT MOVED")
        })
    }

    // React to the cross-panel drag coordinator (WidgetIslandsBar).
    Connections {
        target: islandWindow.moveHost
        function onUniversalDragXChanged() { if (islandWindow.foreignIslandDrag) islandWindow.updateForeignTarget() }
        function onUniversalDragYChanged() { if (islandWindow.foreignIslandDrag) islandWindow.updateForeignTarget() }
        function onUniversalDragEdgeChanged() {
            if (islandWindow.foreignIslandDrag) {
                // First cursor sample may already sit inside our zone.
                islandWindow.updateForeignTarget()
            } else if (!islandWindow.islandDragActive && !islandWindow.barDragging) {
                islandWindow.clearBarDrop()
            }
        }
    }

    Connections {
        target: barApi
        function onBarDragSourceChanged() {
            if (barApi && barApi.barDragSource) islandWindow.updateBarDropTarget()
            else islandWindow.finishBarDropToIsland()
        }
        function onBarDragScreenXChanged() { if (islandWindow.barDragging) islandWindow.updateBarDropTarget() }
        function onBarDragScreenYChanged() { if (islandWindow.barDragging) islandWindow.updateBarDropTarget() }
    }

    // Acceptance zone: drops and empty-tab reveals only count while the
    // dragged pointer sits at THIS island's edge.
    // (+grace). Mirrors the native bar, which ignores releases outside its
    // window — without this, every release lands somewhere.
    readonly property int zoneGrace: Style.space(6)
    function pointerInIslandZone(pEdge, px, py) {
        var sw = screen ? screen.width : 0
        var sh = screen ? screen.height : 0
        var depth = Math.max(thickness + 2, Math.round(barSize * 0.85)) + zoneGrace
        if (pEdge === "top") return py <= depth && px >= -zoneGrace && px <= sw + zoneGrace
        if (pEdge === "bottom") return py >= sh - depth && px >= -zoneGrace && px <= sw + zoneGrace
        if (pEdge === "left") return px <= depth && py >= -zoneGrace && py <= sh + zoneGrace
        return px >= sw - depth && py >= -zoneGrace && py <= sh + zoneGrace
    }

    function clearIslandDrag() {
        islandDragSourceSlot = null
        islandDragTargetSlot = null
        islandDragAfter = false
        islandDragTargetGeometry = null
        islandDragImageUrl = ""
        islandDragScreenX = 0
        islandDragScreenY = 0
        islandDragOffsetX = 0
        islandDragOffsetY = 0
        islandToBarTargetSlot = null
        islandToBarAfter = false
        islandToBarGeometry = null
        islandToBarTargetName = ""
        islandToBarTargetOrdinal = 0
        if (moveHost && moveHost.universalDragEdge === edge) {
            moveHost.universalDragEdge = ""
            moveHost.universalDragX = 0
            moveHost.universalDragY = 0
        }
    }

    function beginIslandDrag(slot, pressedX, pressedY) {
        if (!slot || islandDragActive) return
        islandDragOffsetX = pressedX
        islandDragOffsetY = pressedY
        islandDragImageUrl = ""
        var item = slot.activeItem
        if (item && typeof item.grabToImage === "function") {
            var gw = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
            var gh = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
            item.grabToImage(function(result) {
                if (islandDragSourceSlot !== slot || !result || !result.url) return
                islandDragImageUrl = result.url
            }, Qt.size(gw, gh))
        }
        console.warn("[RAIL]", edge, "widget-drag begin:", slot.moduleName)
        islandDragSourceSlot = slot
        if (moveHost) moveHost.universalDragEdge = edge
    }

    function updateIslandDrag(slot, scenePoint) {
        if (!islandDragActive || slot !== islandDragSourceSlot) return

        var srcIsl = islandDragSourceSlot.host
        var so = srcIsl ? srcIsl.screenOrigin() : { x: 0, y: 0 }
        islandDragScreenX = so.x + scenePoint.x
        islandDragScreenY = so.y + scenePoint.y
        // Live cursor for peer panels computing their own island offers.
        if (moveHost && moveHost.universalDragEdge === edge) {
            moveHost.universalDragX = islandDragScreenX
            moveHost.universalDragY = islandDragScreenY
        }

        // Drop candidates: every visible slot across this island's islands,
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
            candidates, { x: islandDragScreenX, y: islandDragScreenY }, !isHorizontal)
        // Outside this island's zone nothing is a target: releasing there
        // cancels the move, same as releasing off the native bar.
        if (drop && !pointerInIslandZone(edge, islandDragScreenX, islandDragScreenY)) drop = null

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
        if ((drop ? drop.slot : null) !== islandDragTargetSlot
            || (drop ? drop.after : false) !== islandDragAfter) {
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
                "· cursor=" + Math.round(islandDragScreenX) + "," + Math.round(islandDragScreenY),
                "· axis=" + (!isHorizontal ? "y" : "x"))
            console.warn("[RAIL] candidates:", dbgParts.join(" | "))
        }

        islandDragTargetSlot = drop ? drop.slot : null
        islandDragAfter = drop ? drop.after : false
        islandDragTargetGeometry = drop ? islandDropMarkerRect(drop.slot, drop.after) : null

        // Outside our zone the native bar strip may offer a
        // landing spot (island -> bar). Cleared automatically on each update.
        updateIslandToBarTarget(islandDragScreenX, islandDragScreenY)
    }

    function islandDropMarkerRect(targetSlot, after) {
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

    function finishIslandDrag() {
        var src = islandDragSourceSlot
        var homeTgt = islandDragTargetSlot
        var homeAfter = islandDragAfter

        // Cross-surface claims, mutually exclusive by geometry:
        // a peer panel's island offer (island -> other island) or our own native-
        // bar strip target (island -> bar).
        var peer = null
        if (moveHost) {
            for (var pi = 0; pi < moveHost.islandPanels.length; pi++) {
                var pp = moveHost.islandPanels[pi]
                if (pp !== islandWindow && pp.barDropTargetSlot) { peer = pp; break }
            }
        }
        var peerTgt = peer ? peer.barDropTargetSlot : null
        var peerAfter = peer ? peer.barDropAfter : false
        var barTgt = islandToBarTargetSlot
        var barAfter = islandToBarAfter
        var barName = islandToBarTargetName
        var barOrd = islandToBarTargetOrdinal

        clearIslandDrag()   // also resets hub cursor/edge + islandToBar*
        if (peer && peer.clearBarDrop) peer.clearBarDrop()

        if (!src || !canMutateIsland) {
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
            console.warn("[RAIL] cross-island drop:", edge,
                src.moduleName + "@" + src.section + "[" + srcIdx + "]",
                "->", peer.edge, (peerTgt.isPlaceholder ? "append@" + peerTgt.section
                    : peerTgt.moduleName + "@" + peerTgt.section + "[" + pIdx + "]"),
                "after=" + peerAfter)
            barApi.shell.mutateShellConfig(function(config) {
                var changed = IslandModel.moveIslandEntryBetweenEdges(
                    config, edge, src.section, srcIdx, peer.edge, peerTgt.section, pIdx, peerAfter)
                console.warn("[RAIL] cross-island result:", changed ? "MOVED" : "IDENTITY (no write)")
            })
            return
        }

        if (barTgt) {
            var region = String(barTgt.region || "")
            var tName = barName
            var tOrd = barOrd
            console.warn("[RAIL] island->bar drop:", edge,
                src.moduleName + "@" + src.section + "[" + srcIdx + "]",
                "-> bar." + region, tName + "#" + tOrd, "after=" + barAfter)
            barApi.shell.mutateShellConfig(function(config) {
                // Resolve against the REAL layout array inside the mutation:
                // moduleSlots order diverges from layout after live changes,
                // so position by name + occurrence ordinal (upstream parity).
                var entries = IslandModel.barLayoutSection(config, region)
                var idx = IslandModel.barEntryIndexOfOccurrence(entries, tName, tOrd)
                console.warn("[RAIL][DBG] resolve:", region,
                    "entries=", entries.map(function(e) { return IslandModel.entryId(e) }).join("|"),
                    "name=", tName, "ord=", tOrd, "-> idx=", idx)
                var destIdx = idx < 0 ? entries.length : idx + (barAfter ? 1 : 0)
                var changed = IslandModel.moveIslandEntryToBarAt(
                    config, edge, src.section, srcIdx, region, destIdx)
                console.warn("[RAIL] island->bar result:", changed ? "MOVED" : "NOT MOVED")
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
            var changed = IslandModel.moveIslandEntryAt(
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

        WlrLayershell.namespace: "omarchy-widget-islands-" + edge
    WlrLayershell.layer: WlrLayer.Top

    color: "transparent"
    surfaceFormat.opaque: false

    // Full-edge hover surface with no visible island and no reservation.
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
        window: islandWindow
    }

    // 3.3 — hints: one dot per widget centered in each third, hitbox = whole third
    IslandHints {
        anchors.fill: parent
        edge: islandWindow.edge
        islandLayout: islandWindow.islandLayout
        hoveredSection: islandWindow.hoveredSection
        dotColor: islandWindow.foregroundColor
        dotColors: islandWindow.indicatorColors
    }

        HoverHandler {
        id: islandHover
        onHoveredChanged: {
            if (!hovered) {
                islandWindow.hoveredSection = ""
                hoverCloseTimer.restart()
            } else {
                hoverCloseTimer.stop()
            }
        }
        onPointChanged: {
            if (!islandHover.hovered) return
            var p = islandHover.point.position
            var sec = ""
            if (islandWindow.isHorizontal) {
                var thirdW = islandWindow.width / 3
                if (p.x < thirdW) sec = "left"
                else if (p.x < thirdW * 2) sec = "center"
                else sec = "right"
            } else {
                var thirdH = islandWindow.height / 3
                if (p.y < thirdH) sec = "left"
                else if (p.y < thirdH * 2) sec = "center"
                else sec = "right"
            }
            islandWindow.hoveredSection = sec
            // Reveal the island for a dotful section on hover.
            // (frozen while a widget is being dragged)
            if (sec !== "" && !islandWindow.dragModeActive
                && sec !== islandWindow.activeSection
                && IslandModel.sectionHasWidgets(islandWindow.islandLayout, sec)) {
                console.warn("[RAIL]", islandWindow.edge, "hover-activate:", sec)
                islandWindow.activeSection = sec
                hoverCloseTimer.stop()
            }
        }
    }

    Timer {
        id: hoverCloseTimer
        interval: 180
        onTriggered: {
            if (islandWindow.dragModeActive) return
            if (islandHover.hovered) return
            for (var i = 0; i < islands.length; i++) {
                var isl = islands[i]
                if (isl && (isl.pointerInside || isl.pinnedByPanel)) return
            }
            islandWindow.activeSection = ""
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

    readonly property var indicatorColors: ({
        left: indicatorColorsFor("left"),
        center: indicatorColorsFor("center"),
        right: indicatorColorsFor("right")
    })
    function indicatorColorsFor(section) {
        for (var i = 0; i < islands.length; i++) {
            var isl = islands[i]
            if (isl && isl.section === section) return isl.indicatorColors
        }
        return []
    }

    // One island per section. Normal mode reveals only activeSection; during a
    // island widget drag ALL populated sections reveal at once — the affordance
    // that says "you can drop it there".
    //
    // Variants, not Repeater: these are PANEL WINDOWS, and Quickshell only
    // creates real layer surfaces through Variants (same as Bar.qml per-screen
    // windows). A Repeater of PanelWindows silently never maps.
    Variants {
        model: ["left", "center", "right"]

        delegate: Component {
            Island {
                required property string modelData

                screen: islandWindow.screen
                edge: islandWindow.edge
                section: modelData
                centerFrac: (["left", "center", "right"].indexOf(modelData) + 0.5) / 3
                entries: islandWindow.islandLayout ? (islandWindow.islandLayout[modelData] || []) : []
                registry: islandWindow.widgetRegistry
                barApi: islandWindow.barApi
                thickness: islandWindow.thickness
                barSize: islandWindow.barSize
                backgroundColor: islandWindow.backgroundColor
                foregroundColor: islandWindow.foregroundColor
                transparent: islandWindow.transparent
                fontFamily: islandWindow.fontFamily
                dragHost: islandWindow
                // Parked windows: mapped whenever the island exists; reveal
                // logic lives inside the island (revealed property).
                visible: islandWindow.shouldShow && !remapGuard.remapping
                onCloseRequested: if (!islandWindow.islandDragActive) islandWindow.activeSection = ""
                onPointerInsideChanged: {
                    if (pointerInside) hoverCloseTimer.stop()
                    else if (!islandHover.hovered && !pinnedByPanel)
                        hoverCloseTimer.restart()
                }
                onPinnedByPanelChanged: {
                    // Panel closed → resume normal dismissal only if pointer is gone
                    if (pinnedByPanel) hoverCloseTimer.stop()
                    else if (!islandHover.hovered && !pointerInside)
                        hoverCloseTimer.restart()
                }
            }
        }
    }

    // Drag feedback overlay (mirrors Bar.qml's DragGhostPanel): the
    // grabbed widget follows the cursor and an accent line marks where it
    // would land. Visual-only: empty input region keeps the pointer grab with
    // the MouseArea that started the drag.
    component IslandDragGhostPanel: PanelWindow {
        id: ghostWindow

        readonly property bool active: islandWindow.islandDragActive
        readonly property var sourceItem: islandWindow.islandDragSourceSlot
            ? islandWindow.islandDragSourceSlot.activeItem : null
        readonly property int ghostPadding: Style.space(1)
        readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
        readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

        // Island-initiated drags ONLY: the bar paints its own ghost natively,
        // and insertion lines now live inside the island windows. Keeping this
        // unmapped during bar drags removes 4 pointless fullscreen mappings
        // from every bar-drag start.
        visible: active && sourceItem !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-widget-islands-drag-ghost-" + islandWindow.edge
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
            visible: islandWindow.islandDragImageUrl !== ""
            x: Math.round(islandWindow.islandDragScreenX - islandWindow.islandDragOffsetX - ghostWindow.ghostPadding)
            y: Math.round(islandWindow.islandDragScreenY - islandWindow.islandDragOffsetY - ghostWindow.ghostPadding)
            width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
            height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

            BorderSurface {
                anchors.fill: parent
                color: islandWindow.transparent ? "transparent" : islandWindow.backgroundColor
                borderSpec: Border.flat(islandWindow.foregroundColor, 1)
                radius: Math.min(Style.cornerRadius, height / 2)
                opacity: islandWindow.transparent ? 0.45 : 0.94
            }

            Image {
                anchors.fill: parent
                anchors.margins: ghostWindow.ghostPadding
                source: islandWindow.islandDragImageUrl
                fillMode: Image.Stretch
                smooth: true
                opacity: 0.84
            }
        }

        // NOTE: island targets paint their own segment inside the island
        // window (localDropGeometry). This window only draws the NATIVE BAR
        // target line for island->bar drags — Overlay deterministically sits
        // above the bar's Top layer, and the strip never overlaps islands.
        Rectangle {
            readonly property var targetRect: islandWindow.islandToBarGeometry

            visible: ghostWindow.active && targetRect !== null
            x: targetRect ? Math.round(targetRect.x) : 0
            y: targetRect ? Math.round(targetRect.y) : 0
            width: targetRect ? targetRect.width : 0
            height: targetRect ? targetRect.height : 0
            color: Color.accent
            radius: Math.min(width, height) / 2
        }
    }

    IslandDragGhostPanel {
        screen: islandWindow.screen
    }

}
