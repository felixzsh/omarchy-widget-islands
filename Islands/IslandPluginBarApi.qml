import QtQuick
import qs.Ui

// Restricted, edge-aware bar surface for a THIRD-PARTY widget hosted in an
// island. Mirrors shell/plugins/bar/Bar.qml's pluginBarApiFor(), with two
// deliberate differences:
//
//   - position/vertical reflect THIS island's edge, not the main bar's, so
//     panels summoned from the island still land next to it.
//   - one facade per widget. Bar.qml caches facades by plugin id and prunes
//     them against the main bar's moduleSlots; island slots live in the
//     island's own moduleSlots, so a cached facade would be destroyed while
//     a widget still holds it.
//
// First-party widgets never use this: they keep the trusted IslandBarShim,
// matching Bar.qml handing `root` to built-ins. Only third-party widgets are
// downgraded to the service-less entry facade the host documents.
PluginBarApi {
    id: api

    // Real inner bar: capability source + scoped callbacks.
    required property var source
    // Island presentation shim (edge-aware colors/size).
    required property var islandBar
    // Owner identity used to scope the host callbacks.
    property string ownerId: ""
    property string edge: "top"
    // When false the host facade is not requested (first-party / unused).
    property bool restricted: true

    foreground: islandBar ? islandBar.foreground : "transparent"
    background: islandBar ? islandBar.background : "transparent"
    barForeground: source ? source.barForeground : foreground
    fontFamily: islandBar ? islandBar.fontFamily : ""
    barSize: islandBar ? islandBar.barSize : 0
    urgent: source ? source.urgent : "transparent"
    transparent: source ? source.transparent : false
    foregroundAnimationEnabled:
        source ? source.foregroundAnimationEnabled : true
    centerSectionRevealHeld: source ? source.centerSectionRevealHeld : false
    _centerHoverRevealSuppressed:
        source ? source.centerHoverRevealSuppressed : false

    position: edge
    vertical: edge === "left" || edge === "right"

    shell: restricted && source && source.shell
        && typeof source.shell.pluginShellForBarEntry === "function"
        ? source.shell.pluginShellForBarEntry(ownerId, moduleName)
        : null

    _showTooltip: function(target, text) {
        if (source) source.showTooltip(target, text)
    }
    _hideTooltip: function(target) {
        if (source) source.hideTooltip(target)
    }
    _registerClickTarget: function(target) {
        if (!target) return
        if (islandBar) islandBar.registerClickTarget(target)
        if (source) source.registerPluginClickTarget(ownerId, target)
    }
    _unregisterClickTarget: function(target) {
        if (islandBar) islandBar.unregisterClickTarget(target)
        if (source) source.unregisterPluginClickTarget(ownerId, target)
    }
    _requestPopout: function(owner) {
        if (source) source.requestPluginPopout(ownerId, owner)
    }
    _releasePopout: function(owner) {
        if (source) source.releasePluginPopout(ownerId, owner)
    }
    _switchPanelFrom: function(owner, direction) {
        return source ? source.switchPanelFrom(owner, direction) : false
    }
    _targetBelongsToWindow: function(target, window) {
        return source ? source.targetBelongsToWindow(target, window) : false
    }
    _moduleWidgets: function(requestedId) {
        return String(requestedId || "") === String(moduleName || "") && source
            ? source.moduleWidgets(moduleName) : []
    }
    _run: function(command) {
        if (source) source.run(command)
    }
    _setCenterHoverRevealSuppressed: function(value) {
        if (source) source.setCenterHoverRevealSuppressed(!!value)
    }

    // Scoped mirrors of the bar-owned objects. Re-read on the same signals
    // Bar.qml watches, since the getters are function calls (no auto-binding).
    // The root here is a plain QtObject with no default property, so the
    // Connections live in IslandWidget (which owns this facade).
    function refresh() {
        activePopout = source && source.pluginOwnsBarObject(ownerId, source.activePopout)
            ? source.activePopout : foreignPopoutMarker
        clickTargets = source ? source.pluginClickTargets(ownerId) : []
        layoutConfig = source && typeof source.publicLayoutConfig === "function"
            ? source.publicLayoutConfig() : ({})
    }

    Component.onCompleted: refresh()
}
