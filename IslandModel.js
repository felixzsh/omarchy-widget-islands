function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

// The move functions run inside shell.mutateShellConfig, which hands them the
// FULL shell config (with `.bar`). The wrapper only has the `bar:` subtree
// (`.layout`/`.islands` directly). Tolerate both shapes.
function barConfigSection(config) {
  if (!isPlainObject(config)) return null
  return isPlainObject(config.bar) ? config.bar : config
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

function islandThickness(barSize) {
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

function normalizeIslandLayout(raw) {
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

function normalizeIslandsConfig(raw, mainPosition) {
  var position = normalizePosition(mainPosition)
  var cfg = isPlainObject(raw) ? raw : {}
  var trigger = normalizeTrigger(cfg.trigger)
  // Support both new shape (bar.islands = {enabled, trigger, top:{},...}) and compat old shape (bar.islands.islands or bar.frame)
  var islandsRaw = null
  if (isPlainObject(cfg.islands)) {
    islandsRaw = cfg.islands
    // if trigger is inside islandsRaw (compat), allow fallback
    if (cfg.trigger === undefined && islandsRaw.trigger !== undefined) trigger = normalizeTrigger(islandsRaw.trigger)
  } else if (isPlainObject(cfg.top) || isPlainObject(cfg.bottom) || isPlainObject(cfg.left) || isPlainObject(cfg.right)) {
    islandsRaw = cfg
  } else {
    islandsRaw = {}
  }
  var edges = ["top", "bottom", "left", "right"]
  var islands = {}
  for (var e = 0; e < edges.length; e++) {
    var edge = edges[e]
    islands[edge] = normalizeIslandLayout(islandsRaw[edge])
  }
  // Normalize entries: ensure id string, strip pinned:false, preserve pinned:true
  for (var edgeKey in islands) {
    var layout = islands[edgeKey]
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
  // No `enabled` flag is needed — islands exist while the plugin does.
  // Visibility is gated by the plugin lifecycle itself and barHidden (the
  // main-bar toggle hides both).
  return { trigger: trigger, islands: islands }
}

function hasAnyWidgets(islandLayout) {
  if (!isPlainObject(islandLayout)) return false
  return (Array.isArray(islandLayout.left) && islandLayout.left.length > 0)
    || (Array.isArray(islandLayout.center) && islandLayout.center.length > 0)
    || (Array.isArray(islandLayout.right) && islandLayout.right.length > 0)
}

function sectionHasWidgets(islandLayout, section) {
  if (!isPlainObject(islandLayout) || typeof section !== "string") return false
  var arr = islandLayout[section]
  return Array.isArray(arr) && arr.length > 0
}

function islandLayoutFor(frameConfig, edge) {
  if (!isPlainObject(frameConfig) || !isPlainObject(frameConfig.islands)) return { left: [], center: [], right: [] }
  var layout = frameConfig.islands[edge]
  return normalizeIslandLayout(layout)
}

function hasPinnedWidgets(islandLayout) {
  if (!isPlainObject(islandLayout)) return false
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = islandLayout[sections[s]]
    if (!Array.isArray(arr)) continue
    for (var i = 0; i < arr.length; i++) if (isPinned(arr[i])) return true
  }
  return false
}

// Compat alias for old frame naming
function normalizeFrameConfig(raw, mainPosition) {
  return normalizeIslandsConfig(raw, mainPosition)
}

// Intra-island widget move (mirrors Bar.qml moveModuleInConfig but scoped
// to config.bar.islands[edge][section]). Mutates config in place; returns true
// when something moved.
function rawIslandSection(config, edge, section) {
  if (!isPlainObject(config.bar)) config.bar = {}
  if (!isPlainObject(config.bar.islands)) config.bar.islands = {}
  if (!isPlainObject(config.bar.islands[edge])) config.bar.islands[edge] = {}
  if (!Array.isArray(config.bar.islands[edge][section])) config.bar.islands[edge][section] = []
  return config.bar.islands[edge][section]
}

function rawIslandEntryIndex(entries, name) {
  for (var i = 0; i < entries.length; i++) {
    if (entryId(entries[i]) === name) return i
  }
  return -1
}

function moveIslandEntry(config, edge, fromSection, name, toSection, beforeName) {
  var fromEntries = rawIslandSection(config, edge, fromSection)
  var toEntries = rawIslandSection(config, edge, toSection)
  var fromIndex = rawIslandEntryIndex(fromEntries, name)
  if (fromIndex < 0) return false

  var toIndex = beforeName ? rawIslandEntryIndex(toEntries, beforeName) : toEntries.length
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
function moveIslandEntryAt(config, edge, fromSection, fromIndex, toSection, targetIndex, after) {
  var fromEntries = rawIslandSection(config, edge, fromSection)
  var toEntries = rawIslandSection(config, edge, toSection)
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

// A hidden bar.layout entry that keeps an island-hosted widget ENABLED for the
// host. Anchors carry an explicit marker (so rendering can drop them wherever
// a reorder leaves them) and are appended to the center tail (so the bar's own
// name-first entry lookups still hit visible duplicates first).
var ANCHOR_KEY = "__islandAnchor"

function isBarAnchor(entry) {
  return isPlainObject(entry) && entry[ANCHOR_KEY] === true
}

function appendBarAnchor(config, entry) {
  var bar = barConfigSection(config)
  if (!bar) return
  if (!isPlainObject(bar.layout)) bar.layout = {}
  if (!Array.isArray(bar.layout.center)) bar.layout.center = []
  var id = entryId(entry)
  if (!id) return
  var anchor = { id: id }
  anchor[ANCHOR_KEY] = true
  bar.layout.center.push(anchor)
}

// Remove one hidden anchor for this id (last match wins).
function removeBarAnchor(config, entry) {
  var bar = barConfigSection(config)
  if (!bar || !isPlainObject(bar.layout)) return
  var id = entryId(entry)
  if (!id) return
  var sections = ["center", "left", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = bar.layout[sections[s]]
    if (!Array.isArray(arr)) continue
    var idx = -1
    for (var i = 0; i < arr.length; i++) {
      if (isBarAnchor(arr[i]) && entryId(arr[i]) === id) idx = i
    }
    if (idx >= 0) { arr.splice(idx, 1); return }
  }
}

// Bar -> island move. Source is config.bar.layout[fromRegion], addressed by
// NAME (upstream parity: bar's own dropBarModule is name-addressed too, and a
// slot index into moduleSlots does not map to layout order). The entry leaves
// the visible layout but stays in bar.layout as a hidden anchor, because the
// scoped host enables/registers/services a widget only while its id sits in
// bar.layout / plugins[] / bar.id. Destination uses the same index/after
// protocol as moveIslandEntryAt.
function moveBarEntryToIsland(config, name, fromRegion, edge, toSection, targetIndex, after) {
  if (!isPlainObject(config.bar)) config.bar = {}
  if (!isPlainObject(config.bar.layout)) config.bar.layout = {}
  if (!Array.isArray(config.bar.layout[fromRegion])) config.bar.layout[fromRegion] = []

  var fromEntries = config.bar.layout[fromRegion]
  var fromIndex = rawIslandEntryIndex(fromEntries, name)
  if (fromIndex < 0) return false

  var movedEntry = fromEntries[fromIndex]
  fromEntries.splice(fromIndex, 1)
  appendBarAnchor(config, movedEntry)

  var toEntries = rawIslandSection(config, edge, toSection)
  var toIndex
  if (toEntries.length === 0 || targetIndex < 0 || targetIndex >= toEntries.length) {
    toIndex = toEntries.length
  } else {
    toIndex = after ? targetIndex + 1 : targetIndex
  }

  toEntries.splice(toIndex, 0, movedEntry)
  return true
}

// IDs referenced anywhere across a normalized islands config. The shell
// core keeps a plugin's bar-widget registered only while its id sits in
// bar.layout / plugins / bar.id; island placements are invisible to
// PluginRegistry.isEnabled(). This helper feeds our registration bridge.
function islandReferencedIds(islands) {
  var out = []
  if (!isPlainObject(islands)) return out
  var edges = ["top", "bottom", "left", "right"]
  var sections = ["left", "center", "right"]
  for (var e = 0; e < edges.length; e++) {
    var layout = isPlainObject(islands[edges[e]]) ? islands[edges[e]] : null
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

// Index of the LAST entry with this id in an array, or -1.
function lastIndexById(entries, id) {
  if (!Array.isArray(entries)) return -1
  var found = -1
  for (var i = 0; i < entries.length; i++) {
    if (entryId(entries[i]) === id) found = i
  }
  return found
}

// True when an id already has an entry anywhere in bar.layout (`left`/`center`/
// `right` — the sections the host scans for enablement).
function barLayoutHasId(config, id) {
  var bar = barConfigSection(config)
  if (!bar || !isPlainObject(bar.layout)) return false
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    if (lastIndexById(bar.layout[sections[s]], id) >= 0) return true
  }
  return false
}

// The bar.layout the inner Bar should render: the raw layout with every hidden
// anchor dropped. Filtering by marker (not position) keeps it correct even if
// the bar's own reorder moved an anchor around.
function visibleBarConfig(barConfig) {
  var config = isPlainObject(barConfig) ? barConfig : {}
  var layout = isPlainObject(config.layout) ? config.layout : {}
  var out = {}
  for (var key in config) out[key] = config[key]
  out.layout = { left: [], center: [], right: [] }
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = layout[sections[s]]
    var kept = []
    if (Array.isArray(arr)) {
      for (var i = 0; i < arr.length; i++) {
        if (!isBarAnchor(arr[i])) kept.push(arr[i])
      }
    }
    out.layout[sections[s]] = kept
  }
  return out
}

// One-time (flag-guarded) migration: island layouts written by older plugin
// versions live only in bar.islands, so the scoped host never enabled them.
// Anchor every id ONCE. The flag then stays set, so anchors the host removes
// for a disabled/uninstalled plugin are never blindly re-added.
function islandAnchorMigrationNeeded(config) {
  var bar = barConfigSection(config)
  if (!bar) return false
  var islands = bar.islands
  if (!isPlainObject(islands) || islands.anchorsMigrated === true) return false
  return islandReferencedIds(islands).length > 0
}

function migrateIslandAnchors(config) {
  if (!islandAnchorMigrationNeeded(config)) return false
  var bar = barConfigSection(config)
  var islands = bar.islands
  var ids = islandReferencedIds(islands)
  for (var i = 0; i < ids.length; i++) {
    if (barLayoutHasId(config, ids[i])) continue
    appendBarAnchor(config, { id: ids[i] })
  }
  islands.anchorsMigrated = true
  return true
}

// Island ids whose anchor is gone (the host removes bar.layout entries for a
// disabled/uninstalled plugin) and that are no longer registered. Only used
// after migration, so a pristine legacy config is never treated as orphan.
function orphanIslandIds(config, registryHas) {
  var bar = barConfigSection(config)
  if (!bar) return []
  var islands = bar.islands
  if (!isPlainObject(islands) || islands.anchorsMigrated !== true) return []
  var has = typeof registryHas === "function" ? registryHas : function() { return true }
  var ids = islandReferencedIds(islands)
  var out = []
  for (var i = 0; i < ids.length; i++) {
    if (barLayoutHasId(config, ids[i])) continue
    if (has(ids[i])) continue
    out.push(ids[i])
  }
  return out
}

function dropIslandIds(config, ids) {
  var bar = barConfigSection(config)
  if (!bar) return false
  var islands = bar.islands
  if (!isPlainObject(islands) || !Array.isArray(ids)) return false
  var drop = {}
  for (var i = 0; i < ids.length; i++) drop[String(ids[i])] = true
  var changed = false
  var edges = ["top", "bottom", "left", "right"]
  var sections = ["left", "center", "right"]
  for (var e = 0; e < edges.length; e++) {
    var layout = islands[edges[e]]
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

// Island -> other island (cross-edge). Same index/after protocol as
// moveIslandEntryAt, but source and destination live on DIFFERENT edges.
function moveIslandEntryBetweenEdges(config, fromEdge, fromSection, fromIndex, toEdge, toSection, targetIndex, after) {
  var fromEntries = rawIslandSection(config, fromEdge, fromSection)
  var toEntries = rawIslandSection(config, toEdge, toSection)
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

// Ensure and return config.bar.layout[region].
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

// Island -> native bar. Source index-addressed within its section
// (duplicate ids safe); destination is a bar layout region with an insert-
// before index resolved by the caller (-1 / overflow = append). The widget's
// hidden anchor is consumed so it renders on the bar again.
function moveIslandEntryToBarAt(config, fromEdge, fromSection, fromIndex, toRegion, toIndex) {
  var fromEntries = rawIslandSection(config, fromEdge, fromSection)
  if (!Array.isArray(fromEntries) || fromIndex < 0 || fromIndex >= fromEntries.length) return false

  var movedEntry = fromEntries[fromIndex]
  fromEntries.splice(fromIndex, 1)
  removeBarAnchor(config, movedEntry)

  var toEntries = barLayoutSection(config, toRegion)
  var destIndex = toIndex < 0 || toIndex > toEntries.length ? toEntries.length : toIndex
  toEntries.splice(destIndex, 0, movedEntry)
  return true
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
    islandThickness: islandThickness,
    nearestScreenEdge: nearestScreenEdge,
    normalizeIslandLayout: normalizeIslandLayout,
    normalizeIslandsConfig: normalizeIslandsConfig,
    normalizeFrameConfig: normalizeFrameConfig,
    hasAnyWidgets: hasAnyWidgets,
    sectionHasWidgets: sectionHasWidgets,
    hasPinnedWidgets: hasPinnedWidgets,
    islandLayoutFor: islandLayoutFor,
    moveIslandEntry: moveIslandEntry,
    moveIslandEntryAt: moveIslandEntryAt,
    moveBarEntryToIsland: moveBarEntryToIsland,
    moveIslandEntryBetweenEdges: moveIslandEntryBetweenEdges,
    moveIslandEntryToBarAt: moveIslandEntryToBarAt,
    barLayoutSection: barLayoutSection,
    barEntryIndexOfOccurrence: barEntryIndexOfOccurrence,
    islandReferencedIds: islandReferencedIds,
    lastIndexById: lastIndexById,
    barLayoutHasId: barLayoutHasId,
    isBarAnchor: isBarAnchor,
    visibleBarConfig: visibleBarConfig,
    islandAnchorMigrationNeeded: islandAnchorMigrationNeeded,
    migrateIslandAnchors: migrateIslandAnchors,
    orphanIslandIds: orphanIslandIds,
    dropIslandIds: dropIslandIds,
    appendBarAnchor: appendBarAnchor,
    removeBarAnchor: removeBarAnchor
  }
}
