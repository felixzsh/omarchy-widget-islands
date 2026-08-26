import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../RailModel.js" as RailModel

// Floating HUD revealing one section's widgets as fully interactive modules.
//
// The HUD is drawn inside an edge-sized anchor surface. The surface keeps the
// coordinate contract expected by KeyboardPanel while its background remains
// transparent and only the detached HUD is masked for input.
//
// Overlay + Ignore only: never touches reserved, workspace never resizes.
// Instant show/hide (no animation by design).
PanelWindow {
    id: root

    required property var screen
    required property string edge
    // Section center along the screen axis, as 0..1 fraction
    required property real centerFrac
    required property var entries
    required property var registry
    required property var barApi
    required property int thickness
    required property int barSize
    required property color backgroundColor
    required property color foregroundColor
    required property bool transparent
    required property string fontFamily
    // Which section this island reveals + RailPanel drag API
    required property string section
    required property var dragHost

    // Parked-window mode: the layer surface stays MAPPED for the rail's life;
    // revealing flips content + input mask (~one commit) instead of creating
    // surfaces. Mapping storms at bar-drag start stalled the native bar's own
    // ghost — same reason Bar.qml parks instead of unmapping (~150ms vs ~20ms).
    readonly property bool revealed: dragHost !== null
        && (dragHost.dragModeActive
            || (dragHost.activeSection === section && entries.length > 0))

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

    // Tunables for the floating HUD footprint.
    readonly property int totalDepth: Math.max(thickness + 2, Math.round(barSize * 0.85))
    readonly property int hudGap: Style.space(3)
    readonly property int pad: Style.space(1)

    // Actual screen origin for drag geometry and cross-window drop targets.
    function screenOrigin() {
        var sw = screen ? screen.width : 0
        var sh = screen ? screen.height : 0
        return horizontal
            ? { x: 0, y: edge === "bottom" ? sh - totalDepth - hudGap : hudGap }
            : { x: edge === "right" ? sw - totalDepth - hudGap : hudGap, y: 0 }
    }

    // HUD geometry in window-local coords.
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

    // Hosted widget slots, registered by RailIslandWidget so the drag
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

    implicitWidth: horizontal ? Math.round(screen ? screen.width : 0) : root.totalDepth
    implicitHeight: horizontal ? root.totalDepth : Math.round(screen ? screen.height : 0)

    anchors {
        top: root.edge === "top" || root.edge === "left" || root.edge === "right"
        bottom: root.edge === "bottom" || root.edge === "left" || root.edge === "right"
        left: root.edge === "top" || root.edge === "bottom" || root.edge === "left"
        right: root.edge === "top" || root.edge === "bottom" || root.edge === "right"
    }

    margins {
        top: root.edge === "top" ? root.hudGap : 0
        bottom: root.edge === "bottom" ? root.hudGap : 0
        left: root.edge === "left" ? root.hudGap : 0
        right: root.edge === "right" ? root.hudGap : 0
    }

    // The painted, interactive floating HUD.
    Rectangle {
        id: tab

        x: root.horizontal ? Math.max(0, Math.min(
              Math.round(root.centerFrac * parent.width - width / 2), parent.width - width)) : 0
        y: !root.horizontal ? Math.max(0, Math.min(
              Math.round(root.centerFrac * parent.height - height / 2), parent.height - height)) : 0
        width: root.horizontal ? root.length : root.totalDepth
        height: root.horizontal ? root.totalDepth : root.length

        color: root.backgroundColor
        radius: Style.cornerRadius
        visible: root.revealed

        BorderSurface {
            anchors.fill: parent
            color: "transparent"
            borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
            radius: parent.radius
        }
    }

    // Input restricted to the HUD while revealed; hidden = fully click-through.
    mask: Region { item: root.revealed ? tab : null }

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
        visible: root.horizontal && root.revealed
        spacing: 0
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
        visible: !root.horizontal && root.revealed
        spacing: 0
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

    // Insertion line for the active drop target, painted by the OWNING
    // island (same-layer Overlay stacking across windows is map-order
    // dependent; inside one window z-order is deterministic).
    Rectangle {
        readonly property var r: dragHost ? dragHost.localDropGeometry(root) : null

        visible: r !== null && root.revealed
        x: r ? Math.round(r.x) : 0
        y: r ? Math.round(r.y) : 0
        width: r ? r.width : 0
        height: r ? r.height : 0
        color: Color.accent
        radius: Math.min(width, height) / 2
        z: 100
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
