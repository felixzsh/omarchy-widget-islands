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

    ScreenMoveRemap {
        id: remapGuard
        window: railWindow
    }
}
