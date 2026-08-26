#!/usr/bin/env bash
# run-upstream.sh — option C (ponytail): does not copy tests, runs them by
# overlaying this repo onto a temporary upstream checkout.
#
# Usage:
#   test/run-upstream.sh                      # run relevant bar suite
#   test/run-upstream.sh test/shell.d/bar-test.sh  # run a single test
#   OMARCHY_SRC=/path/to/omarchy test/run-upstream.sh
#   KEEP_TMP=1 test/run-upstream.sh           # keep /tmp for debugging
#
# Requires: bash, node, rg, jq (for upstream tests). Quickshell optional.
# When run without a compositor, tests that require Quickshell are skipped automatically.

set -euo pipefail

FRAME_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# 1) Locate upstream checkout
OMARCHY_SRC="${OMARCHY_SRC:-}"
if [[ -z "$OMARCHY_SRC" ]]; then
  # prefer ../omarchy if it exists (dev layout fe1ix), then upstream remote
  if [[ -d "$FRAME_ROOT/../omarchy/test/shell.d" ]]; then
    OMARCHY_SRC="$(cd "$FRAME_ROOT/../omarchy" && pwd)"
  else
    # fallback: clone from `upstream` remote to tmp and use as src
    OMARCHY_SRC=""
  fi
fi

TMPDIR=""
cleanup() {
  if [[ -n "${KEEP_TMP:-}" ]]; then
    echo "KEEP_TMP: keeping TMP at $TMPDIR" >&2
    return
  fi
  [[ -n "$TMPDIR" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

if [[ -n "$OMARCHY_SRC" && -d "$OMARCHY_SRC" ]]; then
  TMPDIR="$(mktemp -d)"
  # Efficient checkout copy (exclude .git to save space)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='.git' --exclude='.venv' --exclude='result' "$OMARCHY_SRC/" "$TMPDIR/"
  else
    cp -a "$OMARCHY_SRC" "$TMPDIR/omarchy"
    # cp -a with different folder: move contents to TMPDIR
    if [[ -d "$TMPDIR/omarchy" ]]; then
      shopt -s dotglob
      mv "$TMPDIR/omarchy"/* "$TMPDIR/" 2>/dev/null || true
      mv "$TMPDIR/omarchy"/.* "$TMPDIR/" 2>/dev/null || true
      rmdir "$TMPDIR/omarchy" 2>/dev/null || true
      shopt -u dotglob
    fi
  fi
  # Re-create minimal .git so tests that invoke git (few) do not fail
  mkdir -p "$TMPDIR/.git"
else
  # Without local checkout: shallow clone from upstream remote
  remote_url="$(git -C "$FRAME_ROOT" config --get remote.upstream.url 2>/dev/null || echo "https://github.com/basecamp/omarchy.git")"
  TMPDIR="$(mktemp -d)"
  echo "Cloning upstream $remote_url (quattro) to $TMPDIR ..." >&2
  git clone --depth 1 --branch quattro "$remote_url" "$TMPDIR" 2>&1 | tail -n 5
fi

# 2) Overlay this repo (bar-only) onto the temporary checkout
echo "Overlay frame -> $TMPDIR/shell/plugins/bar" >&2
mkdir -p "$TMPDIR/shell/plugins/bar"
# Required files (always exist) — Bar.qml verbatim upstream, never edited
cp -f "$FRAME_ROOT/Bar.qml" "$TMPDIR/shell/plugins/bar/Bar.qml"
cp -f "$FRAME_ROOT/BarModel.js" "$TMPDIR/shell/plugins/bar/BarModel.js"
# Wrapper + islands model (entry point is WidgetIslandsBar.qml, not Bar.qml)
for f in WidgetIslandsBar.qml IslandModel.js; do
  [[ -f "$FRAME_ROOT/$f" ]] && cp -f "$FRAME_ROOT/$f" "$TMPDIR/shell/plugins/bar/$f"
done
# Islands/ subdir if it exists (WidgetIslandsBar.qml expects it at Islands/)
if [[ -d "$FRAME_ROOT/Islands" ]]; then
  mkdir -p "$TMPDIR/shell/plugins/bar/Islands"
  cp -f "$FRAME_ROOT/Islands"/* "$TMPDIR/shell/plugins/bar/Islands/" 2>/dev/null || true
fi
# Widgets/indicators if touched in frame (keep upstream otherwise)
if [[ -d "$FRAME_ROOT/widgets" ]]; then
  # only overlay files that exist in frame (do not delete others from upstream)
  for w in "$FRAME_ROOT"/widgets/*; do
    [[ -e "$w" ]] && cp -f "$w" "$TMPDIR/shell/plugins/bar/widgets/" 2>/dev/null || cp -f "$w" "$TMPDIR/shell/plugins/bar/widgets/$(basename "$w")"
  done
fi
if [[ -d "$FRAME_ROOT/indicators" ]]; then
  for i in "$FRAME_ROOT"/indicators/*; do
    [[ -e "$i" ]] && cp -f "$i" "$TMPDIR/shell/plugins/bar/indicators/" 2>/dev/null || true
  done
fi

# 3) Choose which tests to run
# Minimal bar-relevant suite (without copying files, we read them from TMP).
# Note: bar-icon-geometry and config-test fail without compositor/fonts/pkgs — run explicitly, not in default.
# Add here if upstream adds bar tests.
DEFAULT_TESTS=(
  "test/shell.d/bar-test.sh"
  "test/shell.d/bar-widget-contract-test.sh"
  "test/shell.d/bar-text-color-test.sh"
  "test/shell.d/border-geometry-test.sh"
  "test/shell.d/plugin-validate-test.sh"
  "test/shell.d/plugins-test.sh"
)

if [[ $# -gt 0 ]]; then
  TESTS=("$@")
else
  TESTS=("${DEFAULT_TESTS[@]}")
fi

# 4) Execute
FAILED=()
PASSED=()
export ROOT="$TMPDIR"
export OMARCHY_PATH="$TMPDIR"

echo "ROOT=$ROOT  OMARCHY_PATH=$OMARCHY_PATH" >&2
echo "Tests: ${TESTS[*]}" >&2
echo "" >&2

for t in "${TESTS[@]}"; do
  # allow both TMP-relative and frame-relative paths
  candidate="$TMPDIR/$t"
  if [[ ! -f "$candidate" && -f "$FRAME_ROOT/$t" ]]; then
    candidate="$FRAME_ROOT/$t"
  fi
  if [[ ! -f "$candidate" ]]; then
    # if the test does not exist upstream (e.g. local islands-test.sh), run it directly with ROOT=FRAME_ROOT
    if [[ -f "$FRAME_ROOT/$t" ]]; then
      echo "==> $t (local, ROOT=$FRAME_ROOT)" >&2
      if ROOT="$FRAME_ROOT" OMARCHY_PATH="$FRAME_ROOT" bash "$FRAME_ROOT/$t"; then
        PASSED+=("$t")
      else
        FAILED+=("$t")
      fi
      continue
    fi
    echo "skip - $t (does not exist upstream)" >&2
    continue
  fi
  echo "==> $t" >&2
  if bash "$candidate"; then
    PASSED+=("$t")
  else
    FAILED+=("$t")
  fi
  echo "" >&2
done

echo "----------------------------------------" >&2
echo "Passed: ${#PASSED[@]}/${#TESTS[@]}  Failed: ${#FAILED[@]}" >&2
if (( ${#PASSED[@]} > 0 )); then
  printf '  ok: %s\n' "${PASSED[@]}" >&2
fi
if (( ${#FAILED[@]} > 0 )); then
  printf '  not ok: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
