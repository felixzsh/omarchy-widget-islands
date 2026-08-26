function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function normalizePosition(value) {
  var next = String(value || "").trim()
  return /^(top|bottom|left|right)$/.test(next) ? next : "top"
}

function normalizeTrigger(value) {
  // Edge indicators are hover-only; keep old config values harmless.
  return "hover"
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (isPlainObject(entry)) {
    var id = entry["id"]
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function entrySettings(entry) {
  if (!isPlainObject(entry)) return {}
  var copy = {}
  for (var key in entry) {
    if (key === "id") continue
    copy[key] = entry[key]
  }
  return copy
}

function isPinned(entry) {
  if (!isPlainObject(entry) && typeof entry !== "string") return false
  var settings = entrySettings(entry)
  if (settings.pinned === true) return true
  if (isPlainObject(entry) && entry.pinned === true) return true
  return false
}

function setPinned(entry, pinned) {
  var id = entryId(entry)
  if (!id) return entry
  var settings = entrySettings(entry)
  var copy = { id: id }
  for (var k in settings) {
    if (k === "pinned") continue
    copy[k] = settings[k]
  }
  if (pinned === true) copy.pinned = true
  return copy
}

function railThickness(barSize) {
  var n = Number(barSize)
  if (!isFinite(n) || n <= 0) n = 26
  return Math.max(4, Math.round(n / 3))
}

function nearestScreenEdge(point, screen) {
  var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
  var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

  var edge = "top"
  var best = ny
  if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
  if (nx < best) { edge = "left"; best = nx }
  if (1 - nx < best) { edge = "right"; best = 1 - nx }
  return edge
}

function normalizeRailLayout(raw) {
  var out = { left: [], center: [], right: [] }
  if (!isPlainObject(raw)) return out
  var sections = ["left", "center", "right"]
  for (var i = 0; i < sections.length; i++) {
    var sec = sections[i]
    var arr = raw[sec]
    out[sec] = Array.isArray(arr) ? arr.slice() : []
  }
  return out
}

function normalizeRailsConfig(raw, mainPosition) {
  var position = normalizePosition(mainPosition)
  var cfg = isPlainObject(raw) ? raw : {}
  var trigger = normalizeTrigger(cfg.trigger)
  // Support both new shape (bar.rails = {enabled, trigger, top:{},...}) and compat old shape (bar.rails.rails or bar.frame)
  var railsRaw = null
  if (isPlainObject(cfg.rails)) {
    railsRaw = cfg.rails
    // if trigger is inside railsRaw (compat), allow fallback
    if (cfg.trigger === undefined && railsRaw.trigger !== undefined) trigger = normalizeTrigger(railsRaw.trigger)
  } else if (isPlainObject(cfg.top) || isPlainObject(cfg.bottom) || isPlainObject(cfg.left) || isPlainObject(cfg.right)) {
    railsRaw = cfg
  } else {
    railsRaw = {}
  }
  var edges = ["top", "bottom", "left", "right"]
  var rails = {}
  for (var e = 0; e < edges.length; e++) {
    var edge = edges[e]
    rails[edge] = normalizeRailLayout(railsRaw[edge])
  }
  // Normalize entries: ensure id string, strip pinned:false, preserve pinned:true
  for (var edgeKey in rails) {
    var layout = rails[edgeKey]
    for (var secKey in layout) {
      var entries = layout[secKey]
      for (var idx = 0; idx < entries.length; idx++) {
        var entry = entries[idx]
        if (typeof entry === "string") {
          var sid = entryId(entry)
          entries[idx] = sid ? { id: sid } : entry
          continue
        }
        if (!isPlainObject(entry)) continue
        // normalize id
        var nid = entryId(entry)
        if (!nid) continue
        // Clean pinned:false
        if (entry.pinned !== true && ("pinned" in entry)) {
          var cleaned = {}
          for (var k2 in entry) if (k2 !== "pinned") cleaned[k2] = entry[k2]
          // ensure id preserved as string
          if (!cleaned.id) cleaned.id = nid
          else cleaned.id = String(cleaned.id)
          entries[idx] = cleaned
        } else {
          // ensure id is string
          if (entry.id !== nid) entry.id = nid
        }
      }
    }
  }
  // Zero-config MVP: no `enabled` flag — rails exist while the plugin does.
  // Visibility is gated by the plugin lifecycle itself and barHidden (the
  // main-bar toggle hides both).
  return { trigger: trigger, rails: rails }
}

function hasAnyWidgets(railLayout) {
  if (!isPlainObject(railLayout)) return false
  return (Array.isArray(railLayout.left) && railLayout.left.length > 0)
    || (Array.isArray(railLayout.center) && railLayout.center.length > 0)
    || (Array.isArray(railLayout.right) && railLayout.right.length > 0)
}

function sectionHasWidgets(railLayout, section) {
  if (!isPlainObject(railLayout) || typeof section !== "string") return false
  var arr = railLayout[section]
  return Array.isArray(arr) && arr.length > 0
}

function railLayoutFor(frameConfig, edge) {
  if (!isPlainObject(frameConfig) || !isPlainObject(frameConfig.rails)) return { left: [], center: [], right: [] }
  var layout = frameConfig.rails[edge]
  return normalizeRailLayout(layout)
}

function hasPinnedWidgets(railLayout) {
  if (!isPlainObject(railLayout)) return false
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = railLayout[sections[s]]
    if (!Array.isArray(arr)) continue
    for (var i = 0; i < arr.length; i++) if (isPinned(arr[i])) return true
  }
  return false
}

// Compat alias for old frame naming
function normalizeFrameConfig(raw, mainPosition) {
  return normalizeRailsConfig(raw, mainPosition)
}

// 3.6 — intra-rail widget move (mirrors Bar.qml moveModuleInConfig but scoped
// to config.bar.rails[edge][section]). Mutates config in place; returns true
// when something moved.
function rawRailSection(config, edge, section) {
  if (!isPlainObject(config.bar)) config.bar = {}
  if (!isPlainObject(config.bar.rails)) config.bar.rails = {}
  if (!isPlainObject(config.bar.rails[edge])) config.bar.rails[edge] = {}
  if (!Array.isArray(config.bar.rails[edge][section])) config.bar.rails[edge][section] = []
  return config.bar.rails[edge][section]
}

function rawRailEntryIndex(entries, name) {
  for (var i = 0; i < entries.length; i++) {
    if (entryId(entries[i]) === name) return i
  }
  return -1
}

function moveRailEntry(config, edge, fromSection, name, toSection, beforeName) {
  var fromEntries = rawRailSection(config, edge, fromSection)
  var toEntries = rawRailSection(config, edge, toSection)
  var fromIndex = rawRailEntryIndex(fromEntries, name)
  if (fromIndex < 0) return false

  var toIndex = beforeName ? rawRailEntryIndex(toEntries, beforeName) : toEntries.length
  if (toIndex < 0) toIndex = toEntries.length

  if (fromSection === toSection && fromIndex === toIndex) return false

  var movedEntry = fromEntries[fromIndex]
  fromEntries.splice(fromIndex, 1)

  if (fromSection === toSection && fromIndex < toIndex) toIndex -= 1
  if (toIndex < 0) toIndex = 0
  if (toIndex > toEntries.length) toIndex = toEntries.length
  if (fromSection === toSection && fromIndex === toIndex) {
    fromEntries.splice(fromIndex, 0, movedEntry)
    return false
  }

  toEntries.splice(toIndex, 0, movedEntry)
  return true
}

// Index-addressed variant: immune to duplicate entry ids (two entries sharing
// a name made name-resolution land on the wrong one → phantom identity/no-op
// drops). targetIndex refers to the entry's position BEFORE removal;
// after=true means "insert past it". targetIndex < 0 = append.
function moveRailEntryAt(config, edge, fromSection, fromIndex, toSection, targetIndex, after) {
  var fromEntries = rawRailSection(config, edge, fromSection)
  var toEntries = rawRailSection(config, edge, toSection)
  if (!Array.isArray(fromEntries) || fromIndex < 0 || fromIndex >= fromEntries.length) return false

  var toIndex
  if (!Array.isArray(toEntries) || toEntries.length === 0 || targetIndex < 0
      || targetIndex >= toEntries.length) {
    toIndex = Array.isArray(toEntries) ? toEntries.length : 0
  } else if (fromSection === toSection && targetIndex === fromIndex) {
    return false
  } else {
    toIndex = after ? targetIndex + 1 : targetIndex
  }

  if (fromSection === toSection && fromIndex === toIndex) return false

  var movedEntry = fromEntries[fromIndex]
  fromEntries.splice(fromIndex, 1)

  if (fromSection === toSection && fromIndex < toIndex) toIndex -= 1
  if (toIndex < 0) toIndex = 0
  if (toIndex > toEntries.length) toIndex = toEntries.length
  if (fromSection === toSection && fromIndex === toIndex) {
    fromEntries.splice(fromIndex, 0, movedEntry)
    return false
  }

  toEntries.splice(toIndex, 0, movedEntry)
  return true
}

// 3.7 — bar → rail move. Source is config.bar.layout[fromRegion], addressed by
// NAME (upstream parity: bar's own dropBarModule is name-addressed too, and a
// slot index into moduleSlots does not map to layout order). Destination uses
// the same index/after protocol as moveRailEntryAt.
function moveBarEntryToRail(config, name, fromRegion, edge, toSection, targetIndex, after) {
  if (!isPlainObject(config.bar)) config.bar = {}
  if (!isPlainObject(config.bar.layout)) config.bar.layout = {}
  if (!Array.isArray(config.bar.layout[fromRegion])) config.bar.layout[fromRegion] = []

  var fromEntries = config.bar.layout[fromRegion]
  var fromIndex = rawRailEntryIndex(fromEntries, name)
  if (fromIndex < 0) return false

  var toEntries = rawRailSection(config, edge, toSection)
  var toIndex
  if (toEntries.length === 0 || targetIndex < 0 || targetIndex >= toEntries.length) {
    toIndex = toEntries.length
  } else {
    toIndex = after ? targetIndex + 1 : targetIndex
  }

  var movedEntry = fromEntries[fromIndex]
  fromEntries.splice(fromIndex, 1)
  toEntries.splice(toIndex, 0, movedEntry)
  return true
}

// 3.7 — ids referenced anywhere across a normalized rails config. The shell
// core keeps a plugin's bar-widget registered only while its id sits in
// bar.layout / plugins / bar.id; rail placements are invisible to
// PluginRegistry.isEnabled(). This helper feeds our registration bridge.
function railReferencedIds(rails) {
  var out = []
  if (!isPlainObject(rails)) return out
  var edges = ["top", "bottom", "left", "right"]
  var sections = ["left", "center", "right"]
  for (var e = 0; e < edges.length; e++) {
    var layout = isPlainObject(rails[edges[e]]) ? rails[edges[e]] : null
    if (!layout) continue
    for (var s = 0; s < sections.length; s++) {
      var arr = layout[sections[s]]
      if (!Array.isArray(arr)) continue
      for (var i = 0; i < arr.length; i++) {
        var id = entryId(arr[i])
        if (id && out.indexOf(id) === -1) out.push(id)
      }
    }
  }
  return out
}

// 3.8 — drop ghost entries from rails config: ids whose plugin is gone from
// disk AND absent from the widget registry (built-ins like omarchy.indicators
// live in the registry, so they never match). Mirrors what the host does to
// bar.layout on plugin disable/remove — rails get the same treatment because
// the host's findEntryLocation doesn't know about bar.rails.
function pruneRailGhosts(config, dropIds) {
  var drop = {}
  var list = Array.isArray(dropIds) ? dropIds : []
  for (var i = 0; i < list.length; i++) drop[String(list[i])] = true
  if (!isPlainObject(config) || !isPlainObject(config.bar) || !isPlainObject(config.bar.rails)) return false

  var changed = false
  var edges = ["top", "bottom", "left", "right"]
  var sections = ["left", "center", "right"]
  for (var e = 0; e < edges.length; e++) {
    var layout = config.bar.rails[edges[e]]
    if (!isPlainObject(layout)) continue
    for (var s = 0; s < sections.length; s++) {
      var arr = layout[sections[s]]
      if (!Array.isArray(arr)) continue
      var kept = []
      for (var j = 0; j < arr.length; j++) {
        var id = entryId(arr[j])
        if (id && drop[id]) changed = true
        else kept.push(arr[j])
      }
      layout[sections[s]] = kept
    }
  }
  return changed
}

// 3.8 — mark plugins enabled via the host's OWN config.plugins list (the
// "enabled without a bar slot" mechanism). Rail placements are invisible to
// the host's isEnabled() (findEntryLocation only scans bar.layout/plugins/
// bar.id), so rail-hosted plugins get added here to unlock the NATIVE
// widget/service/panel lifecycles instead of mirroring them in the bridge.
function ensurePluginsEnabled(config, ids) {
  if (!isPlainObject(config)) return false
  if (!Array.isArray(config.plugins)) config.plugins = []
  var changed = false
  var list = Array.isArray(ids) ? ids : []
  for (var i = 0; i < list.length; i++) {
    var key = String(list[i])
    var found = false
    for (var j = 0; j < config.plugins.length; j++) {
      var e = config.plugins[j]
      if (isPlainObject(e) && entryId(e) === key) { found = true; break }
    }
    if (!found) { config.plugins.push({ id: key }); changed = true }
  }
  return changed
}

// 3.7 universal — rail → other rail (cross-edge). Same index/after protocol as
// moveRailEntryAt, but source and destination live on DIFFERENT edges.
function moveRailEntryBetweenEdges(config, fromEdge, fromSection, fromIndex, toEdge, toSection, targetIndex, after) {
  var fromEntries = rawRailSection(config, fromEdge, fromSection)
  var toEntries = rawRailSection(config, toEdge, toSection)
  if (!Array.isArray(fromEntries) || fromIndex < 0 || fromIndex >= fromEntries.length) return false

  var toIndex
  if (toEntries.length === 0 || targetIndex < 0 || targetIndex >= toEntries.length) {
    toIndex = toEntries.length
  } else {
    toIndex = after ? targetIndex + 1 : targetIndex
  }

  var sameEdge = fromEdge === toEdge && fromSection === toSection
  if (sameEdge && (targetIndex === fromIndex || (after && targetIndex + 1 === fromIndex))) return false

  var movedEntry = fromEntries[fromIndex]
  fromEntries.splice(fromIndex, 1)

  if (sameEdge) {
    if (fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }
  }

  toEntries.splice(toIndex, 0, movedEntry)
  return true
}

// 3.7 universal — ensure & return config.bar.layout[region].
function barLayoutSection(config, region) {
  if (!isPlainObject(config.bar)) config.bar = {}
  if (!isPlainObject(config.bar.layout)) config.bar.layout = {}
  if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []
  return config.bar.layout[region]
}

// Index of the occurrence-th entry whose id == name within a bar region
// layout (-1 when absent). Bar moduleSlots can't be trusted for positional
// math — registration order diverges from layout after any live mutation —
// so cross-surface drops resolve destinations by NAME + geometric occurrence
// ordinal instead, like upstream's name-based drops but duplicate-aware.
function barEntryIndexOfOccurrence(entries, name, occurrence) {
  var arr = Array.isArray(entries) ? entries : []
  var seen = 0
  for (var i = 0; i < arr.length; i++) {
    if (entryId(arr[i]) === name) {
      if (seen === occurrence) return i
      seen++
    }
  }
  return -1
}

// 3.7 universal — rail → native bar. Source index-addressed within its section
// (duplicate ids safe); destination is a bar layout region with an insert-
// before index resolved by the caller (-1 / overflow = append).
function moveRailEntryToBarAt(config, fromEdge, fromSection, fromIndex, toRegion, toIndex) {
  var fromEntries = rawRailSection(config, fromEdge, fromSection)
  if (!Array.isArray(fromEntries) || fromIndex < 0 || fromIndex >= fromEntries.length) return false

  var toEntries = barLayoutSection(config, toRegion)
  var destIndex = toIndex < 0 || toIndex > toEntries.length ? toEntries.length : toIndex

  var movedEntry = fromEntries[fromIndex]
  fromEntries.splice(fromIndex, 1)
  toEntries.splice(destIndex, 0, movedEntry)
  return true
}

// 3.8 — remove ids from config.plugins (stale "enabled" markers left behind
// when a rail-hosted plugin is uninstalled without the host's disable path
// firing; they'd keep isEnabled() true forever and break reinstalls).
function prunePluginsEnabled(config, ids) {
  if (!isPlainObject(config) || !Array.isArray(config.plugins)) return false
  var drop = {}
  var list = Array.isArray(ids) ? ids : []
  for (var i = 0; i < list.length; i++) drop[String(list[i])] = true
  var kept = []
  var changed = false
  for (var j = 0; j < config.plugins.length; j++) {
    var e = config.plugins[j]
    if (isPlainObject(e) && drop[entryId(e)]) changed = true
    else kept.push(e)
  }
  config.plugins = kept
  return changed
}

// 3.8 — PURE decision logic for bridge.reconcile(), extracted so it is
// unit-testable (the QML side just executes the plan in ONE config write).
//
// Ghost detection must NEVER use isEnabled(): once we add a rail-hosted
// plugin to config.plugins, isEnabled() returns true for it, and a plugin
// uninstalled without the host's disable path keeps that stale entry —
// isEnabled stays true and the dot would linger forever. Ghosts are decided
// purely on installedPlugins presence (with the registry guard protecting
// bar-built-in widgets like omarchy.indicators, which are not plugins).
function railReconcilePlan(wanted, installedKeys, registryHas, isEnabled) {
  var list = Array.isArray(wanted) ? wanted : []
  var hasInstalled = typeof installedKeys === "function" ? installedKeys
    : function(key) {
        if (!installedKeys) return false
        if (typeof installedKeys.has === "function") return installedKeys.has(key)
        return installedKeys[key] !== undefined && installedKeys[key] !== null
      }
  var hasRegistry = typeof registryHas === "function" ? registryHas : function() { return false }
  var enabled = typeof isEnabled === "function" ? isEnabled : function() { return false }

  var toEnable = []
  var ghosts = []
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i])
    if (!id) continue
    if (hasInstalled(id)) {
      // Installed: unlock the native lifecycle via config.plugins (the
      // host's own "enabled without a bar slot" mechanism) when needed.
      if (!enabled(id)) toEnable.push(id)
    } else if (!hasRegistry(id)) {
      // Uninstalled (or built-in absent from the registry): drop the rail
      // entry — the host's findEntryLocation can't see rails to clean it.
      ghosts.push(id)
    }
  }
  return { toEnable: toEnable, ghosts: ghosts }
}

if (typeof module !== "undefined") {
  module.exports = {
    isPlainObject: isPlainObject,
    normalizePosition: normalizePosition,
    normalizeTrigger: normalizeTrigger,
    entryId: entryId,
    entrySettings: entrySettings,
    isPinned: isPinned,
    setPinned: setPinned,
    railThickness: railThickness,
    nearestScreenEdge: nearestScreenEdge,
    normalizeRailLayout: normalizeRailLayout,
    normalizeRailsConfig: normalizeRailsConfig,
    normalizeFrameConfig: normalizeFrameConfig,
    hasAnyWidgets: hasAnyWidgets,
    sectionHasWidgets: sectionHasWidgets,
    hasPinnedWidgets: hasPinnedWidgets,
    railLayoutFor: railLayoutFor,
    moveRailEntry: moveRailEntry,
    moveRailEntryAt: moveRailEntryAt,
    moveBarEntryToRail: moveBarEntryToRail,
    moveRailEntryBetweenEdges: moveRailEntryBetweenEdges,
    moveRailEntryToBarAt: moveRailEntryToBarAt,
    barLayoutSection: barLayoutSection,
    barEntryIndexOfOccurrence: barEntryIndexOfOccurrence,
    railReferencedIds: railReferencedIds,
    pruneRailGhosts: pruneRailGhosts,
    ensurePluginsEnabled: ensurePluginsEnabled,
    prunePluginsEnabled: prunePluginsEnabled,
    railReconcilePlan: railReconcilePlan
  }
}
