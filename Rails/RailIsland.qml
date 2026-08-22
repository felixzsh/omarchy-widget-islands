import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../RailModel.js" as RailModel

// 3.5 experiment A — RailIsland: rectangular tab protruding out of the rail
// edge, revealing one section's widgets as fully interactive native modules.
// Overlay + Ignore only: it never touches reserved, the Hyprland workspace
// never resizes. The window overlaps the rail strip so the dots stay covered
// while open. Show/hide is instant (no animation by design).
//
// Summon adjacency: widgets are hosted INSIDE this window, so KeyboardPanel /
// PopupCard anchor to it via anchorItem.QsWindow.window; the bar shim below
// overrides position/vertical to this rail's edge so anything reading
// bar.position also lands next to the rail instead of the main bar.
PanelWindow {
    id: root

    required property var screen
    required property string edge
    // Section center along the rail axis, as 0..1 fraction
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

    Component.onCompleted: console.warn("[ISLAND]", edge, "created · registry:",
        root.registry ? "ok" : "NULL", "· barApi:", root.barApi ? "ok" : "NULL")

    onEntriesChanged: console.warn("[ISLAND]", edge, "entries:", entries.length,
        entries.length ? JSON.stringify(entries.map(function(e) { return RailModel.entryId(e) })) : "[]",
        "· registry:", root.registry ? "ok" : "NULL")

    onLengthChanged: console.warn("[ISLAND]", edge, "length:", length, "· totalDepth:", totalDepth)

    // Tunables for the experiment. totalDepth INCLUDES the strip overlap:
    // rail third + protrusion == 80% of main bar thickness.
    readonly property int totalDepth: Math.max(thickness + 2, Math.round(barSize * 0.8))
    readonly property int depthOut: totalDepth - thickness
    readonly property int pad: Style.space(3)

    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property int contentLength: horizontal ? contentRow.implicitWidth : contentColumn.implicitHeight
    readonly property int length: Math.max(totalDepth, contentLength + pad * 2)
    readonly property int xOff: horizontal
        ? Math.max(0, Math.min(Math.round((screen ? screen.width : 0) - length),
                               Math.round(centerFrac * (screen ? screen.width : 0) - length / 2)))
        : 0
    readonly property int yOff: !horizontal
        ? Math.max(0, Math.min(Math.round((screen ? screen.height : 0) - length),
                               Math.round(centerFrac * (screen ? screen.height : 0) - length / 2)))
        : 0

    visible: false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-rails-island-" + edge
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    surfaceFormat.opaque: false

    implicitWidth: horizontal ? length : totalDepth
    implicitHeight: horizontal ? totalDepth : length

    anchors {
        top: edge === "top" || edge === "left" || edge === "right"
        left: edge === "top" || edge === "bottom" || edge === "left"
        bottom: edge === "bottom"
        right: edge === "right"
    }

    margins {
        left: horizontal ? xOff : 0
        top: !horizontal ? yOff : 0
        right: 0
        bottom: 0
    }

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

    // The tab body: plain background rectangle, same color as the rails, so
    // it reads as the rail itself protruding into the workspace.
    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
    }

    Row {
        id: contentRow
        visible: root.horizontal
        spacing: Style.space(2)
        anchors.centerIn: parent

        Repeater {
            model: root.entries
            delegate: RailIslandWidget {
                registry: root.registry
                barObj: railBar
                edge: root.edge
            }
            onItemAdded: function(index, item) {
                console.warn("[ISLAND] delegate added:", index, item.moduleName)
            }
            onCountChanged: console.warn("[ISLAND]", root.edge, "row repeater count:", count)
        }
    }

    Column {
        id: contentColumn
        visible: !root.horizontal
        spacing: Style.space(2)
        anchors.centerIn: parent

        Repeater {
            model: root.entries
            delegate: RailIslandWidget {
                registry: root.registry
                barObj: railBar
                edge: root.edge
            }
            onItemAdded: function(index, item) {
                console.warn("[ISLAND] delegate added:", index, item.moduleName)
            }
            onCountChanged: console.warn("[ISLAND]", root.edge, "column repeater count:", count)
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
        readonly property var clickTargets: source ? source.clickTargets : null

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