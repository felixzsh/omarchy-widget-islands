import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

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
        onHoveredChanged: if (!hovered) railWindow.hoveredSection = ""
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
            }
        }
    }
}
