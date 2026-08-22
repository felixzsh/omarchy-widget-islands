import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "RailModel.js" as RailModel
import "Rails"

Item {
    id: root

    // Host-injected props (plain, not required — wrapper satisfies Bar's required at creation)
    property string omarchyPath: ""
    property var barWidgetRegistry: null
    property var barConfig: fallbackBarConfig
    property var shell: null
    property var manifest: null

    // Fallback when host hasn't yet provided barConfig (jm)
    property var fallbackBarConfig: ({
        position: "top",
        transparent: false,
        centerAnchor: "omarchy.clock",
        layout: { left: [], center: [], right: [] },
        rails: {
            enabled: false,
            trigger: "hover",
            top: { left: [], center: [], right: [] },
            bottom: { left: [], center: [], right: [] },
            left: { left: [], center: [], right: [] },
            right: { left: [], center: [], right: [] }
        }
    })

    // Rails state — parsed from bar.rails
    property bool railsEnabled: false
    property string railsTrigger: "hover"
    property var normalizedRails: ({
        enabled: false,
        trigger: "hover",
        rails: {
            top: { left: [], center: [], right: [] },
            bottom: { left: [], center: [], right: [] },
            left: { left: [], center: [], right: [] },
            right: { left: [], center: [], right: [] }
        }
    })
    property int barConfigSerial: 0

    property bool containerMoveActive: false
    property string containerMoveSource: ""
    property string containerMoveCandidate: ""
    property var containerMoveWindow: null
    property var containerMoveScreen: null

    function beginContainerMove(edge, win) {
        containerMoveWindow = win
        containerMoveScreen = win && win.screen ? win.screen : null
        containerMoveSource = edge
        containerMoveCandidate = edge
        containerMoveActive = true
    }
    function updateContainerMove(screenPoint) {
        if (!containerMoveActive || !containerMoveScreen) return
        containerMoveCandidate = RailModel.nearestScreenEdge(screenPoint, containerMoveScreen)
    }
    function clearContainerMove() {
        containerMoveActive = false
        containerMoveCandidate = ""
        containerMoveWindow = null
        containerMoveScreen = null
        containerMoveSource = ""
    }

    function swapRailConfigs(config, edgeA, edgeB) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        if (!Util.isPlainObject(config.bar.rails)) config.bar.rails = {}
        var rails = config.bar.rails
        var a = RailModel.normalizeRailLayout(rails[edgeA])
        var b = RailModel.normalizeRailLayout(rails[edgeB])
        rails[edgeA] = b
        rails[edgeB] = a
    }

    function finishContainerMove() {
        var src = containerMoveSource
        var cand = containerMoveCandidate
        var active = containerMoveActive
        clearContainerMove()
        if (!active || !src || !cand || src === cand) return
        if (!shell || typeof shell.mutateShellConfig !== "function") return

        var mainPos = RailModel.normalizePosition(position)
        if (src === mainPos) {
            shell.mutateShellConfig(function(config) { root.swapRailConfigs(config, mainPos, cand) })
            if (innerBar && typeof innerBar.setBarPosition === "function") innerBar.setBarPosition(cand)
        } else if (cand === mainPos) {
            shell.mutateShellConfig(function(config) { root.swapRailConfigs(config, src, mainPos) })
            if (innerBar && typeof innerBar.setBarPosition === "function") innerBar.setBarPosition(src)
        } else {
            shell.mutateShellConfig(function(config) { root.swapRailConfigs(config, src, cand) })
        }
    }

    property string _barDragFrom: ""
    Connections {
        target: innerBar
        function onBarMoveActiveChanged() {
            if (innerBar.barMoveActive) {
                root._barDragFrom = innerBar.position
                return
            }
            var from = root._barDragFrom
            root._barDragFrom = ""
            if (!from) return
            var to = RailModel.normalizePosition(innerBar.barMoveCandidate || innerBar.position)
            if (to !== from && root.shell && typeof root.shell.mutateShellConfig === "function") {
                root.shell.mutateShellConfig(function(config) { root.swapRailConfigs(config, from, to) })
            }
        }
    }

    // Duck contract for shell.bar — aliases to innerBar (main)
    readonly property alias barHidden: innerBar.barHidden
    readonly property alias barSize: innerBar.barSize
    readonly property alias position: innerBar.position
    readonly property alias vertical: innerBar.vertical
    readonly property alias foreground: innerBar.foreground
    readonly property alias background: innerBar.background
    readonly property alias fontFamily: innerBar.fontFamily

    // Forwarded methods (guard typeof)
    function run(command) { if (innerBar && typeof innerBar.run === "function") return innerBar.run(command) }
    function showTooltip(target, text) { if (innerBar && typeof innerBar.showTooltip === "function") return innerBar.showTooltip(target, text) }
    function hideTooltip(target) { if (innerBar && typeof innerBar.hideTooltip === "function") return innerBar.hideTooltip(target) }
    function requestPopout(owner) { if (innerBar && typeof innerBar.requestPopout === "function") return innerBar.requestPopout(owner) }
    function releasePopout(owner) { if (innerBar && typeof innerBar.releasePopout === "function") return innerBar.releasePopout(owner) }
    function summonBarWidget(id) { if (innerBar && typeof innerBar.summonBarWidget === "function") return innerBar.summonBarWidget(id); return false }
    function hideBarWidget(id) { if (innerBar && typeof innerBar.hideBarWidget === "function") return innerBar.hideBarWidget(id); return false }
    function isBarWidgetOpen(id) { if (innerBar && typeof innerBar.isBarWidgetOpen === "function") return innerBar.isBarWidgetOpen(id); return false }
    function toggleTransparency() { if (innerBar && typeof innerBar.toggleTransparency === "function") return innerBar.toggleTransparency() }
    function debugBarGeometry() { if (innerBar && typeof innerBar.debugBarGeometry === "function") return innerBar.debugBarGeometry(); return [] }
    function panelWidgetIdAt(region, index) { if (innerBar && typeof innerBar.panelWidgetIdAt === "function") return innerBar.panelWidgetIdAt(region, index); return "" }

    // Known issue: rapid bar.position switches can flicker through "top"
    // when shell.json is read mid atomic write — FileView sees an empty file
    // and shell/shell.qml:72 falls back to defaults for one frame. For the
    // rails plugin this is visible as a gap/detach when flipping left↔right
    // quickly (see: https://github.com/basecamp/omarchy/pull/7723).
    function applyBarConfig() {
        var config = Util.isPlainObject(root.barConfig) ? root.barConfig : root.fallbackBarConfig
        var railsRaw = config.rails
        var pos = config.position
        var parsed = RailModel.normalizeRailsConfig(railsRaw, pos)
        railsEnabled = parsed.enabled
        railsTrigger = parsed.trigger
        normalizedRails = parsed
        barConfigSerial++
    }

    onBarConfigChanged: applyBarConfig()
    Component.onCompleted: applyBarConfig()

    // Main bar — must be first so Hyprland arranges main before rails (invite)
    Bar {
        id: innerBar
        omarchyPath: root.omarchyPath
        barWidgetRegistry: root.barWidgetRegistry
        barConfig: root.barConfig
        shell: root.shell
        manifest: root.manifest
    }

    // Rails — 3 per monitor (edge !== position), trapped between main and parallel
    // React to barConfigSerial + innerBar.position for correct filtering
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Item {
                id: screenDelegate
                required property var modelData
                readonly property var screen: modelData

                // Compute thickness once per screen-delegate (reacts to barSize changes)
                readonly property int thickness: RailModel.railThickness(innerBar.barSize)
                readonly property string mainPos: innerBar.position
                readonly property int cfgSerial: root.barConfigSerial
                // Keep cfgSerial dependency for hasWidgets
                readonly property var _topLayout: (cfgSerial, root.normalizedRails && root.normalizedRails.rails ? root.normalizedRails.rails["top"] : null)
                readonly property var _bottomLayout: (cfgSerial, root.normalizedRails && root.normalizedRails.rails ? root.normalizedRails.rails["bottom"] : null)
                readonly property var _leftLayout: (cfgSerial, root.normalizedRails && root.normalizedRails.rails ? root.normalizedRails.rails["left"] : null)
                readonly property var _rightLayout: (cfgSerial, root.normalizedRails && root.normalizedRails.rails ? root.normalizedRails.rails["right"] : null)
                readonly property bool topHasWidgets: _topLayout ? RailModel.hasAnyWidgets(_topLayout) : false
                readonly property bool bottomHasWidgets: _bottomLayout ? RailModel.hasAnyWidgets(_bottomLayout) : false
                readonly property bool leftHasWidgets: _leftLayout ? RailModel.hasAnyWidgets(_leftLayout) : false
                readonly property bool rightHasWidgets: _rightLayout ? RailModel.hasAnyWidgets(_rightLayout) : false

                // Visual frame — Top Ignore, trapped only laterals, parallel full-span
                // Ponytail: visible whenever railsEnabled && not main, even if empty (dots will differentiate later)
                RailPanel {
                    screen: screenDelegate.screen
                    edge: "top"
                    mainPosition: screenDelegate.mainPos
                    barSize: innerBar.barSize
                    thickness: screenDelegate.thickness
                    barHidden: innerBar.barHidden
                    hasWidgets: screenDelegate.topHasWidgets
                    railsEnabled: root.railsEnabled
                    backgroundColor: innerBar.background
                    transparent: innerBar.transparent
                    railLayout: screenDelegate._topLayout ? screenDelegate._topLayout : ({ left: [], center: [], right: [] })
                    trigger: root.railsTrigger
                    foregroundColor: innerBar.foreground
                    moveHost: root
                    barApi: innerBar
                    widgetRegistry: root.barWidgetRegistry
                    fontFamily: innerBar.fontFamily
                }

                RailPanel {
                    screen: screenDelegate.screen
                    edge: "bottom"
                    mainPosition: screenDelegate.mainPos
                    barSize: innerBar.barSize
                    thickness: screenDelegate.thickness
                    barHidden: innerBar.barHidden
                    hasWidgets: screenDelegate.bottomHasWidgets
                    railsEnabled: root.railsEnabled
                    backgroundColor: innerBar.background
                    transparent: innerBar.transparent
                    railLayout: screenDelegate._bottomLayout ? screenDelegate._bottomLayout : ({ left: [], center: [], right: [] })
                    trigger: root.railsTrigger
                    foregroundColor: innerBar.foreground
                    moveHost: root
                    barApi: innerBar
                    widgetRegistry: root.barWidgetRegistry
                    fontFamily: innerBar.fontFamily
                }

                RailPanel {
                    screen: screenDelegate.screen
                    edge: "left"
                    mainPosition: screenDelegate.mainPos
                    barSize: innerBar.barSize
                    thickness: screenDelegate.thickness
                    barHidden: innerBar.barHidden
                    hasWidgets: screenDelegate.leftHasWidgets
                    railsEnabled: root.railsEnabled
                    backgroundColor: innerBar.background
                    transparent: innerBar.transparent
                    railLayout: screenDelegate._leftLayout ? screenDelegate._leftLayout : ({ left: [], center: [], right: [] })
                    trigger: root.railsTrigger
                    foregroundColor: innerBar.foreground
                    moveHost: root
                    barApi: innerBar
                    widgetRegistry: root.barWidgetRegistry
                    fontFamily: innerBar.fontFamily
                }

                RailPanel {
                    screen: screenDelegate.screen
                    edge: "right"
                    mainPosition: screenDelegate.mainPos
                    barSize: innerBar.barSize
                    thickness: screenDelegate.thickness
                    barHidden: innerBar.barHidden
                    hasWidgets: screenDelegate.rightHasWidgets
                    railsEnabled: root.railsEnabled
                    backgroundColor: innerBar.background
                    transparent: innerBar.transparent
                    railLayout: screenDelegate._rightLayout ? screenDelegate._rightLayout : ({ left: [], center: [], right: [] })
                    trigger: root.railsTrigger
                    foregroundColor: innerBar.foreground
                    moveHost: root
                    barApi: innerBar
                    widgetRegistry: root.barWidgetRegistry
                    fontFamily: innerBar.fontFamily
                }

                // Invisible reservers — Overlay Auto, full-span, keep main 0,0 full while resizing workspace
                RailReserve {
                    screen: screenDelegate.screen
                    edge: "top"
                    mainPosition: screenDelegate.mainPos
                    thickness: screenDelegate.thickness
                    hasWidgets: screenDelegate.topHasWidgets
                    railsEnabled: root.railsEnabled
                    barHidden: innerBar.barHidden
                }

                RailReserve {
                    screen: screenDelegate.screen
                    edge: "bottom"
                    mainPosition: screenDelegate.mainPos
                    thickness: screenDelegate.thickness
                    hasWidgets: screenDelegate.bottomHasWidgets
                    railsEnabled: root.railsEnabled
                    barHidden: innerBar.barHidden
                }

                RailReserve {
                    screen: screenDelegate.screen
                    edge: "left"
                    mainPosition: screenDelegate.mainPos
                    thickness: screenDelegate.thickness
                    hasWidgets: screenDelegate.leftHasWidgets
                    railsEnabled: root.railsEnabled
                    barHidden: innerBar.barHidden
                }

                RailReserve {
                    screen: screenDelegate.screen
                    edge: "right"
                    mainPosition: screenDelegate.mainPos
                    thickness: screenDelegate.thickness
                    hasWidgets: screenDelegate.rightHasWidgets
                    railsEnabled: root.railsEnabled
                    barHidden: innerBar.barHidden
                }
            }
        }
    }

    component RailMoveGhostPanel: PanelWindow {
        id: ghostWindow
        required property var ghostScreen
        readonly property bool screenMatches: root.containerMoveScreen === ghostScreen ||
            (root.containerMoveScreen && ghostScreen && root.containerMoveScreen.name && ghostScreen.name && root.containerMoveScreen.name === ghostScreen.name)
        visible: root.containerMoveActive && screenMatches
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-rails-move-ghost"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {}

        Repeater {
            model: ["top", "bottom", "left", "right"]

            BorderSurface {
                required property string modelData
                readonly property bool edgeVertical: modelData === "left" || modelData === "right"
                readonly property int edgeSize: RailModel.railThickness(innerBar.barSize)

                x: modelData === "right" ? parent.width - edgeSize : 0
                y: modelData === "bottom" ? parent.height - edgeSize : 0
                width: edgeVertical ? edgeSize : parent.width
                height: edgeVertical ? parent.height : edgeSize
                color: innerBar.transparent ? "transparent" : innerBar.background
                borderSpec: Border.flat(innerBar.foreground, 1)
                visible: opacity > 0
                opacity: root.containerMoveCandidate === modelData ? (innerBar.transparent ? 0.45 : 0.7) : 0

                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: Component {
            RailMoveGhostPanel { required property var modelData; ghostScreen: modelData }
        }
    }
}
