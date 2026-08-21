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
  assertEqual(cfg.enabled, false, 'normalize undefined -> disabled')
  cfg = normalizeFn({ enabled: true, top: { left: [{ id: 'omarchy.tray' }] } }, 'top')
  assertEqual(cfg.rails.top.left[0].id, 'omarchy.tray', 'bar.rails direct top.left')
  // inline pinned preserved
  cfg = normalizeFn({ enabled: true, bottom: { right: [{ id: 'omarchy.audio', pinned: true }] } }, 'top')
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
  }
}

JS

pass "rails model"
