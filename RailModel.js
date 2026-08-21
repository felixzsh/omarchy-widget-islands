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
    normalizeRailLayout: normalizeRailLayout,
    normalizeRailsConfig: normalizeRailsConfig,
    normalizeFrameConfig: normalizeFrameConfig,
    hasAnyWidgets: hasAnyWidgets,
    sectionHasWidgets: sectionHasWidgets,
    hasPinnedWidgets: hasPinnedWidgets,
    railLayoutFor: railLayoutFor,
    frameVisible: frameVisible,
    railsVisible: railsVisible
  }
}
