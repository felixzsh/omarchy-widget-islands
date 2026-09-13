#!/usr/bin/env bash
# islands-test.sh — Islands-specific tests (not upstream).
# Validates IslandModel.js when present.
# Run with:  test/islands-test.sh   or   test/run-upstream.sh test/islands-test.sh

set -euo pipefail

FRAME_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# ROOT for node harness: if coming from run-upstream.sh it is already TMP, otherwise frame
ROOT="${ROOT:-$FRAME_ROOT}"
export ROOT

# Reuse upstream harness (pass/fail/assert) if it exists, otherwise define local
if [[ -f "$ROOT/test/shell.d/base-test.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/test/shell.d/base-test.sh"
else
  # minimal fallback when run isolated without upstream checkout
  pass() { printf 'ok - %s\n' "$1"; }
  fail() { printf 'not ok - %s\n' "$1" >&2; [[ -n "${2:-}" ]] && printf '%s\n' "$2" >&2; exit 1; }
  require_command() { command -v "$1" >/dev/null || fail "required command: $1"; }
  run_node_test() {
    require_command node
    {
      cat <<'JS_PRELUDE'
const path = require('path')
const root = process.env.ROOT
function fail(description, detail) {
  if (detail) console.error(detail)
  console.error(`not ok - ${description}`)
  process.exit(1)
}
function pass(description) { console.log(`ok - ${description}`) }
function assert(condition, description, detail) {
  if (!condition) fail(description, detail)
  pass(description)
}
function assertEqual(actual, expected, description) {
  assert(actual === expected, description, `expected: ${expected}\nactual:   ${actual}`)
}
function assertDeepEqual(actual, expected, description) {
  const actualJson = JSON.stringify(actual)
  const expectedJson = JSON.stringify(expected)
  assert(actualJson === expectedJson, description, `expected: ${expectedJson}\nactual:   ${actualJson}`)
}
function requireFromRoot(relativePath) {
  return require(path.join(root, relativePath))
}
JS_PRELUDE
      cat
    } | node
  }
  export ROOT
fi

# If IslandModel.js does not exist yet, skip informatively
for check in "$FRAME_ROOT/IslandModel.js" "$ROOT/shell/plugins/bar/IslandModel.js"; do
  if [[ -f "$check" ]]; then found=1; break; fi
done
if [[ -z "${found:-}" ]]; then
  pass "IslandModel.js does not exist yet — skip islands-test"
  exit 0
fi

run_node_test <<'JS'
const fs = require('fs')

// Resolve IslandModel from islands or overlay
let islandPath = null
for (const cand of [
  path.join(process.env.ROOT, 'shell/plugins/bar/IslandModel.js'),
  path.join(process.env.ROOT, '../omarchy-frame/IslandModel.js'),
  path.join(path.join(process.env.ROOT || '', '../omarchy-frame/IslandModel.js')),
]) {
  if (fs.existsSync(cand)) { islandPath = cand; break }
}
if (!islandPath) {
  const alt = path.join(process.env.ROOT || '', 'IslandModel.js')
  if (fs.existsSync(alt)) islandPath = alt
}
if (!islandPath) {
  console.log('ok - IslandModel.js not found, skip')
  process.exit(0)
}

const src = fs.readFileSync(islandPath, 'utf8')
// IslandModel is plain JS (no pragma), evaluate in vm
const vm = require('vm')
const ctx = { module: { exports: {} }, exports: {}, console }
vm.createContext(ctx)
const clean = src.replace(/^\s*\.pragma library\s*\n/m, '')
vm.runInContext(clean, ctx)
const rm = ctx.module.exports || ctx

const normalizeFn = rm.normalizeIslandsConfig
if (typeof rm.islandThickness !== 'function' && typeof normalizeFn !== 'function') {
  console.log('ok - IslandModel has no testable API yet (WIP)')
  process.exit(0)
}

// --- Concrete tests (enabled when you implement IslandModel) ---
if (typeof rm.islandThickness === 'function') {
  assertEqual(rm.islandThickness(26), 9, 'islandThickness 26 -> ~9 (1/3)')
  assertEqual(rm.islandThickness(28), 9, 'islandThickness 28 -> ~9 (1/3)')
  assert(rm.islandThickness(6) >= 4, 'islandThickness clamps to minimum 4')
}

if (typeof rm.isPinned === 'function' && typeof rm.setPinned === 'function') {
  assertEqual(rm.isPinned({ id: 'a' }), false, 'isPinned default false')
  assertEqual(rm.isPinned({ id: 'a', pinned: true }), true, 'isPinned true')
  assertEqual(rm.isPinned({ id: 'a', pinned: false }), false, 'isPinned explicit false')
  const e = { id: 'x' }
  const pinned = rm.setPinned(e, true)
  assertEqual(pinned.pinned, true, 'setPinned true adds key')
  assertEqual(e.pinned, undefined, 'setPinned does not mutate original')
  assertEqual(rm.setPinned({ id: 'x', pinned: true }, false).pinned, undefined, 'setPinned false removes key')
}

if (typeof normalizeFn === 'function') {
  let bar = null
  for (const bp of [path.join(process.env.ROOT, 'shell/plugins/bar/BarModel.js'), path.join(process.env.ROOT, 'BarModel.js'), path.join(process.env.ROOT, '../BarModel.js')]) {
    try { bar = require(bp); break } catch (e) {}
  }
  if (!bar) { console.log('ok - BarModel not found, skip normalize checks'); } else {
  let cfg = normalizeFn(undefined, 'top')
  assertEqual(cfg.islands.top.left.length, 0, 'normalize undefined -> zero-config empty islands')
  assertEqual(cfg.trigger, 'hover', 'normalize undefined -> default trigger hover')
  assertEqual(rm.normalizeTrigger('click'), 'hover', 'click trigger is normalized to hover')
  assert(cfg.enabled === undefined, 'no enabled flag in output')
  // legacy explicit enabled:false is ignored entirely
  cfg = normalizeFn({ enabled: false, bottom: { left: [{ id: 'x' }] } }, 'top')
  assertEqual(cfg.islands.bottom.left[0].id, 'x', 'legacy enabled:false ignored')
  cfg = normalizeFn({ top: { left: [{ id: 'omarchy.tray' }] } }, 'top')
  assertEqual(cfg.islands.top.left[0].id, 'omarchy.tray', 'bar.islands direct top.left')
  // inline pinned preserved
  cfg = normalizeFn({ bottom: { right: [{ id: 'omarchy.audio', pinned: true }] } }, 'top')
  let entry = cfg.islands.bottom.right[0]
  assertEqual(entry.id, 'omarchy.audio', 'islands preserves id')
  assertEqual(entry.pinned, true, 'islands preserves pinned:true')
  // dots per section: hasAnyWidgets and sectionHasWidgets (if present)
  if (typeof rm.hasAnyWidgets === 'function') {
    assertEqual(rm.hasAnyWidgets({ left: [{id:'a'}], center: [], right: [] }), true, 'hasAnyWidgets true if any section has widgets')
    assertEqual(rm.hasAnyWidgets({ left: [], center: [], right: [] }), false, 'hasAnyWidgets false if empty')
  }
  if (typeof rm.sectionHasWidgets === 'function') {
    assertEqual(rm.sectionHasWidgets({ left: [{id:'a'}], center: [], right: [] }, 'left'), true, 'sectionHasWidgets left true')
    assertEqual(rm.sectionHasWidgets({ left: [{id:'a'}], center: [], right: [] }, 'center'), false, 'sectionHasWidgets center false')
  }

  // moveIslandEntry (intra-island drag & drop persistence)
  function freshConfig() {
    return { bar: { islands: { bottom: {
      left: [{id:'a'}, {id:'b'}, {id:'c'}],
      center: [{id:'x'}],
      right: []
    } } } }
  }
  if (rm.moveIslandEntry) {
    // same-section reorder forward
    let c = freshConfig()
    assertEqual(rm.moveIslandEntry(c, 'bottom', 'left', 'a', 'left', 'c'), true, 'move a before c')
    let ids = c.bar.islands.bottom.left.map(e => e.id).join(',')
    assertEqual(ids, 'b,a,c', 'left order after move a before c')
    // same-section no-op (b before c == already there)
    c = freshConfig()
    assertEqual(rm.moveIslandEntry(c, 'bottom', 'left', 'b', 'left', 'c'), false, 'move b before c is identity')
    ids = c.bar.islands.bottom.left.map(e => e.id).join(',')
    assertEqual(ids, 'a,b,c', 'identity leaves order untouched')
    // same-section real swap
    c = freshConfig()
    assertEqual(rm.moveIslandEntry(c, 'bottom', 'left', 'b', 'left', 'a'), true, 'move b before a swaps')
    assertEqual(c.bar.islands.bottom.left.map(e => e.id).join(','), 'b,a,c', 'swap applied')
    // cross-section before target
    c = freshConfig()
    assertEqual(rm.moveIslandEntry(c, 'bottom', 'left', 'a', 'center', 'x'), true, 'move a to center before x')
    assertEqual(c.bar.islands.bottom.left.map(e => e.id).join(','), 'b,c', 'source section loses a')
    assertEqual(c.bar.islands.bottom.center.map(e => e.id).join(','), 'a,x', 'center gains a before x')
    // cross-section append (beforeName empty)
    c = freshConfig()
    rm.moveIslandEntry(c, 'bottom', 'left', 'b', 'right', '')
    assertEqual(c.bar.islands.bottom.right.map(e => e.id).join(','), 'b', 'append to empty right')
    // drop after last target → append semantics
    c = freshConfig()
    rm.moveIslandEntry(c, 'bottom', 'center', 'x', 'left', '')
    assertEqual(c.bar.islands.bottom.left.map(e => e.id).join(','), 'a,b,c,x', 'x appended to left end')
    // missing widget → false
    c = freshConfig()
    assertEqual(rm.moveIslandEntry(c, 'bottom', 'left', 'zz', 'center', ''), false, 'missing id returns false')
  }
  if (rm.moveBarEntryToIsland) {
    // bar layout → island section, before target
    let c2 = { bar: { position: 'top', layout: { left: [{id:'tray'},{id:'net'}] },
      islands: { bottom: { left: [], center: [{id:'x'}], right: [] } } } }
    assertEqual(rm.moveBarEntryToIsland(c2, 'net', 'left', 'bottom', 'center', 0, false), true, 'bar->island before x')
    assertEqual(c2.bar.layout.left.map(e => e.id).join(','), 'tray', 'bar layout loses net')
    assertEqual(c2.bar.layout.center.map(e => e.id).join(','), 'net', 'net keeps a hidden bar anchor')
    assertEqual(c2.bar.islands.bottom.center.map(e => e.id).join(','), 'net,x', 'island center gains net before x')
    // append to empty island section (targetIndex -1)
    c2 = { bar: { layout: { center: [{id:'clock'}] }, islands: { top: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveBarEntryToIsland(c2, 'clock', 'center', 'top', 'right', -1, false), true, 'bar->island append empty')
    assertEqual(c2.bar.islands.top.right.map(e => e.id).join(','), 'clock', 'empty right gains clock')
    assertEqual(c2.bar.layout.center.map(e => e.id).join(','), 'clock', 'anchor kept after leaving center')
    // after=true inserts past target
    c2 = { bar: { layout: { right: [{id:'a'}] }, islands: { left: { left: [{id:'p'},{id:'q'}], center: [], right: [] } } } }
    rm.moveBarEntryToIsland(c2, 'a', 'right', 'left', 'left', 0, true)
    assertEqual(c2.bar.islands.left.left.map(e => e.id).join(','), 'p,a,q', 'after=true lands past p')
    // preserves entry object shape
    c2 = { bar: { layout: { left: [{id:'aud', pinned: true}] }, islands: { bottom: { left: [], center: [], right: [] } } } }
    rm.moveBarEntryToIsland(c2, 'aud', 'left', 'bottom', 'center', -1, false)
    assertEqual(c2.bar.islands.bottom.center[0].pinned, true, 'entry object preserved')
    // missing id
    assertEqual(rm.moveBarEntryToIsland({bar:{layout:{left:[]},islands:{}}}, 'nope', 'left', 'top', 'left', -1, false), false, 'bar->island missing id false')
  }
  if (rm.islandReferencedIds) {
    let r = { bottom: { left: [{id:'a'}], center: [{id:'b'},'c'], right: [] },
              left:  { left: [], center: ['a'], right: [{id:'d'}] },
              top: { left: [], center: [], right: [] },
              right: { left: [], center: [], right: [] } }
    let ids = rm.islandReferencedIds(r)
    assertEqual(ids.length, 4, 'islandReferencedIds dedupes across edges')
    for (const want of ['a','b','c','d']) assert(ids.indexOf(want) !== -1, 'contains ' + want)
    assertEqual(rm.islandReferencedIds({}).length, 0, 'empty islands -> empty ids')
    assertEqual(rm.islandReferencedIds(null).length, 0, 'null islands -> empty ids')
  }
  if (rm.lastIndexById) {
    const arr = [{id:'a'},'b',{id:'a'},{id:'c'}]
    assertEqual(rm.lastIndexById(arr,'a'),2,'last index of a')
    assertEqual(rm.lastIndexById(arr,'b'),1,'last index of string b')
    assertEqual(rm.lastIndexById(arr,'zz'),-1,'missing -> -1')
    assertEqual(rm.lastIndexById(null,'a'),-1,'null entries -> -1')
  }
  if (rm.barLayoutHasId) {
    const cfg = { bar: { layout: { left: [{id:'a'}], center: ['b'], right: [] } } }
    assertEqual(rm.barLayoutHasId(cfg,'a'),true,'found in left')
    assertEqual(rm.barLayoutHasId(cfg,'b'),true,'found as string in center')
    assertEqual(rm.barLayoutHasId(cfg,'zz'),false,'absent -> false')
    assertEqual(rm.barLayoutHasId({},'a'),false,'no layout -> false')
  }
  if (rm.visibleBarConfig) {
    // anchors are marked, so rendering drops them wherever they sit.
    const cfg = { position:'top', layout: {
      left: [{id:'barleft'}], center: [{id:'clock'}], right: [] } }
    cfg.layout.center.push({ id:'sp', __islandAnchor: true })
    const vis = rm.visibleBarConfig(cfg)
    assertEqual(vis.layout.left.map(e=>e.id).join(','), 'barleft', 'left untouched')
    assertEqual(vis.layout.center.map(e=>e.id).join(','), 'clock', 'marked anchor hidden, clock kept')
    assertEqual(cfg.layout.center.length, 2, 'source layout not mutated')
    assertEqual(vis.layout.center.length, 1, 'anchor not rendered')
    assertEqual(vis.layout.center[0].__islandAnchor, undefined, 'rendered entries carry no marker')
  }
  if (rm.islandAnchorMigrationNeeded && rm.migrateIslandAnchors) {
    // legacy: island ids with no bar anchor -> migrate adds anchors once
    let m = { bar: { layout: { left: [{id:'keep'}], center: [], right: [] },
      islands: { bottom: { left: [{id:'a'}, {id:'b'}], center: [], right: [] } } } }
    assertEqual(rm.islandAnchorMigrationNeeded(m), true, 'legacy config needs migration')
    assertEqual(rm.migrateIslandAnchors(m), true, 'migration reports changed')
    assertEqual(m.bar.islands.anchorsMigrated, true, 'flag persisted')
    assertEqual(rm.barLayoutHasId(m,'a'), true, 'a anchored')
    assertEqual(rm.barLayoutHasId(m,'b'), true, 'b anchored')
    assertEqual(rm.isBarAnchor(m.bar.layout.center[0]), true, 'anchor carries the hidden marker')
    assertEqual(rm.islandAnchorMigrationNeeded(m), false, 'idempotent once flagged')
    // id already in layout -> no duplicate anchor
    let m2 = { bar: { layout: { left: [], center: [{id:'c'}], right: [] },
      islands: { bottom: { left: [{id:'c'}], center: [], right: [] } } } }
    rm.migrateIslandAnchors(m2)
    assertEqual(m2.bar.layout.center.length, 1, 'existing id not double-anchored')
    // the wrapper only has the `bar:` subtree; the mutator gets the full config
    let m3 = { layout: { left: [], center: [], right: [] },
      islands: { bottom: { left: [{id:'x'}], center: [], right: [] } } }
    assertEqual(rm.islandAnchorMigrationNeeded(m3), true, 'bar-subtree shape needs migration')
    rm.migrateIslandAnchors(m3)
    assertEqual(rm.barLayoutHasId(m3,'x'), true, 'anchor added to bar-subtree shape')
    assertEqual(m3.islands.anchorsMigrated, true, 'bar-subtree flag persisted')
  }
  if (rm.orphanIslandIds && rm.dropIslandIds) {
    // post-migration: anchor gone + not registered -> orphan
    let o = { bar: { layout: { left: [], center: [{id:'alive'}], right: [] },
      islands: { anchorsMigrated: true,
        bottom: { left: [{id:'alive'}, {id:'gone'}], center: [], right: [] },
        top: { left: [], center: [], right: [] }, left: { left: [], center: [], right: [] },
        right: { left: [], center: [], right: [] } } } }
    let ids = rm.orphanIslandIds(o, function(id){ return id === 'alive' })
    assertEqual(ids.join(','), 'gone', 'only the orphan is reported')
    assertEqual(rm.dropIslandIds(o, ids), true, 'drop reports changed')
    assertEqual(o.bar.islands.bottom.left.map(e=>e.id).join(','), 'alive', 'orphan removed')
    // before migration never prunes
    let pre = { bar: { layout: { left: [], center: [], right: [] },
      islands: { bottom: { left: [{id:'legacy'}], center: [], right: [] } } } }
    assertEqual(rm.orphanIslandIds(pre, function(){ return false }).length, 0,
      'pre-migration never orphans')
    // bar-subtree shape (what the wrapper's pre-check sees)
    let o2 = { layout: { left: [], center: [], right: [] },
      islands: { anchorsMigrated: true, bottom: { left: [{id:'dead'}], center: [], right: [] } } }
    assertEqual(rm.orphanIslandIds(o2, function(){ return false }).join(','), 'dead',
      'bar-subtree orphan detected')
  }
  if (rm.moveIslandEntryBetweenEdges) {
    // left -> bottom, before target
    let c3 = { bar: { islands: {
      left:  { left: [{id:'n'}], center: [], right: [] },
      bottom:{ left: [{id:'x'},{id:'y'}], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveIslandEntryBetweenEdges(c3, 'left', 'left', 0, 'bottom', 'left', 0, false), true, 'cross-edge before x')
    assertEqual(c3.bar.islands.left.left.length, 0, 'source edge emptied')
    assertEqual(c3.bar.islands.bottom.left.map(e=>e.id).join(','), 'n,x,y', 'dest order n,x,y')
    // same-edge passthrough still identity-safe via generalized fn
    c3 = { bar: { islands: {
      left:  { left: [{id:'a'},{id:'b'}], center: [], right: [] },
      bottom:{ left: [], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveIslandEntryBetweenEdges(c3, 'left', 'left', 0, 'left', 'left', 0, true), false, 'drop on self after == identity')
    assertEqual(c3.bar.islands.left.left.map(e=>e.id).join(','), 'a,b', 'identity preserved')
    // real swap: a after b
    assertEqual(rm.moveIslandEntryBetweenEdges(c3, 'left', 'left', 0, 'left', 'left', 1, true), true, 'a after b swaps')
    assertEqual(c3.bar.islands.left.left.map(e=>e.id).join(','), 'b,a', 'swap applied')
    // append to empty section on other edge (fresh source state)
    c3 = { bar: { islands: {
      left:  { left: [{id:'a'}], center: [], right: [] },
      bottom:{ left: [], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] } } } }
    rm.moveIslandEntryBetweenEdges(c3, 'left', 'left', 0, 'right', 'center', -1, false)
    assertEqual(c3.bar.islands.right.center.map(e=>e.id).join(','), 'a', 'cross-edge append empty')
    // bad index
    assertEqual(rm.moveIslandEntryBetweenEdges(c3, 'left', 'left', 9, 'top', 'left', -1, false), false, 'bad fromIndex false')
  }
  if (rm.moveIslandEntryToBarAt) {
    let c4 = { bar: { layout: { left: [{id:'L1'}] }, islands: { bottom: { left: [{id:'r1'},{id:'r2'}], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] }, left: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveIslandEntryToBarAt(c4, 'bottom', 'left', 1, 'left', 1), true, 'island->bar insert middle')
    assertEqual(c4.bar.islands.bottom.left.map(e=>e.id).join(','), 'r1', 'island lost r2')
    assertEqual(c4.bar.layout.left.map(e=>e.id).join(','), 'L1,r2', 'bar gains r2 at index 1')
    // append when index out of range
    assertEqual(rm.moveIslandEntryToBarAt(c4, 'bottom', 'left', 0, 'right', 7), true, 'overflow index appends')
    let right = c4.bar.layout.right || []
    assertEqual(right.map(e=>e.id).join(','), 'r1', 'appended to right')
    // bad fromIndex
    assertEqual(rm.moveIslandEntryToBarAt(c4, 'bottom', 'left', 5, 'left', 0), false, 'bad island index false')
    // consumes the hidden bar anchor so the widget renders on the bar again
    let c6 = { bar: { layout: { left: [], center: [{id:'clock'}, {id:'r2', __islandAnchor:true}], right: [] },
      islands: { anchorsMigrated: true,
        bottom: { left: [{id:'r2'}], center: [], right: [] },
        top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] },
        left: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveIslandEntryToBarAt(c6, 'bottom', 'left', 0, 'left', -1), true, 'un-anchor move')
    assertEqual(c6.bar.layout.center.map(e=>e.id).join(','), 'clock', 'bar anchor consumed')
    assertEqual(c6.bar.layout.left.map(e=>e.id).join(','), 'r2', 'restored to the left section')
  }
  if (rm.barEntryIndexOfOccurrence) {
    const arr = [{id:'a'},'b',{id:'a'},{id:'c'}]
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'a',0),0,'occurrence 0 of a')
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'a',1),2,'occurrence 1 of a')
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'a',2),-1,'exceeded occurrence')
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'b',0),1,'string entry b')
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'zz',0),-1,'missing name')
    // integrado: insertar después del SEGUNDO 'a' cae en su posición exacta
    let c5 = { bar: { layout: { center: [{id:'a'},'b',{id:'a'}] }, islands: {
      bottom: { left: [{id:'r'}], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] },
      left: { left: [], center: [], right: [] } } } }
    const ent = rm.barLayoutSection(c5, 'center')
    const idx = rm.barEntryIndexOfOccurrence(ent, 'a', 1)
    rm.moveIslandEntryToBarAt(c5, 'bottom', 'left', 0, 'center', idx + 1)
    assertEqual(ent.map(e => typeof e === 'string' ? e : e.id).join(','), 'a,b,a,r', 'lands after second a')
    assertEqual(c5.bar.islands.bottom.left.length, 0, 'island emptied')
  }
  if (rm.moveIslandEntryAt) {
    // REGRESSION: duplicate ids made name-based drops land on the wrong one.
    // left=[cb,net,a,a], drag net(idx1) after first a(idx2) → [cb,a,net,a]
    c = { bar: { islands: { top: {
      left: [{id:'cb'}, {id:'net'}, {id:'a'}, {id:'a'}],
      center: [], right: []
    } } } }
    assertEqual(rm.moveIslandEntryAt(c, 'top', 'left', 1, 'left', 2, true), true,
      'moveIslandEntryAt net after first duplicate audio')
    ids = c.bar.islands.top.left.map(e => e.id).join(',')
    assertEqual(ids, 'cb,a,net,a', 'duplicate-id one-step move lands between the two')
    // before variant: drag a(idx3) before net(idx1) → [cb,a,net,a] identity? no:
    c = { bar: { islands: { top: {
      left: [{id:'x'}, {id:'m'}, {id:'n'}], center: [], right: []
    } } } }
    assertEqual(rm.moveIslandEntryAt(c, 'top', 'left', 2, 'left', 0, false), true, 'before idx0')
    assertEqual(c.bar.islands.top.left.map(e => e.id).join(','), 'n,x,m', 'insert at head shifts')
    // onto itself → identity
    c = freshConfig()
    assertEqual(rm.moveIslandEntryAt(c, 'bottom', 'left', 0, 'left', 0, true), false, 'self target identity')
    assertEqual(c.bar.islands.bottom.left.length, 3, 'identity keeps entries')
    // append to empty section via placeholder (targetIndex -1)
    c = { bar: { islands: { bottom: {
      left: [{id:'a'}], center: [], right: []
    } } } }
    assertEqual(rm.moveIslandEntryAt(c, 'bottom', 'left', 0, 'right', -1, false), true, 'placeholder append to empty right')
    assertEqual(c.bar.islands.bottom.right[0].id, 'a', 'empty section gains entry')
    // out-of-range source index
    c = freshConfig()
    assertEqual(rm.moveIslandEntryAt(c, 'bottom', 'left', 9, 'center', 0, false), false, 'bad fromIndex rejected')
  }
  }
}

JS

pass "islands model"
