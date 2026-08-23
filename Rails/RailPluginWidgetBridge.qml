import QtQuick
import "../RailModel.js" as RailModel

// 3.7 — registration bridge for plugin bar-widgets hosted in rails.
//
// The shell core keeps a plugin's bar-widget registered only while its id is
// reachable from config.bar.layout / config.plugins / bar.id — that is the
// whole body of PluginRegistry.isEnabled(). A widget dragged into a rail
// leaves bar.layout, isEnabled() flips false, and syncPluginWidgets' sweep
// unregisters it: islands keep counting dots but resolve component NULL.
// Natives survive via __isFirstParty; third-party plugins need this bridge.
//
// We mirror shell.qml's loadPluginWidget cycle for rail-referenced plugin ids
// the core does not currently hold: async createComponent + register with the
// same metadata shape. Safe against the core's sweep because it only drops
// keys present in its internal pluginWidgetComponents map — ours are foreign.
// When the same id later returns to the native bar, the core re-registers over
// our key with an equivalent component (no gap, last write wins).
Item {
    id: bridge

    // Shell root — needs .barWidgetRegistry and .pluginRegistry
    required property var shell
    // normalizedRails ({rails:{edge:{section:[entries]}}}) or the rails map itself
    required property var railsConfig
    // Bump externally to force a resync after config mutations
    property int cfgSerial: 0

    // registryKey -> { url: string, component: Component|null }
    property var owned: ({})

    onRailsConfigChanged: sync()
    onCfgSerialChanged: sync()

    // Safety net: core sweeps ride scan events whose ordering vs our triggers
    // is undefined; a cheap periodic re-add closes any gap. No-op when idle.
    Timer {
        interval: 4000
        running: bridge.shell !== null
        repeat: true
        onTriggered: bridge.sync()
    }

    Connections {
        target: bridge.shell ? bridge.shell.pluginRegistry : null
        function onPluginsChanged() { bridge.sync() }
        function onScanFinished() { bridge.sync() }
    }

    function railIds() {
        var rails = railsConfig && railsConfig.rails ? railsConfig.rails : railsConfig
        return RailModel.railReferencedIds(rails)
    }

    function setOwned(key, entry) {
        var next = {}
        for (var k in owned) if (k !== key) next[k] = owned[k]
        if (entry) next[key] = entry
        owned = next
    }

    function buildMeta(manifest) {
        var bw = manifest && manifest.barWidget ? manifest.barWidget : {}
        return {
            displayName: bw.displayName || manifest.name,
            description: bw.description || manifest.description,
            category: bw.category || "Plugin",
            allowMultiple: bw.allowMultiple === true,
            defaults: bw.defaults || {},
            settingsForm: bw.settingsForm || "",
            schema: bw.schema || [],
            pluginId: manifest.id,
            sourceDir: manifest.__sourceDir || "",
            source: "plugin"
        }
    }

    function sync() {
        var reg = shell ? shell.barWidgetRegistry : null
        var plugins = shell && shell.pluginRegistry ? shell.pluginRegistry.installedPlugins : null
        if (!reg || !plugins) return

        var wanted = railIds()

        // Release ours whose ids left the rails entirely.
        var nextOwned = {}
        for (var key in owned) {
            if (wanted.indexOf(key) !== -1) { nextOwned[key] = owned[key]; continue }
            if (owned[key] && owned[key].component) reg.unregister(key)
        }
        owned = nextOwned

        for (var i = 0; i < wanted.length; i++) loadIfNeeded(wanted[i], reg, plugins)

        // Services (dynamic data: live counters, trackers, daemons-with-state).
        // The host only starts a plugin's service while isEnabled() says so,
        // and its placement scan doesn't know about rails — rail-hosted
        // widgets would render but feed on a service that never exists.
        // ensureService() is public and ungated; idempotent, so calling it
        // every sync (signals + 4s timer) keeps the service alive across the
        // core's sweeps. These services persist state to disk by design, so
        // even a destroy/recreate cycle loses nothing.
        //
        // UPSTREAM-PR(omarchy-core): teach PluginRegistry.findEntryLocation
        // about config.bar.rails[edge][section] (mirror findBarLocation with
        // barEntryId) and add the same pass to shell.updateEntryInline before
        // its plugins[] fallback — then this loop becomes redundant.
        for (var w = 0; w < wanted.length; w++) ensureServiceIfNeeded(wanted[w], plugins)
    }

    function ensureServiceIfNeeded(id, plugins) {
        if (!shell || typeof shell.ensureService !== "function") return
        var manifest = plugins[id]
        if (!manifest || !manifest.kinds || manifest.kinds.indexOf("service") === -1) return
        var had = !!shell.serviceFor(id)
        shell.ensureService(id)
        if (!had && shell.serviceFor(id))
            console.warn("[RAIL] plugin-service bridge started:", id)
    }

    function loadIfNeeded(id, reg, plugins) {
        if (reg.has(id)) return  // core owns it (bar/plugins placement or prior pass)
        var manifest = plugins[id]
        if (!manifest || !manifest.kinds || manifest.kinds.indexOf("bar-widget") === -1) return

        var url = shell.pluginRegistry.entryPointUrl(manifest, "barWidget")
        if (!url) return
        var existing = owned[id]
        // In-flight claim for this URL: let the pending load finish.
        if (existing && existing.url === url && !existing.component) return

        console.warn("[RAIL] plugin-widget bridge register:", id)
        setOwned(id, { url: url, component: null })
        var meta = buildMeta(manifest)
        var comp = Qt.createComponent(url, Component.Asynchronous)

        var finalize = function(status) {
            if (status === Component.Ready) {
                reg.register(id, comp, meta)
                setOwned(id, { url: url, component: comp })
            } else if (status === Component.Error) {
                console.warn("[RAIL] plugin-widget load failed:", id, comp.errorString())
                setOwned(id, null)  // release claim so a later sync can retry
            }
        }

        if (comp.status === Component.Loading) comp.statusChanged.connect(finalize)
        else finalize(comp.status)
    }

    Component.onCompleted: sync()
}
