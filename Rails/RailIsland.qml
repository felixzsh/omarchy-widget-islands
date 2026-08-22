import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "../RailModel.js" as RailModel

// 3.5 experiment A — RailIsland: trapezoid island growing out of the rail edge,
// revealing one section's widgets as fully interactive native modules.
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
    signal closeRequested()

    // Tunables for the experiment
    readonly property int depthOut: Math.max(thickness, Math.round(barSize * 0.8))
    readonly property int totalDepth: thickness + depthOut
    readonly property int slant: Math.min(12, Math.max(4, Math.round(thickness)))
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

    Shape {
        anchors.fill: parent
        asynchronous: false
        ShapePath {
            fillColor: root.backgroundColor
            strokeColor: "transparent"
            strokeWidth: -1
            startX: root.horizontal ? root.slant : (root.edge === "right" ? root.width : 0)
            startY: root.horizontal ? (root.edge === "bottom" ? root.height : 0) : root.slant
            PathLine {
                x: root.horizontal ? root.width - root.slant : (root.edge === "right" ? root.width : root.width)
                y: root.horizontal ? (root.edge === "bottom" ? root.height : 0) : (root.edge === "right" ? root.height - root.slant : root.slant)
            }
            PathLine {
                x: root.horizontal ? root.width : (root.edge === "right" ? 0 : root.width)
                y: root.horizontal ? (root.edge === "bottom" ? 0 : root.height) : root.height
            }
            PathLine {
                x: root.horizontal ? root.slant : 0
                y: root.horizontal ? (root.edge === "bottom" ? 0 : root.height) : (root.edge === "right" ? root.height : root.slant)
            }
        }
    }

    Row {
        id: contentRow
        visible: root.horizontal
        spacing: Style.space(2)
        anchors.centerIn: parent

        Repeater {
            model: root.entries
            delegate: islandWidgetDelegate
        }
    }

    Column {
        id: contentColumn
        visible: !root.horizontal
        spacing: Style.space(2)
        anchors.centerIn: parent

        Repeater {
            model: root.entries
            delegate: islandWidgetDelegate
        }
    }

    component IslandWidget: Item {
        required property var modelData
        readonly property string moduleName: RailModel.entryId(modelData)
        readonly property var moduleSettings: RailModel.entrySettings(modelData)
        readonly property string canonicalName: Util.canonicalWidgetId(moduleName)
        readonly property var registryComponent: {
            var w = root.registry && root.registry.widgets
            return (w && w[canonicalName]) ? w[canonicalName].component : null
        }
        implicitWidth: widgetLoader.item ? widgetLoader.item.implicitWidth : 0
        implicitHeight: widgetLoader.item ? widgetLoader.item.implicitHeight : 0

        Loader {
            id: widgetLoader
            anchors.centerIn: parent
            active: parent.registryComponent !== null
            sourceComponent: parent.registryComponent
            onLoaded: {
                if (!item) return
                if ("bar" in item) item.bar = railBar
                if ("moduleName" in item) item.moduleName = parent.moduleName
                if ("settings" in item) item.settings = parent.moduleSettings
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