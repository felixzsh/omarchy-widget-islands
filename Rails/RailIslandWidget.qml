import QtQuick
import qs.Commons
import qs.Ui
import "../RailModel.js" as RailModel

// 3.5 — one hosted native widget inside a RailIsland. Mirrors Bar.qml
// ModuleSlot essentials: registry component lookup + bar/moduleName/settings
// injection on load. Exposes panelOpen + the accent marker (outer edge,
// same semantics as the main bar's open-panel indicator).
Item {
    id: slot

    required property var modelData
    required property var registry
    required property string edge
    // Duck-contract shim (position/vertical reflect the rail edge)
    required property var barObj

    readonly property string moduleName: RailModel.entryId(modelData)
    readonly property var moduleSettings: RailModel.entrySettings(modelData)
    readonly property string canonicalName: Util.canonicalWidgetId(moduleName)
    readonly property var registryComponent: {
        var w = registry && registry.widgets
        return (w && w[canonicalName]) ? w[canonicalName].component : null
    }
    // Panel widgets expose opened/open()/close()
    readonly property bool panelOpen: {
        var it = widgetLoader.item
        return !!it && it.opened === true
    }

    width: implicitWidth
    height: implicitHeight
    implicitWidth: widgetLoader.item ? widgetLoader.item.implicitWidth : 0
    implicitHeight: widgetLoader.item ? widgetLoader.item.implicitHeight : 0

    Component.onCompleted: console.warn("[ISLAND] widget:", moduleName,
        "· canonical:", canonicalName,
        "· component:", registryComponent ? "OK" : "NULL",
        "· registry:", registry ? "ok" : "NULL")

    Loader {
        id: widgetLoader
        anchors.centerIn: parent
        active: slot.registryComponent !== null
        sourceComponent: slot.registryComponent
        onLoaded: {
            if (!item) return
            if ("bar" in item) item.bar = slot.barObj
            if ("moduleName" in item) item.moduleName = slot.moduleName
            if ("settings" in item) item.settings = slot.moduleSettings
            console.warn("[ISLAND] loaded:", slot.moduleName,
                "·", item.implicitWidth + "x" + item.implicitHeight)
        }
    }

    // Open-panel mark: sits on the island's outer edge (the one facing the
    // desktop), mirroring the main bar's openPanelIndicator semantics.
    Rectangle {
        readonly property int inset: Style.space(2)
        readonly property bool horizontalRail: root.edge === "top" || root.edge === "bottom"

        visible: opacity > 0
        opacity: slot.panelOpen ? 0.9 : 0
        color: Color.accent
        radius: Math.min(width, height) / 2
        width: horizontalRail
            ? Math.max(Style.space(10), Math.round(parent.width * 0.55))
            : Style.space(2)
        height: horizontalRail
            ? Style.space(2)
            : Math.max(Style.space(10), Math.round(parent.height * 0.55))
        x: !horizontalRail
            ? (root.edge === "left" ? parent.width - width - inset : inset)
            : Math.round((parent.width - width) / 2)
        y: horizontalRail
            ? (root.edge === "top" ? parent.height - height - inset : inset)
            : Math.round((parent.height - height) / 2)
        z: 50

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }
}