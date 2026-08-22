import QtQuick
import qs.Commons

// RailHints — 3 thirds per rail, one dot per widget centered in each third.
// Hitbox = whole third (MouseArea fill), dots centered, highlight on hover.
// Ponytail: no abstractions, just Row/Column + Repeater per spec.
Item {
    id: root

    required property string edge
    // Layout for this edge: {left:[], center:[], right:[]}
    property var railLayout: ({ left: [], center: [], right: [] })
    property string trigger: "hover"
    // Dot color — defaults to bar text, matches bar foreground on background.
    property color dotColor: Color.bar.text

    // Derived
    readonly property bool isHorizontal: edge === "top" || edge === "bottom"

    // Helper to get count per section
    function countFor(section) {
        if (!railLayout || !railLayout[section] || !Array.isArray(railLayout[section])) return 0
        return railLayout[section].length
    }

    // Horizontal rails (top/bottom): 3 columns side-by-side, dots in Row
    Row {
        id: horizontalThirds
        visible: root.isHorizontal
        anchors.fill: parent

        // left third
        Item {
            id: hLeft
            width: parent.width / 3
            height: parent.height
            readonly property int dotCount: root.countFor("left")
            readonly property bool hovered: hLeftMa.containsMouse && dotCount > 0

            Row {
                anchors.centerIn: parent
                spacing: 2
                visible: hLeft.dotCount > 0
                Repeater {
                    model: hLeft.dotCount
                    Rectangle {
                        width: 2; height: 2; radius: 1
                        color: root.dotColor
                        opacity: hLeft.hovered ? 0.6 : 0.35
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
            }

            MouseArea {
                id: hLeftMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: hLeft.dotCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                // 3.5 will use hover/click to open panel; 3.3 only highlights.
                // Keep hover detection here so future logic can rely on containsMouse.
            }
        }

        // center third
        Item {
            id: hCenter
            width: parent.width / 3
            height: parent.height
            readonly property int dotCount: root.countFor("center")
            readonly property bool hovered: hCenterMa.containsMouse && dotCount > 0

            Row {
                anchors.centerIn: parent
                spacing: 2
                visible: hCenter.dotCount > 0
                Repeater {
                    model: hCenter.dotCount
                    Rectangle {
                        width: 2; height: 2; radius: 1
                        color: root.dotColor
                        opacity: hCenter.hovered ? 0.6 : 0.35
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
            }

            MouseArea {
                id: hCenterMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: hCenter.dotCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }

        // right third
        Item {
            id: hRight
            width: parent.width / 3
            height: parent.height
            readonly property int dotCount: root.countFor("right")
            readonly property bool hovered: hRightMa.containsMouse && dotCount > 0

            Row {
                anchors.centerIn: parent
                spacing: 2
                visible: hRight.dotCount > 0
                Repeater {
                    model: hRight.dotCount
                    Rectangle {
                        width: 2; height: 2; radius: 1
                        color: root.dotColor
                        opacity: hRight.hovered ? 0.6 : 0.35
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
            }

            MouseArea {
                id: hRightMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: hRight.dotCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }
    }

    // Vertical rails (left/right): 3 rows stacked, dots in Column
    Column {
        id: verticalThirds
        visible: !root.isHorizontal
        anchors.fill: parent

        Item {
            id: vLeft
            width: parent.width
            height: parent.height / 3
            readonly property int dotCount: root.countFor("left")
            readonly property bool hovered: vLeftMa.containsMouse && dotCount > 0

            Column {
                anchors.centerIn: parent
                spacing: 2
                visible: vLeft.dotCount > 0
                Repeater {
                    model: vLeft.dotCount
                    Rectangle {
                        width: 2; height: 2; radius: 1
                        color: root.dotColor
                        opacity: vLeft.hovered ? 0.6 : 0.35
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
            }

            MouseArea {
                id: vLeftMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: vLeft.dotCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }

        Item {
            id: vCenter
            width: parent.width
            height: parent.height / 3
            readonly property int dotCount: root.countFor("center")
            readonly property bool hovered: vCenterMa.containsMouse && dotCount > 0

            Column {
                anchors.centerIn: parent
                spacing: 2
                visible: vCenter.dotCount > 0
                Repeater {
                    model: vCenter.dotCount
                    Rectangle {
                        width: 2; height: 2; radius: 1
                        color: root.dotColor
                        opacity: vCenter.hovered ? 0.6 : 0.35
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
            }

            MouseArea {
                id: vCenterMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: vCenter.dotCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }

        Item {
            id: vRight
            width: parent.width
            height: parent.height / 3
            readonly property int dotCount: root.countFor("right")
            readonly property bool hovered: vRightMa.containsMouse && dotCount > 0

            Column {
                anchors.centerIn: parent
                spacing: 2
                visible: vRight.dotCount > 0
                Repeater {
                    model: vRight.dotCount
                    Rectangle {
                        width: 2; height: 2; radius: 1
                        color: root.dotColor
                        opacity: vRight.hovered ? 0.6 : 0.35
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                }
            }

            MouseArea {
                id: vRightMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: vRight.dotCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }
    }
}
