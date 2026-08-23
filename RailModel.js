function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function normalizePosition(value) {
  var next = String(value || "").trim()
  return /^(top|bottom|left|right)$/.test(next) ? next : "top"
}

function normalizeTrigger(value) {
  var v = String(value || "").trim().toLowerCase()
  return v === "click" ? "click" : "hover"
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
  var enabled = cfg.enabled === true
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
  return { enabled: enabled, trigger: trigger, rails: rails }
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

function frameVisible(frameConfig, edge, mainPosition) {
  if (!isPlainObject(frameConfig) || frameConfig.enabled !== true) return false
  return normalizePosition(edge) !== normalizePosition(mainPosition)
}

function railsVisible(config, edge, mainPosition) {
  return frameVisible(config, edge, mainPosition)
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
    frameVisible: frameVisible,
    railsVisible: railsVisible,
    moveRailEntry: moveRailEntry,
    moveRailEntryAt: moveRailEntryAt,
    moveBarEntryToRail: moveBarEntryToRail
  }
}
