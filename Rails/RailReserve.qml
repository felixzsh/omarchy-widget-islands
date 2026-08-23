import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// RailReserve — invisible reserver for workspace insets.
// Ponytail: visual rails are Ignore (keep main full), this reserves per edge.
// Overlay arranges after Top, so main (Top) stays 0,0 full while reserved still counts.
PanelWindow {
    id: reserveWindow

    required property var screen
    required property string edge
    property string mainPosition: "top"
    property int thickness: 8
    property bool hasWidgets: true
    property bool barHidden: false

    readonly property bool shouldReserve: edge !== mainPosition && !barHidden

    visible: shouldReserve && !remapGuard.remapping
    exclusionMode: shouldReserve ? ExclusionMode.Auto : ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-reserve-" + edge
    WlrLayershell.layer: WlrLayer.Overlay

    color: "transparent"
    surfaceFormat.opaque: false

    // Click-through: keep the input region empty so this Overlay strip never
    // steals the rail's drag MouseArea (which lives on the Top layer below).
    mask: Region {}

    readonly property bool isHorizontal: edge === "top" || edge === "bottom"
    implicitWidth: isHorizontal ? 0 : thickness
    implicitHeight: isHorizontal ? thickness : 0

    anchors {
        top: edge === "top" || edge === "left" || edge === "right"
        bottom: edge === "bottom" || edge === "left" || edge === "right"
        left: edge === "left" || edge === "top" || edge === "bottom"
        right: edge === "right" || edge === "top" || edge === "bottom"
    }

    // Full-span, no trapped margins — reserve the whole edge strip.
    // Windows still inset correctly; visual rails (Ignore, trapped) remain continuous.
    margins.top: 0
    margins.bottom: 0
    margins.left: 0
    margins.right: 0

    ScreenMoveRemap {
        id: remapGuard
        window: reserveWindow
    }
}
