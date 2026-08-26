import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "BarModel.js" as BarModel
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

    // 3.7 universal — cross-panel rail drag coordination. The panel that
    // starts a rail widget drag publishes its edge + live cursor here; peer
    // panels compute their own island offers from it, and the source resolves
    // claims across all railPanels at release.
    property string universalDragEdge: ""
    property real universalDragX: 0
    property real universalDragY: 0
    property var railPanels: []
    function registerRailPanel(p) {
        if (!p) return
        var next = railPanels.slice()
        if (next.indexOf(p) !== -1) return
        next.push(p)
        railPanels = next
    }
    function unregisterRailPanel(p) {
        var next = railPanels.filter(function(t) { return t !== p })
        if (next.length === railPanels.length) return
        railPanels = next
    }

    // Moving the native bar to another edge swaps the rail contents at the two
    // edges. This keeps each edge's widgets attached to the space they occupy;
    // unlike the removed container gesture, this follows the native bar move.
    function swapRailConfigs(config, edgeA, edgeB) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        if (!Util.isPlainObject(config.bar.rails)) config.bar.rails = {}
        var rails = config.bar.rails
        var a = RailModel.normalizeRailLayout(rails[edgeA])
        var b = RailModel.normalizeRailLayout(rails[edgeB])
        rails[edgeA] = b
        rails[edgeB] = a
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

    // 3.7 — keep plugin bar-widgets registered while they live in rails (the
    // core's isEnabled() only scans bar.layout/plugins/bar.id, so a rail
    // placement alone reads as "disabled" and the core sweep drops them).
    // Self-triggered: onRailsConfigChanged / onCfgSerialChanged / Timer /
    // pluginRegistry signals inside the bridge — NO root handlers here (a
    // second Component.onCompleted at this level kills the whole component).
    RailPluginWidgetBridge {
        id: pluginBridge
        shell: innerBar && innerBar.shell ? innerBar.shell : null
        railsConfig: root.normalizedRails
        cfgSerial: root.barConfigSerial
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
    // The host routes shell summon/toggle commands through these methods. The
    // native Bar only knows its own ModuleSlots, so fall back to rail islands
    // when a widget has been moved out of the main bar.
    function railPanelCandidate(id) {
        var wanted = String(id || "")
        if (!wanted) return null

        var candidates = []
        for (var p = 0; p < railPanels.length; p++) {
            var panel = railPanels[p]
            if (!panel || !panel.islands) continue
            var screenName = panel.screen ? String(panel.screen.name || "") : ""
            for (var i = 0; i < panel.islands.length; i++) {
                var island = panel.islands[i]
                if (!island || !island.moduleSlots) continue
                for (var s = 0; s < island.moduleSlots.length; s++) {
                    var slot = island.moduleSlots[s]
                    var item = slot ? slot.activeItem : null
                    if (!slot || !item || slot.moduleName !== wanted) continue
                    if (typeof item.open !== "function" || typeof item.close !== "function"
                        || item.opened === undefined) continue
                    candidates.push({
                        panel: panel,
                        slot: slot,
                        screenName: screenName,
                        opened: item.opened === true
                    })
                }
            }
        }

        if (!candidates.length) return null
        var focused = innerBar && typeof innerBar.focusedScreenName === "function"
            ? innerBar.focusedScreenName() : ""
        var chosenSlot = BarModel.pickPanelSlot(candidates, focused)
        for (var c = 0; c < candidates.length; c++) {
            if (candidates[c].slot === chosenSlot) return candidates[c]
        }
        return null
    }

    function summonBarWidget(id) {
        if (innerBar && typeof innerBar.summonBarWidget === "function"
            && innerBar.summonBarWidget(id)) return true

        var candidate = railPanelCandidate(id)
        if (!candidate) return false
        candidate.panel.activeSection = candidate.slot.section
        candidate.slot.activeItem.open()
        return true
    }

    function hideBarWidget(id) {
        if (innerBar && typeof innerBar.hideBarWidget === "function"
            && innerBar.hideBarWidget(id)) return true

        var candidate = railPanelCandidate(id)
        if (!candidate) return false
        candidate.slot.activeItem.close()
        return true
    }

    function isBarWidgetOpen(id) {
        if (innerBar && typeof innerBar.isBarWidgetOpen === "function"
            && innerBar.isBarWidgetOpen(id)) return true
        var candidate = railPanelCandidate(id)
        return !!candidate && candidate.slot.activeItem.opened === true
    }
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
                // Ponytail: always visible when not main, even if empty (dots will differentiate later)
                RailPanel {
                    screen: screenDelegate.screen
                    edge: "top"
                    mainPosition: screenDelegate.mainPos
                    barSize: innerBar.barSize
                    thickness: screenDelegate.thickness
                    barHidden: innerBar.barHidden
                    hasWidgets: screenDelegate.topHasWidgets
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

            }
        }
    }
}
