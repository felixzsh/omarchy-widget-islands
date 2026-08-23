import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../BarModel.js" as BarModel
import "../RailModel.js" as RailModel

// RailPanel — visual overlay (ponytail: no reservation, keeps main 0,0 full).
// Only side rails are trapped; parallel stays full-span.
PanelWindow {
    id: railWindow

    required property var screen
    required property string edge
    // Provided by RailsBar
    property string mainPosition: "top"
    property int thickness: 8
    property int barSize: 26
    property bool barHidden: false
    // Whether this rail has widgets (for future dots — not used for visibility)
    property bool hasWidgets: true
    property bool railsEnabled: true
    // Colors from innerBar
    property color backgroundColor: Color.bar.background
    property bool transparent: false
    // Hints data — per-edge layout for 3 thirds
    property var railLayout: ({ left: [], center: [], right: [] })
    property string trigger: "hover"
    property color foregroundColor: Color.bar.text
    // Container swap host (RailsBar root)
    property var moveHost: null
    // Section under the pointer (left/center/right), fed by railHover
    property string hoveredSection: ""
    // 3.5 — host-injected for island widgets
    property var barApi: null
    property var widgetRegistry: null
    property string fontFamily: ""
    // 3.5 — the section whose island is currently revealed ("" = none)
    property string activeSection: ""

    function sectionHasEntries(section) {
        return RailModel.sectionHasWidgets(railLayout, section)
    }

    // Derived
    readonly property bool isHorizontal: edge === "top" || edge === "bottom"
    readonly property string opposite: {
        if (mainPosition === "top") return "bottom"
        if (mainPosition === "bottom") return "top"
        if (mainPosition === "left") return "right"
        return "left"
    }
    readonly property bool isParallel: edge === opposite
    readonly property bool isSide: !isParallel && edge !== mainPosition
    readonly property bool shouldShow: railsEnabled && edge !== mainPosition && !barHidden
    onShouldShowChanged: if (!shouldShow) activeSection = ""

    // 3.5 — trapped span of this rail along its axis (between main and the
    // parallel rail). Islands align their tab within THIS span so they sit
    // centered over their section's dots instead of the raw screen edge.
    readonly property int spanStart: isHorizontal ? margins.left : margins.top
    readonly property int spanLen: isHorizontal
        ? Math.max(0, Math.round((screen ? screen.width : 0) - margins.left - margins.right))
        : Math.max(0, Math.round((screen ? screen.height : 0) - margins.top - margins.bottom))

    // 3.6 — intra-rail widget drag & drop state (mirrors Bar.qml's barDrag*)
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

    // 3.7 — universal DnD step 1: BAR → RAIL. While the native bar drags one
    // of ITS widgets, this rail reveals all islands and tracks the cursor to
    // offer drop targets. The bar's own intra-bar behavior is untouched; we
    // only observe public state (barDragSource/barDragScreenX/Y).
    readonly property bool barDragging: barApi !== null && barApi.barDragSource !== null
    readonly property bool dragModeActive: railDragActive || barDragging

    // Source identity captured CONTINUOUSLY while the bar drags — the bar
    // clears barDragSource before deciding its own drop, so reading it at
    // release time would already be too late.
    property var barCrossSource: null
    property var barDropTargetSlot: null
    property bool barDropAfter: false
    property var barDropGeometry: null

    function clearBarDrop() {
        barCrossSource = null
        barDropTargetSlot = null
        barDropAfter = false
        barDropGeometry = null
    }

    function updateBarDropTarget() {
        if (!barDragging || !barApi.barDragSource) { clearBarDrop(); return }
        var src = barApi.barDragSource
        barCrossSource = { region: String(src.region || ""), moduleName: String(src.moduleName || "") }

        var px = barApi.barDragScreenX
        var py = barApi.barDragScreenY

        barDropTargetSlot = null
        barDropAfter = false
        barDropGeometry = null
        if (!pointerInRailZone(edge, px, py)) return

        // Same selection mechanics as intra-rail: EVERY visible island's slots
        // (+ empty-tab placeholders) compete by proximity; the zone gate above
        // is the only containment. Between two tabs the line pins to the
        // nearest island's edge — identical to a rail-initiated drag.
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

    // 3.7 — insertion line is painted INSIDE the owning island's window.
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

    Connections {
        target: barApi
        function onBarDragSourceChanged() {
            if (barApi && barApi.barDragSource) railWindow.updateBarDropTarget()
            else railWindow.finishBarDropToRail()
        }
        function onBarDragScreenXChanged() { if (railWindow.barDragging) railWindow.updateBarDropTarget() }
        function onBarDragScreenYChanged() { if (railWindow.barDragging) railWindow.updateBarDropTarget() }
    }

    // 3.7 — acceptance zone: drops and empty-tab reveals only count while the
    // dragged pointer sits at THIS rail's edge, inside the trapped span
    // (+grace). Mirrors the native bar, which ignores releases outside its
    // window — without this, every release lands somewhere.
    readonly property int zoneGrace: Style.space(6)
    function pointerInRailZone(pEdge, px, py) {
        var sw = screen ? screen.width : 0
        var sh = screen ? screen.height : 0
        var depth = Math.max(thickness + 2, Math.round(barSize * 0.85)) + zoneGrace
        var start = spanStart - zoneGrace
        var end = spanStart + spanLen + zoneGrace
        if (pEdge === "top") return py <= depth && px >= start && px <= end
        if (pEdge === "bottom") return py >= sh - depth && px >= start && px <= end
        if (pEdge === "left") return px <= depth && py >= start && py <= end
        return px >= sw - depth && py >= start && py <= end
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
    }

    function updateRailDrag(slot, scenePoint) {
        if (!railDragActive || slot !== railDragSourceSlot) return

        var srcIsl = railDragSourceSlot.host
        var so = srcIsl ? srcIsl.screenOrigin() : { x: 0, y: 0 }
        railDragScreenX = so.x + scenePoint.x
        railDragScreenY = so.y + scenePoint.y

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
        var tgt = railDragTargetSlot
        var after = railDragAfter
        clearRailDrag()
        if (!src || !tgt || !canMutateRail) {
            console.warn("[RAIL] drop: CANCEL",
                "src=", src ? (src.moduleName + "@" + src.section) : "null",
                "tgt=", tgt ? (tgt.isPlaceholder ? "PH@" + tgt.section : tgt.moduleName + "@" + tgt.section) : "null")
            return
        }

        // Index-addressed move: slot order in moduleSlots mirrors the section
        // layout, so resolve positions by identity — duplicate ids (two
        // omarchy.audio entries, say) can't hijack name lookups anymore.
        var srcIdx = slotIndexIn(src.host ? src.host.moduleSlots : [], src)
        var tgtIdx = tgt.isPlaceholder ? -1 : slotIndexIn(tgt.host ? tgt.host.moduleSlots : [], tgt)
        if (srcIdx < 0) return

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

    color: transparent ? "transparent" : backgroundColor
    surfaceFormat.opaque: false

    // Size: thickness along the exclusive edge
    implicitWidth: isHorizontal ? 0 : thickness
    implicitHeight: isHorizontal ? thickness : 0

    anchors {
        top: edge === "top" || edge === "left" || edge === "right"
        bottom: edge === "bottom" || edge === "left" || edge === "right"
        left: edge === "left" || edge === "top" || edge === "bottom"
        right: edge === "right" || edge === "top" || edge === "bottom"
    }

    // Trapped margins for side rails: inset between main and parallel
    // Vertical side rails (left/right) need top/bottom margins
    // Horizontal side rails (top/bottom) need left/right margins
    margins {
        top: {
            if (!isSide) return 0
            // side is vertical (left/right)
            if (edge === "left" || edge === "right") {
                if (mainPosition === "top") return barSize
                if (mainPosition === "bottom") return thickness
            }
            return 0
        }
        bottom: {
            if (!isSide) return 0
            if (edge === "left" || edge === "right") {
                if (mainPosition === "top") return thickness
                if (mainPosition === "bottom") return barSize
            }
            return 0
        }
        left: {
            if (!isSide) return 0
            if (edge === "top" || edge === "bottom") {
                if (mainPosition === "left") return barSize
                if (mainPosition === "right") return thickness
            }
            return 0
        }
        right: {
            if (!isSide) return 0
            if (edge === "top" || edge === "bottom") {
                if (mainPosition === "left") return thickness
                if (mainPosition === "right") return barSize
            }
            return 0
        }
    }

    function windowScreenPoint(scenePoint) {
        if (!screen) return scenePoint
        var ox = 0, oy = 0
        if (edge === "top") {
            oy = 0
            if (isSide) ox = mainPosition === "left" ? barSize : thickness
        } else if (edge === "bottom") {
            oy = screen.height - thickness
            if (isSide) ox = mainPosition === "left" ? barSize : thickness
        } else if (edge === "left") {
            ox = 0
            oy = mainPosition === "top" ? barSize : (mainPosition === "bottom" ? thickness : 0)
        } else if (edge === "right") {
            ox = screen.width - thickness
            oy = mainPosition === "top" ? barSize : (mainPosition === "bottom" ? thickness : 0)
        }
        return { x: scenePoint.x + ox, y: scenePoint.y + oy }
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
        trigger: railWindow.trigger
        hoveredSection: railWindow.hoveredSection
        dotColor: railWindow.foregroundColor
    }

        HoverHandler {
        id: railHover
        onHoveredChanged: {
            if (!hovered) {
                railWindow.hoveredSection = ""
                if (railWindow.trigger === "hover") hoverCloseTimer.restart()
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
            // 3.5 — hover trigger: reveal the island for a dotful section
            // (frozen while a widget is being dragged)
            if (sec !== "" && !railWindow.dragModeActive
                && sec !== railWindow.activeSection
                && RailModel.sectionHasWidgets(railWindow.railLayout, sec)) {
                console.warn("[RAIL]", railWindow.edge, "hover-activate:", sec)
                if (railWindow.trigger === "hover") {
                    railWindow.activeSection = sec
                    hoverCloseTimer.stop()
                }
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
                spanStart: railWindow.spanStart
                spanLen: railWindow.spanLen
                entries: railWindow.railLayout ? (railWindow.railLayout[modelData] || []) : []
                registry: railWindow.widgetRegistry
                barApi: railWindow.barApi
                thickness: railWindow.thickness
                barSize: railWindow.barSize
                backgroundColor: railWindow.backgroundColor
                foregroundColor: railWindow.foregroundColor
                transparent: railWindow.transparent
                fontFamily: railWindow.fontFamily
                clickMode: railWindow.trigger === "click"
                dragHost: railWindow
                // Parked windows: mapped whenever the rail exists; reveal
                // logic lives inside the island (revealed property).
                visible: railWindow.shouldShow && !remapGuard.remapping
                onCloseRequested: if (!railWindow.railDragActive) railWindow.activeSection = ""
                onPointerInsideChanged: {
                    if (pointerInside) hoverCloseTimer.stop()
                    else if (railWindow.trigger === "hover" && !railHover.hovered && !pinnedByPanel)
                        hoverCloseTimer.restart()
                }
                onPinnedByPanelChanged: {
                    // Panel closed → resume normal dismissal only if pointer is gone
                    if (pinnedByPanel) hoverCloseTimer.stop()
                    else if (railWindow.trigger === "hover" && !railHover.hovered && !pointerInside)
                        hoverCloseTimer.restart()
                }
            }
        }
    }

    // 3.6 — drag feedback overlay (mirrors Bar.qml's DragGhostPanel): the
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

        // NOTE: no insertion line here anymore — islands paint their own
        // segment via localDropGeometry() (deterministic z-order).
    }

    RailDragGhostPanel {
        screen: railWindow.screen
    }

    MouseArea {
        id: containerDragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
        pressAndHoldInterval: 200

        property bool dragging: false
        property bool suppressClick: false
        property real pressedX: 0
        property real pressedY: 0
        readonly property real dragThreshold: Style.space(4)

        function startDrag(x, y) {
            if (dragging) return
            dragging = true
            if (railWindow.moveHost) railWindow.moveHost.beginContainerMove(railWindow.edge, railWindow)
            var scenePoint = containerDragArea.mapToItem(null, x, y)
            var screenPoint = railWindow.windowScreenPoint(scenePoint)
            if (railWindow.moveHost) railWindow.moveHost.updateContainerMove(screenPoint)
        }

        onPressed: function(mouse) {
            dragging = false
            suppressClick = false
            pressedX = mouse.x
            pressedY = mouse.y
        }

        onPressAndHold: function(mouse) {
            if (!containerDragArea.pressed) return
            startDrag(mouse.x, mouse.y)
        }

        onPositionChanged: function(mouse) {
            if (!(mouse.buttons & Qt.LeftButton)) return
            if (!dragging) {
                var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
                if (distance < dragThreshold) return
                startDrag(mouse.x, mouse.y)
                return
            }
            var scenePoint = containerDragArea.mapToItem(null, mouse.x, mouse.y)
            var screenPoint = railWindow.windowScreenPoint(scenePoint)
            if (railWindow.moveHost) railWindow.moveHost.updateContainerMove(screenPoint)
        }

        onReleased: function(mouse) {
            if (!dragging) return
            dragging = false
            suppressClick = true
            if (railWindow.moveHost) railWindow.moveHost.finishContainerMove()
            mouse.accepted = true
        }

        onCanceled: {
            dragging = false
            suppressClick = false
            if (railWindow.moveHost) railWindow.moveHost.clearContainerMove()
        }

        onClicked: function(mouse) {
            if (suppressClick) {
                suppressClick = false
                mouse.accepted = true
                return
            }
            // 3.5 — click trigger: toggle the island for the hovered section
            if (railWindow.trigger === "click" && railWindow.hoveredSection !== ""
                && RailModel.sectionHasWidgets(railWindow.railLayout, railWindow.hoveredSection)) {
                railWindow.activeSection = railWindow.activeSection === railWindow.hoveredSection
                    ? "" : railWindow.hoveredSection
                mouse.accepted = true
            }
        }
    }
}
