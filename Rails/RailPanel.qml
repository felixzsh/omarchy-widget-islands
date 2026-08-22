import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
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
            if (sec !== "" && sec !== railWindow.activeSection
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
            if (!railHover.hovered && !island.pointerInside && !island.pinnedByPanel)
                railWindow.activeSection = ""
        }
    }

    RailIsland {
        id: island
        screen: railWindow.screen
        edge: railWindow.edge
        centerFrac: {
            var idx = ["left", "center", "right"].indexOf(railWindow.activeSection)
            return idx < 0 ? 0.5 : (idx + 0.5) / 3
        }
        spanStart: railWindow.spanStart
        spanLen: railWindow.spanLen
        entries: railWindow.activeSection !== "" && railWindow.railLayout
            ? (railWindow.railLayout[railWindow.activeSection] || [])
            : []
        registry: railWindow.widgetRegistry
        barApi: railWindow.barApi
        thickness: railWindow.thickness
        barSize: railWindow.barSize
        backgroundColor: railWindow.backgroundColor
        foregroundColor: railWindow.foregroundColor
        transparent: railWindow.transparent
        fontFamily: railWindow.fontFamily
        clickMode: railWindow.trigger === "click"
        visible: railWindow.shouldShow && !remapGuard.remapping
            && railWindow.activeSection !== "" && entries.length > 0
        onCloseRequested: railWindow.activeSection = ""
        onPointerInsideChanged: {
            if (pointerInside) hoverCloseTimer.stop()
            else if (railWindow.trigger === "hover" && !railHover.hovered && !pinnedByPanel)
                hoverCloseTimer.restart()
        }
        onPinnedByPanelChanged: {
            // Panel closed → resume normal dismissal only if pointer is gone
            if (!pinnedByPanel && railWindow.trigger === "hover"
                && !railHover.hovered && !pointerInside)
                hoverCloseTimer.restart()
            if (pinnedByPanel) hoverCloseTimer.stop()
        }
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
