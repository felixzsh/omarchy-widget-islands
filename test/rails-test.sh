#!/usr/bin/env bash
# rails-test.sh — Rails-specific tests (not upstream).
# Validates RailModel.js when present.
# Run with:  test/rails-test.sh   or   test/run-upstream.sh test/rails-test.sh

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

# If RailModel.js does not exist yet, skip informatively
for check in "$FRAME_ROOT/RailModel.js" "$ROOT/shell/plugins/bar/RailModel.js"; do
  if [[ -f "$check" ]]; then found=1; break; fi
done
if [[ -z "${found:-}" ]]; then
  pass "RailModel.js does not exist yet — skip rails-test (MVP pending)"
  exit 0
fi

run_node_test <<'JS'
const fs = require('fs')

// Resolve RailModel from rails or overlay
let railPath = null
for (const cand of [
  path.join(process.env.ROOT, 'shell/plugins/bar/RailModel.js'),
  path.join(process.env.ROOT, '../omarchy-frame/RailModel.js'),
  path.join(path.join(process.env.ROOT || '', '../omarchy-frame/RailModel.js')),
]) {
  if (fs.existsSync(cand)) { railPath = cand; break }
}
if (!railPath) {
  const alt = path.join(process.env.ROOT || '', 'RailModel.js')
  if (fs.existsSync(alt)) railPath = alt
}
if (!railPath) {
  console.log('ok - RailModel.js not found, skip')
  process.exit(0)
}

const src = fs.readFileSync(railPath, 'utf8')
// RailModel is plain JS (no pragma), evaluate in vm
const vm = require('vm')
const ctx = { module: { exports: {} }, exports: {}, console }
vm.createContext(ctx)
const clean = src.replace(/^\s*\.pragma library\s*\n/m, '')
vm.runInContext(clean, ctx)
const rm = ctx.module.exports || ctx

const normalizeFn = rm.normalizeRailsConfig
if (typeof rm.railThickness !== 'function' && typeof normalizeFn !== 'function') {
  console.log('ok - RailModel has no testable API yet (WIP)')
  process.exit(0)
}

// --- Concrete tests (enabled when you implement RailModel) ---
if (typeof rm.railThickness === 'function') {
  assertEqual(rm.railThickness(26), 9, 'railThickness 26 -> ~9 (1/3)')
  assertEqual(rm.railThickness(28), 9, 'railThickness 28 -> ~9 (1/3)')
  assert(rm.railThickness(6) >= 4, 'railThickness clamps to minimum 4')
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
  assertEqual(cfg.rails.top.left.length, 0, 'normalize undefined -> zero-config empty rails')
  assertEqual(cfg.trigger, 'hover', 'normalize undefined -> default trigger hover')
  assert(cfg.enabled === undefined, 'no enabled flag in output')
  // legacy explicit enabled:false is ignored entirely
  cfg = normalizeFn({ enabled: false, bottom: { left: [{ id: 'x' }] } }, 'top')
  assertEqual(cfg.rails.bottom.left[0].id, 'x', 'legacy enabled:false ignored')
  cfg = normalizeFn({ top: { left: [{ id: 'omarchy.tray' }] } }, 'top')
  assertEqual(cfg.rails.top.left[0].id, 'omarchy.tray', 'bar.rails direct top.left')
  // inline pinned preserved
  cfg = normalizeFn({ bottom: { right: [{ id: 'omarchy.audio', pinned: true }] } }, 'top')
  let entry = cfg.rails.bottom.right[0]
  assertEqual(entry.id, 'omarchy.audio', 'rails preserves id')
  assertEqual(entry.pinned, true, 'rails preserves pinned:true')
  // dots per section: hasAnyWidgets and sectionHasWidgets (if present)
  if (typeof rm.hasAnyWidgets === 'function') {
    assertEqual(rm.hasAnyWidgets({ left: [{id:'a'}], center: [], right: [] }), true, 'hasAnyWidgets true if any section has widgets')
    assertEqual(rm.hasAnyWidgets({ left: [], center: [], right: [] }), false, 'hasAnyWidgets false if empty')
  }
  if (typeof rm.sectionHasWidgets === 'function') {
    assertEqual(rm.sectionHasWidgets({ left: [{id:'a'}], center: [], right: [] }, 'left'), true, 'sectionHasWidgets left true')
    assertEqual(rm.sectionHasWidgets({ left: [{id:'a'}], center: [], right: [] }, 'center'), false, 'sectionHasWidgets center false')
  }

  // 3.6 — moveRailEntry (intra-rail drag & drop persistence)
  function freshConfig() {
    return { bar: { rails: { bottom: {
      left: [{id:'a'}, {id:'b'}, {id:'c'}],
      center: [{id:'x'}],
      right: []
    } } } }
  }
  if (rm.moveRailEntry) {
    // same-section reorder forward
    let c = freshConfig()
    assertEqual(rm.moveRailEntry(c, 'bottom', 'left', 'a', 'left', 'c'), true, 'move a before c')
    let ids = c.bar.rails.bottom.left.map(e => e.id).join(',')
    assertEqual(ids, 'b,a,c', 'left order after move a before c')
    // same-section no-op (b before c == already there)
    c = freshConfig()
    assertEqual(rm.moveRailEntry(c, 'bottom', 'left', 'b', 'left', 'c'), false, 'move b before c is identity')
    ids = c.bar.rails.bottom.left.map(e => e.id).join(',')
    assertEqual(ids, 'a,b,c', 'identity leaves order untouched')
    // same-section real swap
    c = freshConfig()
    assertEqual(rm.moveRailEntry(c, 'bottom', 'left', 'b', 'left', 'a'), true, 'move b before a swaps')
    assertEqual(c.bar.rails.bottom.left.map(e => e.id).join(','), 'b,a,c', 'swap applied')
    // cross-section before target
    c = freshConfig()
    assertEqual(rm.moveRailEntry(c, 'bottom', 'left', 'a', 'center', 'x'), true, 'move a to center before x')
    assertEqual(c.bar.rails.bottom.left.map(e => e.id).join(','), 'b,c', 'source section loses a')
    assertEqual(c.bar.rails.bottom.center.map(e => e.id).join(','), 'a,x', 'center gains a before x')
    // cross-section append (beforeName empty)
    c = freshConfig()
    rm.moveRailEntry(c, 'bottom', 'left', 'b', 'right', '')
    assertEqual(c.bar.rails.bottom.right.map(e => e.id).join(','), 'b', 'append to empty right')
    // drop after last target → append semantics
    c = freshConfig()
    rm.moveRailEntry(c, 'bottom', 'center', 'x', 'left', '')
    assertEqual(c.bar.rails.bottom.left.map(e => e.id).join(','), 'a,b,c,x', 'x appended to left end')
    // missing widget → false
    c = freshConfig()
    assertEqual(rm.moveRailEntry(c, 'bottom', 'left', 'zz', 'center', ''), false, 'missing id returns false')
  }
  if (rm.moveBarEntryToRail) {
    // bar layout → rail section, before target
    let c2 = { bar: { position: 'top', layout: { left: [{id:'tray'},{id:'net'}] },
      rails: { bottom: { left: [], center: [{id:'x'}], right: [] } } } }
    assertEqual(rm.moveBarEntryToRail(c2, 'net', 'left', 'bottom', 'center', 0, false), true, 'bar->rail before x')
    assertEqual(c2.bar.layout.left.map(e => e.id).join(','), 'tray', 'bar layout loses net')
    assertEqual(c2.bar.rails.bottom.center.map(e => e.id).join(','), 'net,x', 'rail center gains net before x')
    // append to empty rail section (targetIndex -1)
    c2 = { bar: { layout: { center: [{id:'clock'}] }, rails: { top: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveBarEntryToRail(c2, 'clock', 'center', 'top', 'right', -1, false), true, 'bar->rail append empty')
    assertEqual(c2.bar.rails.top.right.map(e => e.id).join(','), 'clock', 'empty right gains clock')
    // after=true inserts past target
    c2 = { bar: { layout: { right: [{id:'a'}] }, rails: { left: { left: [{id:'p'},{id:'q'}], center: [], right: [] } } } }
    rm.moveBarEntryToRail(c2, 'a', 'right', 'left', 'left', 0, true)
    assertEqual(c2.bar.rails.left.left.map(e => e.id).join(','), 'p,a,q', 'after=true lands past p')
    // preserves entry object shape
    c2 = { bar: { layout: { left: [{id:'aud', pinned: true}] }, rails: { bottom: { left: [], center: [], right: [] } } } }
    rm.moveBarEntryToRail(c2, 'aud', 'left', 'bottom', 'center', -1, false)
    assertEqual(c2.bar.rails.bottom.center[0].pinned, true, 'entry object preserved')
    // missing id
    assertEqual(rm.moveBarEntryToRail({bar:{layout:{left:[]},rails:{}}}, 'nope', 'left', 'top', 'left', -1, false), false, 'bar->rail missing id false')
  }
  if (rm.railReferencedIds) {
    let r = { bottom: { left: [{id:'a'}], center: [{id:'b'},'c'], right: [] },
              left:  { left: [], center: ['a'], right: [{id:'d'}] },
              top: { left: [], center: [], right: [] },
              right: { left: [], center: [], right: [] } }
    let ids = rm.railReferencedIds(r)
    assertEqual(ids.length, 4, 'railReferencedIds dedupes across edges')
    for (const want of ['a','b','c','d']) assert(ids.indexOf(want) !== -1, 'contains ' + want)
    assertEqual(rm.railReferencedIds({}).length, 0, 'empty rails -> empty ids')
    assertEqual(rm.railReferencedIds(null).length, 0, 'null rails -> empty ids')
  }
  if (rm.pruneRailGhosts) {
    let g1 = { bar: { rails: {
      bottom: { left: [{id:'ghost1'}, {id:'alive'}], center: ['ghost2'], right: [] },
      top: { left: [], center: [], right: [] },
      left: { left: [], center: [], right: [] },
      right: { left: [{id:'ghost1'}], center: [{id:'kept'}], right: [] } } } }
    assertEqual(rm.pruneRailGhosts(g1, ['ghost1', 'ghost2']), true, 'prune returns changed')
    assertEqual(g1.bar.rails.bottom.left.map(e => e.id).join(','), 'alive', 'mixed section keeps alive')
    assertEqual(g1.bar.rails.bottom.center.length, 0, 'string ghost removed')
    assertEqual(g1.bar.rails.right.left.length, 0, 'same ghost across edges removed')
    assertEqual(g1.bar.rails.right.center[0].id, 'kept', 'unlisted kept')
    assertEqual(rm.pruneRailGhosts(g1, ['ghost1', 'ghost2']), false, 'second prune no-op')
    let g2 = { bar: { rails: { bottom: { left: [{id:'omarchy.indicators'}], center: [], right: [] },
      top: { left: [], center: [], right: [] }, left: { left: [], center: [], right: [] },
      right: { left: [], center: [], right: [] } } } }
    assertEqual(rm.pruneRailGhosts(g2, ['ghost1']), false, 'built-in-like id untouched when not listed')
    let g3 = { bar: { rails: { bottom: { left: [{id:'gone', pinned:true}, {id:'stay', format:'x'}], center: [], right: [] },
      top: { left: [], center: [], right: [] }, left: { left: [], center: [], right: [] },
      right: { left: [], center: [], right: [] } } } }
    rm.pruneRailGhosts(g3, ['gone'])
    assertEqual(g3.bar.rails.bottom.left.length, 1, 'only ghost removed')
    assertEqual(g3.bar.rails.bottom.left[0].format, 'x', 'survivor settings intact')
  }
  if (rm.ensurePluginsEnabled) {
    let e1 = { version: 1 }
    assertEqual(rm.ensurePluginsEnabled(e1, ['akshar.radio-atlas', 'felixzsh.codexbar']), true, 'adds missing plugins list')
    assertEqual(Array.isArray(e1.plugins), true, 'plugins array created')
    assertEqual(e1.plugins.length, 2, 'two ids added')
    assertEqual(e1.plugins[0].id, 'akshar.radio-atlas', 'entry shape {id}')
    // idempotente
    assertEqual(rm.ensurePluginsEnabled(e1, ['akshar.radio-atlas']), false, 'existing id no-op')
    assertEqual(e1.plugins.length, 2, 'no duplicates')
    // preserva entradas existentes; el host exige {id} en plugins[], así que
    // una entrada string cruda cuenta como ausente y se añade normalizada
    let e2 = { plugins: [{ id: 'a' }, 'b'] }
    assertEqual(rm.ensurePluginsEnabled(e2, ['a', 'b', 'c']), true, 'adds missing (string b normalized)')
    assertEqual(e2.plugins.length, 4, 'a, b(string), b{id}, c')
    assertEqual(e2.plugins[2].id, 'b', 'string entry normalized to {id}')
    assertEqual(e2.plugins[3].id, 'c', 'appended at end')
    // null config safe
    assertEqual(rm.ensurePluginsEnabled(null, ['x']), false, 'null config false')
    assertEqual(rm.ensurePluginsEnabled({}, []), false, 'empty ids false')
  }
  if (rm.railReconcilePlan) {
    // REGRESIÓN (el caso que rompió el fix anterior): plugin desinstalado
    // pero con su id aún en config.plugins → isEnabled() devuelve TRUE
    // (envenenado por la entrada fantasma). El plan debe PODARLO igual.
    let p1 = rm.railReconcilePlan(
      ['akshar.radio-atlas'],
      {},                                                    // no instalado
      function() { return false },                           // no en registry
      function() { return true })                            // isEnabled envenenado = true
    assertEqual(p1.ghosts.indexOf('akshar.radio-atlas') !== -1, true, 'REGRESSION: uninstalled-but-in-plugins[] still pruned')
    // instalado + no-enabled → toEnable
    let p2 = rm.railReconcilePlan(['felixzsh.codexbar'],
      { 'felixzsh.codexbar': { id: 'felixzsh.codexbar' } },
      function() { return false },
      function() { return false })
    assertEqual(p2.toEnable.length, 1, 'installed not-enabled -> toEnable')
    assertEqual(p2.ghosts.length, 0, 'no ghosts for installed')
    // instalado + enabled → nada
    let p3 = rm.railReconcilePlan(['felixzsh.codexbar'],
      { 'felixzsh.codexbar': {} },
      function() { return true },
      function() { return true })
    assertEqual(p3.toEnable.length + p3.ghosts.length, 0, 'installed enabled -> no-op')
    // built-in: no instalado pero SÍ en registry → nada
    let p4 = rm.railReconcilePlan(['omarchy.indicators'],
      {},
      function(id) { return id === 'omarchy.indicators' },
      function() { return false })
    assertEqual(p4.ghosts.length, 0, 'built-in in registry never ghosted')
    // uninstalled sin registry → ghost
    let p5 = rm.railReconcilePlan(['dead.plugin'],
      {},
      function() { return false },
      function() { return false })
    assertEqual(p5.ghosts.indexOf('dead.plugin') !== -1, true, 'plain uninstall ghosted')
  }
  if (rm.prunePluginsEnabled) {
    let pl1 = { plugins: [{ id: 'a' }, { id: 'dead' }, 'rawstring'] }
    assertEqual(rm.prunePluginsEnabled(pl1, ['dead']), true, 'prune removes stale marker')
    assertEqual(pl1.plugins.length, 2, 'keeps others')
    assertEqual(pl1.plugins[0].id, 'a', 'survivor intact')
    assertEqual(pl1.plugins[1], 'rawstring', 'raw strings untouched')
    assertEqual(rm.prunePluginsEnabled(pl1, ['nope']), false, 'no-op when absent')
    assertEqual(rm.prunePluginsEnabled({}, ['a']), false, 'missing list no-op')
  }
  if (rm.moveRailEntryBetweenEdges) {
    // left -> bottom, before target
    let c3 = { bar: { rails: {
      left:  { left: [{id:'n'}], center: [], right: [] },
      bottom:{ left: [{id:'x'},{id:'y'}], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveRailEntryBetweenEdges(c3, 'left', 'left', 0, 'bottom', 'left', 0, false), true, 'cross-edge before x')
    assertEqual(c3.bar.rails.left.left.length, 0, 'source edge emptied')
    assertEqual(c3.bar.rails.bottom.left.map(e=>e.id).join(','), 'n,x,y', 'dest order n,x,y')
    // same-edge passthrough still identity-safe via generalized fn
    c3 = { bar: { rails: {
      left:  { left: [{id:'a'},{id:'b'}], center: [], right: [] },
      bottom:{ left: [], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveRailEntryBetweenEdges(c3, 'left', 'left', 0, 'left', 'left', 0, true), false, 'drop on self after == identity')
    assertEqual(c3.bar.rails.left.left.map(e=>e.id).join(','), 'a,b', 'identity preserved')
    // real swap: a after b
    assertEqual(rm.moveRailEntryBetweenEdges(c3, 'left', 'left', 0, 'left', 'left', 1, true), true, 'a after b swaps')
    assertEqual(c3.bar.rails.left.left.map(e=>e.id).join(','), 'b,a', 'swap applied')
    // append to empty section on other edge (fresh source state)
    c3 = { bar: { rails: {
      left:  { left: [{id:'a'}], center: [], right: [] },
      bottom:{ left: [], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] } } } }
    rm.moveRailEntryBetweenEdges(c3, 'left', 'left', 0, 'right', 'center', -1, false)
    assertEqual(c3.bar.rails.right.center.map(e=>e.id).join(','), 'a', 'cross-edge append empty')
    // bad index
    assertEqual(rm.moveRailEntryBetweenEdges(c3, 'left', 'left', 9, 'top', 'left', -1, false), false, 'bad fromIndex false')
  }
  if (rm.moveRailEntryToBarAt) {
    let c4 = { bar: { layout: { left: [{id:'L1'}] }, rails: { bottom: { left: [{id:'r1'},{id:'r2'}], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] }, left: { left: [], center: [], right: [] } } } }
    assertEqual(rm.moveRailEntryToBarAt(c4, 'bottom', 'left', 1, 'left', 1), true, 'rail->bar insert middle')
    assertEqual(c4.bar.rails.bottom.left.map(e=>e.id).join(','), 'r1', 'rail lost r2')
    assertEqual(c4.bar.layout.left.map(e=>e.id).join(','), 'L1,r2', 'bar gains r2 at index 1')
    // append when index out of range
    assertEqual(rm.moveRailEntryToBarAt(c4, 'bottom', 'left', 0, 'right', 7), true, 'overflow index appends')
    let right = c4.bar.layout.right || []
    assertEqual(right.map(e=>e.id).join(','), 'r1', 'appended to right')
    // bad fromIndex
    assertEqual(rm.moveRailEntryToBarAt(c4, 'bottom', 'left', 5, 'left', 0), false, 'bad rail index false')
  }
  if (rm.barEntryIndexOfOccurrence) {
    const arr = [{id:'a'},'b',{id:'a'},{id:'c'}]
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'a',0),0,'occurrence 0 of a')
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'a',1),2,'occurrence 1 of a')
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'a',2),-1,'exceeded occurrence')
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'b',0),1,'string entry b')
    assertEqual(rm.barEntryIndexOfOccurrence(arr,'zz',0),-1,'missing name')
    // integrado: insertar después del SEGUNDO 'a' cae en su posición exacta
    let c5 = { bar: { layout: { center: [{id:'a'},'b',{id:'a'}] }, rails: {
      bottom: { left: [{id:'r'}], center: [], right: [] },
      top: { left: [], center: [], right: [] }, right: { left: [], center: [], right: [] },
      left: { left: [], center: [], right: [] } } } }
    const ent = rm.barLayoutSection(c5, 'center')
    const idx = rm.barEntryIndexOfOccurrence(ent, 'a', 1)
    rm.moveRailEntryToBarAt(c5, 'bottom', 'left', 0, 'center', idx + 1)
    assertEqual(ent.map(e => typeof e === 'string' ? e : e.id).join(','), 'a,b,a,r', 'lands after second a')
    assertEqual(c5.bar.rails.bottom.left.length, 0, 'rail emptied')
  }
  if (rm.moveRailEntryAt) {
    // REGRESSION: duplicate ids made name-based drops land on the wrong one.
    // left=[cb,net,a,a], drag net(idx1) after first a(idx2) → [cb,a,net,a]
    c = { bar: { rails: { top: {
      left: [{id:'cb'}, {id:'net'}, {id:'a'}, {id:'a'}],
      center: [], right: []
    } } } }
    assertEqual(rm.moveRailEntryAt(c, 'top', 'left', 1, 'left', 2, true), true,
      'moveRailEntryAt net after first duplicate audio')
    ids = c.bar.rails.top.left.map(e => e.id).join(',')
    assertEqual(ids, 'cb,a,net,a', 'duplicate-id one-step move lands between the two')
    // before variant: drag a(idx3) before net(idx1) → [cb,a,net,a] identity? no:
    c = { bar: { rails: { top: {
      left: [{id:'x'}, {id:'m'}, {id:'n'}], center: [], right: []
    } } } }
    assertEqual(rm.moveRailEntryAt(c, 'top', 'left', 2, 'left', 0, false), true, 'before idx0')
    assertEqual(c.bar.rails.top.left.map(e => e.id).join(','), 'n,x,m', 'insert at head shifts')
    // onto itself → identity
    c = freshConfig()
    assertEqual(rm.moveRailEntryAt(c, 'bottom', 'left', 0, 'left', 0, true), false, 'self target identity')
    assertEqual(c.bar.rails.bottom.left.length, 3, 'identity keeps entries')
    // append to empty section via placeholder (targetIndex -1)
    c = { bar: { rails: { bottom: {
      left: [{id:'a'}], center: [], right: []
    } } } }
    assertEqual(rm.moveRailEntryAt(c, 'bottom', 'left', 0, 'right', -1, false), true, 'placeholder append to empty right')
    assertEqual(c.bar.rails.bottom.right[0].id, 'a', 'empty section gains entry')
    // out-of-range source index
    c = freshConfig()
    assertEqual(rm.moveRailEntryAt(c, 'bottom', 'left', 9, 'center', 0, false), false, 'bad fromIndex rejected')
  }
  }
}

JS

pass "rails model"
