import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../RailModel.js" as RailModel

// 3.5 experiment A — RailIsland: rectangular tab protruding out of the rail
// edge, revealing one section's widgets as fully interactive native modules.
//
// Window geometry mirrors the MAIN BAR (BarPanel): the surface spans the FULL
// edge it lives on, flush with the screen corners. That is what makes summon
// adjacency work — KeyboardPanel/PopupCard treat anchor-window-local coords as
// screen coords (valid for the flush main bar, valid for us too), so panels
// open aligned to the clicked widget exactly like from main. The visible tab
// is painted inside at the active section's span, and `mask` limits input to
// the tab so sibling sections stay interactive.
//
// Overlay + Ignore only: never touches reserved, workspace never resizes.
// Instant show/hide (no animation by design).
PanelWindow {
    id: root

    required property var screen
    required property string edge
    // Section center along the rail axis, as 0..1 fraction
    required property real centerFrac
    // Trapped span of the rail along its axis (between main and parallel)
    required property int spanStart
    required property int spanLen
    required property var entries
    required property var registry
    required property var barApi
    required property int thickness
    required property int barSize
    required property color backgroundColor
    required property color foregroundColor
    required property bool transparent
    required property string fontFamily
    // 3.6 — which section this island reveals + RailPanel drag API
    required property string section
    required property var dragHost
    property bool clickMode: false

    readonly property bool pointerInside: islandHover.hovered
    // While any hosted widget has its panel open, the island is pinned:
    // hover-leave must not dismiss it (the widget lives here — closing the
    // island would kill its panel).
    readonly property bool pinnedByPanel: {
        var kids = horizontal ? contentRow.children : contentColumn.children
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (k && k.panelOpen === true) return true
        }
        return false
    }
    signal closeRequested()

    // Self-register into the RailPanel's islands list (Variants can't be
    // enumerated from outside; the drag machinery and dismissal timer need
    // to iterate live islands).
    Component.onCompleted: if (dragHost && dragHost.registerIsland) dragHost.registerIsland(root)
    Component.onDestruction: if (dragHost && dragHost.unregisterIsland) dragHost.unregisterIsland(root)

    // Tunables. totalDepth INCLUDES the strip overlap: rail third + protrusion
    // == 70% of main bar thickness.
    readonly property int totalDepth: Math.max(thickness + 2, Math.round(barSize * 0.7))
    readonly property int depthOut: totalDepth - thickness
    readonly property int pad: Style.space(3)

    // 3.6 — window origin in screen coords (full-edge span, flush corners).
    // NOTE: the window's own width/height are NOT screen-sized on every edge
    // (the bottom island is a thin horizontal strip, the right island a thin
    // vertical one) — always derive from the SCREEN, never from this window.
    function screenOrigin() {
        var sw = screen ? screen.width : 0
        var sh = screen ? screen.height : 0
        var x = 0
        var y = 0
        if (edge === "bottom") y = sh - totalDepth
        else if (edge === "right") x = sw - totalDepth
        return { x: x, y: y }
    }

    // Tab geometry in window-local coords.
    function tabPoint() {
        var p = tab.mapToItem(null, 0, 0)
        return { x: p.x, y: p.y }
    }

    // Synthetic drop target for an empty section: the whole tab is the zone.
    readonly property var placeholderTarget: ({
        isPlaceholder: true,
        host: root,
        section: root.section,
        moduleName: "",
        width: tab.width,
        height: tab.height
    })

    // 3.6 — hosted widget slots, registered by RailIslandWidget so the drag
    // machinery can collect drop candidates across all revealed islands.
    property var moduleSlots: []
    function registerModuleSlot(s) {
        if (!s) return
        var next = moduleSlots.slice()
        if (next.indexOf(s) !== -1) return
        next.push(s)
        moduleSlots = next
    }
    function unregisterModuleSlot(s) {
        var next = moduleSlots.filter(function(t) { return t !== s })
        if (next.length === moduleSlots.length) return
        moduleSlots = next
    }

    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property int contentLength: horizontal ? contentRow.implicitWidth : contentColumn.implicitHeight
    readonly property int length: Math.max(totalDepth, contentLength + pad * 2)

    visible: false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-rails-island-" + edge
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    surfaceFormat.opaque: false

    // Full-edge span, flush with the screen corners — main-bar contract.
    implicitWidth: horizontal ? Math.round(screen ? screen.width : 0) : totalDepth
    implicitHeight: horizontal ? totalDepth : Math.round(screen ? screen.height : 0)

    anchors {
        top: edge === "top" || edge === "left" || edge === "right"
        bottom: edge === "bottom" || edge === "left" || edge === "right"
        left: edge === "top" || edge === "bottom" || edge === "left"
        right: edge === "right"
    }

    // The painted, interactive tab. Placed at the active section's span,
    // flush against the rail strip.
    Rectangle {
        id: tab

        readonly property int crossPos: root.edge === "bottom" ? parent.height - height
            : root.edge === "right" ? parent.width - width : 0

        x: root.horizontal ? Math.max(root.spanStart, Math.min(
              Math.round(root.spanStart + root.centerFrac * root.spanLen - width / 2),
              root.spanStart + root.spanLen - width)) : crossPos
        y: !root.horizontal ? Math.max(root.spanStart, Math.min(
              Math.round(root.spanStart + root.centerFrac * root.spanLen - height / 2),
              root.spanStart + root.spanLen - height)) : crossPos
        width: root.horizontal ? root.length : root.totalDepth
        height: root.horizontal ? root.totalDepth : root.length

        color: root.backgroundColor
    }

    // Input restricted to the tab: clicks elsewhere fall through (to the
    // rails below, the desktop, or the click-catcher while armed).
    mask: Region { item: tab }

    // Duck-contract shim handed to hosted widgets: mirrors innerBar except
    // position/vertical, which reflect THIS rail's edge.
    RailBarShim {
        id: railBar
        source: root.barApi
        edgeOverride: root.edge
        fallbackSize: root.barSize
        fallbackForeground: root.foregroundColor
        fallbackBackground: root.backgroundColor
        fallbackFontFamily: root.fontFamily
    }

    HoverHandler {
        id: islandHover
    }

    Row {
        id: contentRow
        visible: root.horizontal
        spacing: Style.space(2)
        anchors.centerIn: tab

        Repeater {
            // Only the active orientation instantiates delegates (the other
            // container is hidden; duplicating widgets would double-register
            // drag slots).
            model: root.horizontal ? root.entries : []
            delegate: RailIslandWidget {
                registry: root.registry
                barObj: railBar
                edge: root.edge
                host: root
                dragHost: root.dragHost
                section: root.section
            }
        }
    }

    Column {
        id: contentColumn
        visible: !root.horizontal
        spacing: Style.space(2)
        anchors.centerIn: tab

        Repeater {
            model: !root.horizontal ? root.entries : []
            delegate: RailIslandWidget {
                registry: root.registry
                barObj: railBar
                edge: root.edge
                host: root
                dragHost: root.dragHost
                section: root.section
            }
        }
    }

    component IslandCatcher: PanelWindow {
        required property var catcherScreen
        visible: false
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-rails-island-catcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        surfaceFormat.opaque: false
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        MouseArea {
            anchors.fill: parent
            onPressed: function(mouse) {
                mouse.accepted = true
                root.closeRequested()
            }
        }
    }

    // Outside-click dismiss for click trigger. Armed a beat after the island
    // maps so the catcher never lands above the island surface.
    property bool catcherArmed: false
    Timer {
        id: catchArmTimer
        interval: 80
        onTriggered: root.catcherArmed = true
    }
    onVisibleChanged: {
        if (visible) {
            root.catcherArmed = false
            catchArmTimer.restart()
        } else {
            root.catcherArmed = false
        }
    }
    IslandCatcher {
        catcherScreen: root.screen
        visible: root.visible && root.clickMode && root.catcherArmed
            && !(root.dragHost && root.dragHost.railDragActive)
    }

    // Duck-contract proxy over the main bar. Everything delegates to innerBar
    // except position/vertical, which reflect this rail's edge so summoned
    // panels (KeyboardPanel reads bar.position) land next to the rail.
    component RailBarShim: QtObject {
        required property var source
        property string edgeOverride: "top"
        property int fallbackSize: 26
        property color fallbackForeground
        property color fallbackBackground
        property string fallbackFontFamily: ""

        readonly property string position: edgeOverride
        readonly property bool vertical: edgeOverride === "left" || edgeOverride === "right"
        readonly property int barSize: source ? source.barSize : fallbackSize
        readonly property bool barHidden: source ? source.barHidden : false
        readonly property color foreground: source ? source.foreground : fallbackForeground
        readonly property color background: source ? source.background : fallbackBackground
        readonly property string fontFamily: source && source.fontFamily !== "" ? source.fontFamily : fallbackFontFamily
        readonly property var shell: source ? source.shell : null
        readonly property var activePopout: source ? source.activePopout : null

        // Island-local WidgetButtons self-register here via onBarChanged →
        // syncClickRegistration (injectProps hands them this shim as `bar`).
        // KeyboardPanel.dismissArea → forwardBarClick resolves these targets,
        // so ONE click on another island widget swaps panels instead of just
        // dismissing — same behavior as clicking another icon on the main bar.
        property var ownClickTargets: []

        function registerClickTarget(target) {
            if (!target) return
            var next = ownClickTargets.slice()
            if (next.indexOf(target) !== -1) return
            next.push(target)
            ownClickTargets = next
        }

        function unregisterClickTarget(target) {
            var next = ownClickTargets.filter(function(t) { return t !== target })
            if (next.length === ownClickTargets.length) return
            ownClickTargets = next
        }

        readonly property var clickTargets: {
            var base = source ? source.clickTargets : null
            if (!base || !base.length) return ownClickTargets.slice()
            return base.concat(ownClickTargets)
        }

        function targetBelongsToWindow(target, window) {
            return source ? source.targetBelongsToWindow(target, window) : false
        }
        function run(command) { return source ? source.run(command) : undefined }
        function showTooltip(target, text) { return source ? source.showTooltip(target, text) : undefined }
        function hideTooltip(target) { return source ? source.hideTooltip(target) : undefined }
        function requestPopout(owner) { return source ? source.requestPopout(owner) : undefined }
        function releasePopout(owner) { return source ? source.releasePopout(owner) : undefined }
        function summonBarWidget(id) { return source ? source.summonBarWidget(id) : false }
        function hideBarWidget(id) { return source ? source.hideBarWidget(id) : false }
        function isBarWidgetOpen(id) { return source ? source.isBarWidgetOpen(id) : false }
        function toggleTransparency() { return source ? source.toggleTransparency() : undefined }
    }
}