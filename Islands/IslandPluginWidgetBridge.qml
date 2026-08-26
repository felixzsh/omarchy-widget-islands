import QtQuick
import "../IslandModel.js" as IslandModel

// Registration bridge for plugin bar-widgets hosted in islands.
//
// The shell core keeps a plugin's bar-widget registered only while its id is
// reachable from config.bar.layout / config.plugins / bar.id — that is the
// whole body of PluginRegistry.isEnabled(). A widget dragged into an island
// leaves bar.layout, isEnabled() flips false, and syncPluginWidgets' sweep
// unregisters it: islands keep counting dots but resolve component NULL.
// Natives survive via __isFirstParty; third-party plugins need this bridge.
//
// We mirror shell.qml's loadPluginWidget cycle for island-referenced plugin ids
// the core does not currently hold: async createComponent + register with the
// same metadata shape. Safe against the core's sweep because it only drops
// keys present in its internal pluginWidgetComponents map — ours are foreign.
// When the same id later returns to the native bar, the core re-registers over
// our key with an equivalent component (no gap, last write wins).
Item {
    id: bridge

    // Shell root — needs .barWidgetRegistry and .pluginRegistry
    required property var shell
    // normalizedIslands ({islands:{edge:{section:[entries]}}}) or the islands map itself
    required property var islandsConfig
    // Bump externally to force a resync after config mutations
    property int cfgSerial: 0

    // registryKey -> { url: string, component: Component|null }
    property var owned: ({})

    onIslandsConfigChanged: reconcile()
    onCfgSerialChanged: reconcile()

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
        reconcile()
    }

    function islandIds() {
        var islands = islandsConfig && islandsConfig.islands ? islandsConfig.islands : islandsConfig
        return IslandModel.islandReferencedIds(islands)
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

        var wanted = islandIds()

        // Release ours whose ids left the islands entirely.
        var nextOwned = {}
        for (var key in owned) {
            if (wanted.indexOf(key) !== -1) { nextOwned[key] = owned[key]; continue }
            if (owned[key] && owned[key].component) reg.unregister(key)
        }
        owned = nextOwned

        for (var i = 0; i < wanted.length; i++) loadIfNeeded(wanted[i], reg, plugins)

        // Services (dynamic data: live counters, trackers, daemons-with-state).
        // The host only starts a plugin's service while isEnabled() says so,
        // and its placement scan doesn't know about islands — island-hosted
        // widgets would render but feed on a service that never exists.
        // ensureService() is public and ungated; idempotent, so calling it
        // every sync (signals + 4s timer) keeps the service alive across the
        // core's sweeps. These services persist state to disk by design, so
        // even a destroy/recreate cycle loses nothing.
        //
        // UPSTREAM-PR(omarchy-core): teach PluginRegistry.findEntryLocation
        // about config.bar.islands[edge][section] (mirror findBarLocation with
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
    // islands whose plugin is gone from disk AND absent from the widget
    // registry (built-ins live in the registry, so never pruned). Mirrors the
    // host pruning bar.layout on plugin remove — its findEntryLocation can't
    // see bar.islands, so without this the dead dot would linger forever.
    // Teach the host's OWN enablement system about island placements. The host
    // treats a plugin as enabled when its id sits in bar.layout, plugins[],
    // or bar.id — nothing knows bar.islands. Adding island-hosted ids to
    // config.plugins (the host's native "enabled without a bar slot" list)
    // unlocks every lifecycle through the CORE: widget registration, service
    // sync, and the panel/overlay loader that summon/toggle route through
    // (isEnabled() gates all three).
    //
    // The same single write also prunes island entries that are no longer
    // host-enabled (uninstalled OR explicitly disabled) — main-bar parity,
    // since the host's findEntryLocation can't see islands to clean them.
    // The registry guard keeps bar-built-in widgets (omarchy.indicators,
    // keyboard-layout, ...) which live outside installedPlugins safe.
    function reconcile() {
        var reg = shell ? shell.barWidgetRegistry : null
        var plugins = shell && shell.pluginRegistry ? shell.pluginRegistry.installedPlugins : null
        if (!reg || !plugins) return
        if (typeof shell.pluginRegistry.isEnabled !== "function") return
        if (typeof shell.mutateShellConfig !== "function") return

        // Decision logic lives in IslandModel.islandReconcilePlan (pure, tested).
        // Note: ghost detection is installedPlugins-based on purpose — using
        // isEnabled() self-poisons via the config.plugins entries we add.
        var plan = IslandModel.islandReconcilePlan(
            islandIds(),
            plugins,
            function(id) { return reg.has(id) },
            function(id) { return shell.pluginRegistry.isEnabled(id) })
        if (!plan.toEnable.length && !plan.ghosts.length) return

        var addIds = plan.toEnable
        var dropIds = plan.ghosts
        shell.mutateShellConfig(function(config) {
            var changed = IslandModel.ensurePluginsEnabled(config, addIds)
            changed = IslandModel.pruneIslandGhosts(config, dropIds) || changed
            // Stale plugins[] markers for uninstalled ids would keep
            // isEnabled() true forever and break reinstalls.
            changed = IslandModel.prunePluginsEnabled(config, dropIds) || changed
            if (changed)
                console.warn("[RAIL] reconciled island plugins:",
                    "add=", addIds.length ? addIds.join(",") : "-",
                    "drop=", dropIds.length ? dropIds.join(",") : "-")
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
