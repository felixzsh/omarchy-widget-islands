#!/usr/bin/env bash
# rails-test.sh — tests propios de Rails (no upstream).
# Valida RailModel.js (y FrameModel.js como compat) cuando exista.
# Corre con:  test/rails-test.sh   o   test/run-upstream.sh test/rails-test.sh
# Mantiene compat con bar.frame (viejo) y bar.rails (nuevo).

set -euo pipefail

FRAME_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# ROOT para node harness: si viene de run-upstream.sh ya está en TMP, sino frame
ROOT="${ROOT:-$FRAME_ROOT}"
export ROOT

# Reusa harness de upstream (pass/fail/assert) si existe, si no define local
if [[ -f "$ROOT/test/shell.d/base-test.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/test/shell.d/base-test.sh"
else
  # fallback minimal cuando se corre aislado sin checkout upstream
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

# Si RailModel.js/FrameModel.js no existe aún, skip informativo
for check in "$FRAME_ROOT/RailModel.js" "$FRAME_ROOT/FrameModel.js" "$ROOT/shell/plugins/bar/RailModel.js" "$ROOT/shell/plugins/bar/FrameModel.js"; do
  if [[ -f "$check" ]]; then found=1; break; fi
done
if [[ -z "${found:-}" ]]; then
  pass "RailModel.js/FrameModel.js aún no existe — skip rails-test (MVP pendiente)"
  exit 0
fi

run_node_test <<'JS'
const fs = require('fs')

// Resolver RailModel (nuevo) o FrameModel (compat) desde rails o overlay
let frame = null
let framePath = null
for (const cand of [
  path.join(process.env.ROOT, 'shell/plugins/bar/RailModel.js'),
  path.join(process.env.ROOT, 'shell/plugins/bar/FrameModel.js'),
  path.join(process.env.ROOT, '../omarchy-frame/RailModel.js'),
  path.join(process.env.ROOT, '../omarchy-frame/FrameModel.js'),
  path.join(path.join(process.env.ROOT || '', '../omarchy-frame/RailModel.js')),
]) {
  if (fs.existsSync(cand)) { framePath = cand; break }
}
if (!framePath) {
  const alt1 = path.join(process.env.ROOT || '', 'RailModel.js')
  const alt2 = path.join(process.env.ROOT || '', 'FrameModel.js')
  if (fs.existsSync(alt1)) framePath = alt1
  else if (fs.existsSync(alt2)) framePath = alt2
}
if (!framePath) {
  console.log('ok - RailModel.js/FrameModel.js no encontrado, skip')
  process.exit(0)
}

const src = fs.readFileSync(framePath, 'utf8')
// RailModel es plain JS (no pragma), evaluar en vm
const vm = require('vm')
const ctx = { module: { exports: {} }, exports: {}, console }
vm.createContext(ctx)
const clean = src.replace(/^\s*\.pragma library\s*\n/m, '')
vm.runInContext(clean, ctx)
const fm = ctx.module.exports || ctx

// Compat: normalizeRailsConfig es el nuevo, normalizeFrameConfig el viejo alias
const normalizeFn = fm.normalizeRailsConfig || fm.normalizeFrameConfig
if (typeof fm.railThickness !== 'function' && typeof normalizeFn !== 'function') {
  console.log('ok - RailModel sin API testeable aún (WIP)')
  process.exit(0)
}

// --- Tests concretos (se activan cuando implementes FrameModel) ---
if (typeof fm.railThickness === 'function') {
  assertEqual(fm.railThickness(26), 9, 'railThickness 26 -> ~9 (1/3)')
  assertEqual(fm.railThickness(28), 9, 'railThickness 28 -> ~9 (1/3)')
  assert(fm.railThickness(6) >= 4, 'railThickness clampa a mínimo 4')
}

if (typeof fm.isPinned === 'function' && typeof fm.setPinned === 'function') {
  assertEqual(fm.isPinned({ id: 'a' }), false, 'isPinned default false')
  assertEqual(fm.isPinned({ id: 'a', pinned: true }), true, 'isPinned true')
  assertEqual(fm.isPinned({ id: 'a', pinned: false }), false, 'isPinned false explícito')
  const e = { id: 'x' }
  const pinned = fm.setPinned(e, true)
  assertEqual(pinned.pinned, true, 'setPinned true añade key')
  assertEqual(e.pinned, undefined, 'setPinned no muta original')
  assertEqual(fm.setPinned({ id: 'x', pinned: true }, false).pinned, undefined, 'setPinned false limpia key')
}

if (typeof normalizeFn === 'function') {
  let bar = null
  for (const bp of [path.join(process.env.ROOT, 'shell/plugins/bar/BarModel.js'), path.join(process.env.ROOT, 'BarModel.js'), path.join(process.env.ROOT, '../BarModel.js')]) {
    try { bar = require(bp); break } catch (e) {}
  }
  if (!bar) { console.log('ok - BarModel no encontrado, skip normalize checks'); } else {
  // deshabilitado -> rails vacíos (nuevo bar.rails y viejo bar.frame)
  let cfg = normalizeFn(undefined, 'top')
  assertEqual(cfg.enabled, false, 'normalize undefined -> disabled')
  cfg = normalizeFn({ enabled: true, rails: {} }, 'top')
  assertEqual(typeof cfg.rails.top, 'object', 'rails.top declarado aunque sea main (viejo bar.frame)')
  assertEqual(typeof cfg.rails.bottom, 'object', 'rails.bottom declarado')
  // nuevo shape bar.rails directo: {enabled, top:{...}} sin anidar rails
  cfg = normalizeFn({ enabled: true, top: { left: [{ id: 'omarchy.tray' }] } }, 'top')
  assertEqual(cfg.rails.top.left[0].id, 'omarchy.tray', 'nuevo bar.rails directo top.left')
  // pinned inline preservado en ambos shapes
  cfg = normalizeFn({ enabled: true, rails: { bottom: { right: [{ id: 'omarchy.audio', pinned: true }] } } }, 'top')
  let entry = cfg.rails.bottom.right[0]
  assertEqual(entry.id, 'omarchy.audio', 'rails preserva id (viejo)')
  assertEqual(entry.pinned, true, 'rails preserva pinned:true (viejo)')
  cfg = normalizeFn({ enabled: true, bottom: { right: [{ id: 'omarchy.audio', pinned: true }] } }, 'top')
  entry = cfg.rails.bottom.right[0]
  assertEqual(entry.pinned, true, 'rails preserva pinned:true (nuevo)')
  // dots por sección: hasAnyWidgets y sectionHasWidgets (si existe)
  if (typeof fm.hasAnyWidgets === 'function') {
    assertEqual(fm.hasAnyWidgets({ left: [{id:'a'}], center: [], right: [] }), true, 'hasAnyWidgets true si alguna sección con widgets')
    assertEqual(fm.hasAnyWidgets({ left: [], center: [], right: [] }), false, 'hasAnyWidgets false si vacío')
  }
  if (typeof fm.sectionHasWidgets === 'function') {
    assertEqual(fm.sectionHasWidgets({ left: [{id:'a'}], center: [], right: [] }, 'left'), true, 'sectionHasWidgets left true')
    assertEqual(fm.sectionHasWidgets({ left: [{id:'a'}], center: [], right: [] }, 'center'), false, 'sectionHasWidgets center false')
  }
  }
}

JS

pass "rails model"
