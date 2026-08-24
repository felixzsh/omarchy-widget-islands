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

    // Plugin install/uninstall events arrive in a STORM (dozens of reload
    // signals per action) while the host rebuilds every plugin tree. Acting
    // per-event amplifies that: component/service churn + config writes during
    // the storm froze the shell and once lost widgets to a write race. So all
    // plugin-event work goes through ONE settle timer — single sync + single
    // prune, only once the storm has quieted (no scanning/reloading).
    Timer {
        id: settleTimer
        interval: 3000
        repeat: false
        onTriggered: bridge.onSettle()
    }

    // Safety net: core sweeps ride scan events whose ordering vs our triggers
    // is undefined; a cheap periodic re-settle closes any gap. No-op when idle.
    Timer {
        interval: 4000
        running: bridge.shell !== null
        repeat: true
        onTriggered: bridge.onSettle()
    }

    Connections {
        target: bridge.shell ? bridge.shell.pluginRegistry : null
        function onPluginsChanged() { settleTimer.restart() }
        function onScanFinished() { settleTimer.restart() }
    }

    function storming() {
        return shell !== null && shell.pluginRegistry !== null
            && (shell.pluginReloading === true || shell.pluginRegistry.scanning === true)
    }

    function onSettle() {
        if (storming()) { settleTimer.restart(); return }
        sync()
        pruneGhosts()
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

    // Plugin reload storms (any install/uninstall touches every local plugin)
    // destroy THIS tree — and with it the QML context our components were
    // created from. Registered-but-zombie components then fail every future
    // instantiation ("Cannot create a component in an invalid context") while
    // reg.has(id) keeps us from ever refreshing them. Release our keys on the
    // way out so the next incarnation registers fresh, valid ones.
    Component.onDestruction: {
        var reg = shell ? shell.barWidgetRegistry : null
        if (!reg) return
        for (var key in owned) {
            if (owned[key] && owned[key].component && reg.has(key)) reg.unregister(key)
        }
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

    // One config write, after the storm settles. Ghosts = ids referenced in
    // rails whose plugin is gone from disk AND absent from the widget
    // registry (built-ins live in the registry, so never pruned). Mirrors the
    // host pruning bar.layout on plugin remove — its findEntryLocation can't
    // see bar.rails, so without this the dead dot would linger forever.
    function pruneGhosts() {
        var reg = shell ? shell.barWidgetRegistry : null
        var plugins = shell && shell.pluginRegistry ? shell.pluginRegistry.installedPlugins : null
        if (!reg || !plugins) return
        if (typeof shell.mutateShellConfig !== "function") return

        var wanted = railIds()
        var ghosts = []
        for (var i = 0; i < wanted.length; i++) {
            var id = wanted[i]
            if (!plugins[id] && !reg.has(id)) ghosts.push(id)
        }
        if (!ghosts.length) return

        var dropIds = ghosts
        shell.mutateShellConfig(function(config) {
            if (RailModel.pruneRailGhosts(config, dropIds))
                console.warn("[RAIL] pruned ghost rail entries:", dropIds.join(", "))
        })
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
