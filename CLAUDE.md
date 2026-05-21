# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

GNOME Shell extension "GnomeDoom" — animated pixel-art characters (skeletons, etc.) that walk, fall, and jump across the desktop, interacting with windows and docks. Forked from the upstream Gnomelets extension; renamed to coexist with it without collision. Targets GNOME Shell 45–50.

- Extension UUID: `gnomedoom@olafkfreund.github.io`
- GSettings schema id: `org.gnome.shell.extensions.gnomedoom`
- State cache: `~/.cache/gnomedoom-state.json`
- Source lives entirely in `src/`. There is no build system, no `package.json`, no transpilation — this is plain GJS (GNOME JavaScript) using ES modules and `gi://` imports.

Internal class/variable names (`Gnomelet`, `GnomeletManager`, GSettings keys like `gnomelet-type`/`gnomelet-count`/`gnomelet-scale`) intentionally keep the original names — they live under the unique schema id so they don't collide with upstream, and renaming them would be a noisy refactor with no behavioral gain.

## Common commands

```bash
# Compile the GSettings schema, then install into ~/.local/share/gnome-shell/extensions/<UUID>
./scripts/install.sh

# Same as above but produces a zip in temp/<UUID>.zip instead of installing
./scripts/install.sh --zip

# Build a release zip (temp/gnomedoom.zip) — used for GNOME Extensions website upload
./scripts/pack.sh

# Compile the schema only (install.sh does this for you)
glib-compile-schemas src/schemas/

# After installing, reload changes
#   X11:     Alt+F2, then 'r'
#   Wayland: log out / log in (or nested shell: dbus-run-session -- gnome-shell --nested --wayland)

# Enable / disable
gnome-extensions enable  gnomedoom@olafkfreund.github.io
gnome-extensions disable gnomedoom@olafkfreund.github.io

# Tail extension logs (errors from console.error inside extension.js end up here)
journalctl -f -o cat /usr/bin/gnome-shell
```

There is no test suite. Validation is manual: install, reload the shell, observe behavior, and watch `journalctl`.

## Architecture

The extension is structured as a small actor system driven by a single tick loop. Understanding the responsibility split between these files is the key to navigating the codebase:

- **`src/extension.js`** — Standard GNOME `Extension` entry point. `enable()` constructs the `GnomeletManager` and optionally a top-bar `GnomeletIndicator`; `disable()` tears both down. Almost no logic lives here.

- **`src/manager.js`** (`GnomeletManager`) — Orchestrator and the most important file. Owns:
  - The list of `Gnomelet` instances and the resource cache (`this._resources[typeName] = { frames, w, h }` of `Gio.FileIcon` per character type).
  - The 50 ms tick (`GLib.timeout_add` → `_tick()`) that scans `global.window_group`, classifies windows, picks docks, then calls `gnomelet.update(...)` on every character.
  - All async image loading (`_loadResourcesAndSpawn`, `_resolveImageFolderAsync`), guarded by a single `Gio.Cancellable` that is cancelled in `disable()`.
  - State persistence to `~/.cache/gnomedoom-state.json` (async load, sync save on disable so the file is written before the extension dies).
  - The "in front of maximized" floor-z-order logic in `_tick()` — three modes (`allow` / `partial` / `disallow`) that compute `minIndex`/`maxIndex`/`forceBackground` bounds against the index of the focused/maximized windows inside `window_group`. This is subtle; preserve its invariants if you touch it.
  - Dock detection in `_scanForDocks()` for Dash to Dock and Dash to Panel — identifies them by walking `Main.layoutManager.uiGroup` and matching `child.constructor.name` / `style_class` prefixes. Selected by the `dock-support` setting.

- **`src/gnomelet.js`** (`Gnomelet`) — One instance per visible character. Holds physics state (`_vx`, `_vy`), animation state, the `St.Icon` actor, drag-and-drop wiring (`DND`), and the per-character state machine (`State.FALLING | WALKING | IDLE | JUMPING | DRAGGING` from `utils.js`). `update(windows, forceBackground, dockContainer)` is called once per tick by the manager with the world it should consider.

- **`src/indicator.js`** — Top-bar `PanelMenu.Button` with Re-spawn / Toggle / Settings entries. Talks to the manager via `_hardReset()` and `toggleVisualization()` and reflects `is-enabled` settings changes.

- **`src/prefs.js`** — Adwaita preferences window. Notably, the character list is built dynamically by enumerating subdirectories of `src/images/`, so new characters appear automatically without code changes.

- **`src/utils.js`** — Shared constants (`UPDATE_INTERVAL_MS=50`, `GRAVITY=2`, `WALK_SPEED=3`), the `State` enum, and `isWindowMaximized()` (treats fullscreen as maximized).

- **`src/schemas/org.gnome.shell.extensions.gnomedoom.gschema.xml`** — All settings keys (`gnomelet-type` as `as`, `gnomelet-count`, `gnomelet-scale`, `floor-z-order`, `dock-support`, `dock-z-order`, `allow-interaction`, `jump-power`, `spawn-offset`, `is-enabled`, `show-indicator`, `reset-trigger`). After any schema edit you **must** run `glib-compile-schemas src/schemas/` and reinstall — the shell only reads `gschemas.compiled`. The manager's `_onSettingsChanged` is the single switch that maps each key to a reaction (`_updateCount`, `_updateScale`, `_loadResourcesAndSpawn(true)`, `_hardReset`, `_updateEnabledState`, `_updateInteractions`, `_updateJumpPower`).

## Adding a character

Characters are discovered, not registered. Create `src/images/<Name>/` with `0.png`–`7.png`:

- `0`–`3`: walk cycle
- `4`: idle
- `5`: jump/fall
- `6`–`7`: optional drag frames (fall back to `1` and `3` if absent)

The folder name is the type string stored in the `gnomelet-type` GSettings array, so renaming a folder will orphan any saved state referring to it.

## Conventions specific to this codebase

- All async GIO work goes through `this._cancellable`. When adding new async calls in the manager, pass it and check `_cancellable.is_cancelled()` before mutating state in callbacks — `disable()` cancels it, and dangling callbacks that touch `this._gnomelets` after teardown will crash the shell.
- Signal connections use the GJS `connectObject(..., this)` / `disconnectObject(this)` pattern (auto-disconnects on object destruction). Match this — do not use raw `connect()`/`disconnect()` with manual id bookkeeping.
- Errors inside `_tick()` are swallowed with `console.error(e)` on purpose so a transient failure doesn't kill the timer. Keep that behavior when editing the loop.
- Synchronous file I/O is acceptable only in `_saveState()` (during `disable()`); everywhere else use the `*_async` variants.
- The `temp/` directory is gitignored and used by both install/pack scripts as a scratch space for zips.
