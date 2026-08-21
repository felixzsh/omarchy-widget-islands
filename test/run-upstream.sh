#!/usr/bin/env bash
# run-upstream.sh — opción C (ponytail): no copia tests, los ejecuta overlayeando
# este repo sobre un checkout upstream temporal.
#
# Uso:
#   test/run-upstream.sh                      # corre suite bar relevante
#   test/run-upstream.sh test/shell.d/bar-test.sh  # corre solo uno
#   OMARCHY_SRC=/path/to/omarchy test/run-upstream.sh
#   KEEP_TMP=1 test/run-upstream.sh           # deja /tmp para debug
#
# Requiere: bash, node, rg, jq (para los tests upstream). Quickshell opcional.
# Si corre sin compositor, los tests que requieren Quickshell se skippean solos.

set -euo pipefail

FRAME_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# 1) Localizar checkout upstream
OMARCHY_SRC="${OMARCHY_SRC:-}"
if [[ -z "$OMARCHY_SRC" ]]; then
  # preferir ../omarchy si existe (layout dev fe1ix), luego upstream remote
  if [[ -d "$FRAME_ROOT/../omarchy/test/shell.d" ]]; then
    OMARCHY_SRC="$(cd "$FRAME_ROOT/../omarchy" && pwd)"
  else
    # fallback: clonar desde remote `upstream` a tmp y usarlo como src
    OMARCHY_SRC=""
  fi
fi

TMPDIR=""
cleanup() {
  if [[ -n "${KEEP_TMP:-}" ]]; then
    echo "KEEP_TMP: dejando TMP en $TMPDIR" >&2
    return
  fi
  [[ -n "$TMPDIR" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

if [[ -n "$OMARCHY_SRC" && -d "$OMARCHY_SRC" ]]; then
  TMPDIR="$(mktemp -d)"
  # Copia eficiente del checkout (excluye .git para ahorrar)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='.git' --exclude='.venv' --exclude='result' "$OMARCHY_SRC/" "$TMPDIR/"
  else
    cp -a "$OMARCHY_SRC" "$TMPDIR/omarchy"
    # cp -a con carpeta distinta: mover contenido a TMPDIR
    if [[ -d "$TMPDIR/omarchy" ]]; then
      shopt -s dotglob
      mv "$TMPDIR/omarchy"/* "$TMPDIR/" 2>/dev/null || true
      mv "$TMPDIR/omarchy"/.* "$TMPDIR/" 2>/dev/null || true
      rmdir "$TMPDIR/omarchy" 2>/dev/null || true
      shopt -u dotglob
    fi
  fi
  # Re-crear .git mínimo para que tests que invocan git (pocos) no fallen
  mkdir -p "$TMPDIR/.git"
else
  # Sin checkout local: clonar shallow desde upstream remote
  remote_url="$(git -C "$FRAME_ROOT" config --get remote.upstream.url 2>/dev/null || echo "https://github.com/basecamp/omarchy.git")"
  TMPDIR="$(mktemp -d)"
  echo "Clonando upstream $remote_url (quattro) a $TMPDIR ..." >&2
  git clone --depth 1 --branch quattro "$remote_url" "$TMPDIR" 2>&1 | tail -n 5
fi

# 2) Overlay de este repo (bar-only) sobre el checkout temporal
echo "Overlay frame -> $TMPDIR/shell/plugins/bar" >&2
mkdir -p "$TMPDIR/shell/plugins/bar"
# Archivos obligatorios (siempre existen)
cp -f "$FRAME_ROOT/Bar.qml" "$TMPDIR/shell/plugins/bar/Bar.qml"
cp -f "$FRAME_ROOT/BarModel.js" "$TMPDIR/shell/plugins/bar/BarModel.js"
# Opcionales (cuando existan, no fallar si no) — RailModel es el nuevo, FrameModel se mantiene por compat
for f in RailModel.js FrameModel.js RailPanel.qml RailHints.qml MainBarPanel.qml; do
  [[ -f "$FRAME_ROOT/$f" ]] && cp -f "$FRAME_ROOT/$f" "$TMPDIR/shell/plugins/bar/$f"
done
# Rails/ subdir si existe (nuevo Bar.qml lo espera en Rails/)
if [[ -d "$FRAME_ROOT/Rails" ]]; then
  mkdir -p "$TMPDIR/shell/plugins/bar/Rails"
  cp -f "$FRAME_ROOT/Rails"/* "$TMPDIR/shell/plugins/bar/Rails/" 2>/dev/null || true
fi
# Widgets/indicators si fueron tocados en frame (mantener upstream si no)
if [[ -d "$FRAME_ROOT/widgets" ]]; then
  # solo overlayea archivos que existen en frame (no borra otros del upstream)
  for w in "$FRAME_ROOT"/widgets/*; do
    [[ -e "$w" ]] && cp -f "$w" "$TMPDIR/shell/plugins/bar/widgets/" 2>/dev/null || cp -f "$w" "$TMPDIR/shell/plugins/bar/widgets/$(basename "$w")"
  done
fi
if [[ -d "$FRAME_ROOT/indicators" ]]; then
  for i in "$FRAME_ROOT"/indicators/*; do
    [[ -e "$i" ]] && cp -f "$i" "$TMPDIR/shell/plugins/bar/indicators/" 2>/dev/null || true
  done
fi

# 3) Elegir qué tests correr
# Suite mínima bar-relevante (sin copiar archivos, los leemos del TMP).
# Nota: bar-icon-geometry y config-test fallan sin compositor/fuentes/pkgs — corren explícitos, no en default.
# Añade aquí si upstream agrega tests de bar.
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

# 4) Ejecutar
FAILED=()
PASSED=()
export ROOT="$TMPDIR"
export OMARCHY_PATH="$TMPDIR"

echo "ROOT=$ROOT  OMARCHY_PATH=$OMARCHY_PATH" >&2
echo "Tests: ${TESTS[*]}" >&2
echo "" >&2

for t in "${TESTS[@]}"; do
  # permitir tanto rutas relativas al TMP como al frame
  candidate="$TMPDIR/$t"
  if [[ ! -f "$candidate" && -f "$FRAME_ROOT/$t" ]]; then
    candidate="$FRAME_ROOT/$t"
  fi
  if [[ ! -f "$candidate" ]]; then
    # si el test no existe en upstream (ej. rails-test.sh local), correrlo directo con ROOT=FRAME_ROOT
    if [[ -f "$FRAME_ROOT/$t" ]]; then
      echo "==> $t (local, ROOT=$FRAME_ROOT)" >&2
      if ROOT="$FRAME_ROOT" OMARCHY_PATH="$FRAME_ROOT" bash "$FRAME_ROOT/$t"; then
        PASSED+=("$t")
      else
        FAILED+=("$t")
      fi
      continue
    fi
    echo "skip - $t (no existe en upstream)" >&2
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
echo "Pasaron: ${#PASSED[@]}/${#TESTS[@]}  Fallaron: ${#FAILED[@]}" >&2
if (( ${#PASSED[@]} > 0 )); then
  printf '  ok: %s\n' "${PASSED[@]}" >&2
fi
if (( ${#FAILED[@]} > 0 )); then
  printf '  not ok: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
