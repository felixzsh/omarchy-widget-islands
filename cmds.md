# Workflows — omarchy-frame

> `plan.md` is the source of truth for design. This is a command cheatsheet.
> **Golden rule:** `Bar.qml` + `BarModel.js` + `widgets/` + `indicators/` are verbatim upstream and **never edited**. Only `RailsBar.qml`, `RailModel.js`, `Rails/` are touched.

## Setup

```bash
git remote -v  # upstream -> basecamp/omarchy
ls ../omarchy/test/shell.d/bar-test.sh  # sibling checkout for overlay
```

Requires `node`, `rg`, `jq`. `quickshell` optional.

## Daily dev

```bash
# edit RailsBar.qml / RailModel.js / Rails/RailPanel.qml (never Bar.qml)
test/rails-test.sh              # without compositor, without touching ../omarchy
test/run-upstream.sh test/shell.d/bar-test.sh  # one overlayed upstream test
qmllint RailsBar.qml Bar.qml Rails/*.qml
```

## Tests (option C: overlay, no copy)

`test/run-upstream.sh` clones `../omarchy` to `/tmp`, overlays `Bar.qml`/`BarModel.js` (+`RailsBar.qml`/`RailModel.js`/`Rails/` if they exist) and runs the suite. Does not dirty `../omarchy`, does not fork tests. Since `Bar.qml` is verbatim, the overlay is idempotent → `bar-test.sh` passes without patches.

```bash
test/run-upstream.sh                         # 6 stable bar tests
test/run-upstream.sh test/shell.d/bar-test.sh
test/rails-test.sh                           # rails-specific (skips if no RailModel.js)

# fragile without compositor/pkgs — explicit only:
test/run-upstream.sh test/shell.d/bar-icon-geometry-test.sh
test/run-upstream.sh test/shell.d/config-test.sh

OMARCHY_SRC=/other/omarchy test/run-upstream.sh
KEEP_TMP=1 test/run-upstream.sh test/shell.d/bar-test.sh  # inspect /tmp
```

**Do rails break upstream tests?** No — `Bar.qml` is untouched. New code lives in `RailsBar.qml`/`RailModel.js`/`Rails/` and is not read by `bar-test.sh`. If an upstream test needs to understand rails (e.g. `config-test.sh` with `bar.rails`), patch on the fly with `sed` inside `run-upstream.sh`. New code goes in `test/rails-test.sh`.

## Pull upstream

```bash
git fetch upstream
git log --oneline HEAD..upstream/quattro -- shell/plugins/bar/  # what changed

git subtree split --prefix=shell/plugins/bar upstream/quattro -b bar-update
git merge bar-update   # trivial by construction: Bar.qml verbatim → fast-forward/auto-merge. Only new files (RailsBar.qml, etc.) live outside the prefix and never collide.
test/run-upstream.sh && test/rails-test.sh
git branch -d bar-update
```

Why trivial? The wrapper is `RailsBar.qml` (entry point), not `Bar.qml`. Everything upstream touches lives under `shell/plugins/bar/` and exists identically here → git merges it automatically. Nothing to resolve unless upstream adds a file named `RailsBar.qml` (unlikely).

Fallback if split fails: `git merge upstream/quattro --no-commit --no-ff` and cherry-pick `shell/plugins/bar/`.

## Clean upstream PR

```bash
git diff --stat upstream/quattro -- shell/plugins/bar/
# ideal: only RailsBar.qml + RailModel.js/Rails/ new outside the prefix; shell/plugins/bar/ identical → empty diff
git diff --stat upstream/quattro  # to see additions: RailsBar.qml, RailModel.js, Rails/, test/rails-test.sh
```
