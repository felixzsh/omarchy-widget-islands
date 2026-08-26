import QtQuick
import qs.Commons
import qs.Ui
import "../IslandModel.js" as IslandModel

// One hosted native widget inside an island. Mirrors Bar.qml
// ModuleSlot essentials: registry component lookup + bar/moduleName/settings
// injection on load. Exposes panelOpen + the accent marker (outer edge,
// same semantics as the main bar's open-panel indicator).
//
// Also mirrors ModuleSlot's modulePointer: an overlay MouseArea that forwards
// clicks to the widget's triggerPress() and starts an island widget
// drag once the pointer moves past the threshold with the button held.
Item {
    id: slot

    required property var modelData
    required property var registry
    required property string edge
    // Duck-contract shim (position/vertical reflect the island edge)
    required property var barObj
    // Owning island + IslandPanel drag API
    required property var host
    required property var dragHost
    required property string section

    readonly property string moduleName: IslandModel.entryId(modelData)
    readonly property var moduleSettings: IslandModel.entrySettings(modelData)
    readonly property string canonicalName: Util.canonicalWidgetId(moduleName)
    readonly property var registryComponent: {
        var w = registry && registry.widgets
        return (w && w[canonicalName]) ? w[canonicalName].component : null
    }
    // Panel widgets expose opened/open()/close()
    readonly property bool panelOpen: {
        var it = widgetLoader.item
        // Both official open-panel contracts, mirroring the main bar's
        // ModuleSlot.panelOpen (activePopout === slot.activeItem):
        //  - Ui.Panel-derived widgets expose `opened`
        //  - BarWidget-based widgets with a self-contained KeyboardPanel /
        //    PopupCard call bar.requestPopout(owner) → bar.activePopout
        //    points at the widget root while open.
        return !!it && (it.opened === true
            || (barObj !== null && barObj.activePopout === it))
    }
    readonly property alias activeItem: widgetLoader.item
    // This slot is being dragged (dimmed + outlined, like ModuleSlot)
    readonly property bool isDragSource: dragHost !== null && dragHost.islandDragSourceSlot === slot

    width: implicitWidth
    height: implicitHeight
    implicitWidth: widgetLoader.item ? widgetLoader.item.implicitWidth : 0
    implicitHeight: widgetLoader.item ? widgetLoader.item.implicitHeight : 0

    Component.onCompleted: {
        console.warn("[ISLAND] widget:", moduleName,
            "· canonical:", canonicalName,
            "· component:", registryComponent ? "OK" : "NULL",
            "· registry:", registry ? "ok" : "NULL")
        if (host) host.registerModuleSlot(slot)
    }
    Component.onDestruction: {
        if (host) host.unregisterModuleSlot(slot)
        if (isDragSource && dragHost) dragHost.clearIslandDrag()
    }

    Loader {
        id: widgetLoader
        anchors.centerIn: parent
        active: slot.registryComponent !== null
        sourceComponent: slot.registryComponent
        opacity: slot.isDragSource ? 0.22 : 1.0
        onLoaded: {
            if (!item) return
            if ("bar" in item) item.bar = slot.barObj
            if ("moduleName" in item) item.moduleName = slot.moduleName
            if ("settings" in item) item.settings = slot.moduleSettings
            console.warn("[ISLAND] loaded:", slot.moduleName,
                "·", item.implicitWidth + "x" + item.implicitHeight)
        }
    }

    // Drag-source outline (mirrors ModuleSlot's drag ghost-of-current-place)
    BorderSurface {
        visible: slot.isDragSource
        anchors.fill: parent
        anchors.margins: Style.space(1)
        color: "transparent"
        borderSpec: Border.flat(slot.barObj.foreground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: 0.32
        z: 40
    }

    // Open-panel mark: sits on the island's outer edge (the one facing the
    // desktop), mirroring the main bar's openPanelIndicator semantics.
    Rectangle {
        readonly property int inset: Style.space(2)
        readonly property bool horizontalIsland: slot.edge === "top" || slot.edge === "bottom"

        visible: opacity > 0
        opacity: slot.panelOpen && !slot.isDragSource ? 0.9 : 0
        color: Color.accent
        radius: Math.min(width, height) / 2
        width: horizontalIsland
            ? Math.max(Style.space(10), Math.round(parent.width * 0.55))
            : Style.space(2)
        height: horizontalIsland
            ? Style.space(2)
            : Math.max(Style.space(10), Math.round(parent.height * 0.55))
        x: !horizontalIsland
            ? (slot.edge === "left" ? parent.width - width - inset : inset)
            : Math.round((parent.width - width) / 2)
        y: horizontalIsland
            ? (slot.edge === "top" ? parent.height - height - inset : inset)
            : Math.round((parent.height - height) / 2)
        z: 50

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    // Clicks + drag initiation, mirroring Bar.qml's modulePointer. The overlay
    // consumes presses; plain clicks are forwarded to triggerPress() so panels
    // open exactly as before, and hold+move hands off to the IslandPanel drag.
    MouseArea {
        id: modulePointer

        property bool dragging: false
        property bool suppressClick: false
        property real pressedX: 0
        property real pressedY: 0
        readonly property bool canReorder: slot.dragHost !== null && slot.dragHost.canMutateIsland
        readonly property real dragThreshold: Style.space(4)

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true
        cursorShape: Qt.PointingHandCursor

        onPressed: function(mouse) {
            dragging = false
            suppressClick = false
            pressedX = mouse.x
            pressedY = mouse.y
            if (slot.dragHost) slot.dragHost.clearIslandDrag()
        }

        onPositionChanged: function(mouse) {
            if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

            var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
            if (distance >= dragThreshold) {
                if (!dragging && slot.dragHost)
                    slot.dragHost.beginIslandDrag(slot, pressedX, pressedY)
                dragging = true
            }

            if (dragging && slot.dragHost) {
                var scenePoint = mapToItem(null, mouse.x, mouse.y)
                slot.dragHost.updateIslandDrag(slot, scenePoint)
            }
        }

        onReleased: function(mouse) {
            var wasDragging = dragging
            if (wasDragging) suppressClick = true
            dragging = false

            if (wasDragging && slot.dragHost) {
                slot.dragHost.finishIslandDrag()
                mouse.accepted = true
            } else if (!wasDragging) {
                mouse.accepted = false
            }
        }

        onCanceled: {
            dragging = false
            suppressClick = false
            if (slot.dragHost) slot.dragHost.clearIslandDrag()
        }

        onClicked: function(mouse) {
            if (suppressClick) {
                suppressClick = false
                mouse.accepted = true
                return
            }

            var it = widgetLoader.item
            if (it && typeof it.triggerPress === "function") it.triggerPress(mouse.button)
            else mouse.accepted = false
        }
    }
}
