import QtQuick
import qs.Commons

// RailHints — 3 thirds per rail, one dot per widget centered in each third.
// Pure visual: hover state comes from RailPanel's HoverHandler via hoveredSection.
// No MouseAreas here: the rail is all background, the single drag MouseArea in
// RailPanel owns all input (mirrors the native bar's bg-drag MouseArea).
Item {
    id: root

    required property string edge
    // Layout for this edge: {left:[], center:[], right:[]}
    property var railLayout: ({ left: [], center: [], right: [] })
    property string trigger: "hover"
    // Section under the pointer, set by RailPanel's HoverHandler
    property string hoveredSection: ""
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
            readonly property bool hovered: root.hoveredSection === "left" && dotCount > 0

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
        }

        // center third
        Item {
            id: hCenter
            width: parent.width / 3
            height: parent.height
            readonly property int dotCount: root.countFor("center")
            readonly property bool hovered: root.hoveredSection === "center" && dotCount > 0

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
        }

        // right third
        Item {
            id: hRight
            width: parent.width / 3
            height: parent.height
            readonly property int dotCount: root.countFor("right")
            readonly property bool hovered: root.hoveredSection === "right" && dotCount > 0

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
            readonly property bool hovered: root.hoveredSection === "left" && dotCount > 0

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
        }

        Item {
            id: vCenter
            width: parent.width
            height: parent.height / 3
            readonly property int dotCount: root.countFor("center")
            readonly property bool hovered: root.hoveredSection === "center" && dotCount > 0

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
        }

        Item {
            id: vRight
            width: parent.width
            height: parent.height / 3
            readonly property int dotCount: root.countFor("right")
            readonly property bool hovered: root.hoveredSection === "right" && dotCount > 0

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
        }
    }
}