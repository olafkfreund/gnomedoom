# Contributing to GnomeDoom

Thanks for considering a contribution! GnomeDoom is a GNOME Shell extension (forked from upstream Gnomelets) that draws animated pixel-art characters across your desktop. It targets GNOME Shell 45–50, is written in plain GJS (no build system, no `package.json`, no transpilation), and lives entirely in `src/`.

This document walks you from a fresh clone to a running dev install, explains the GJS conventions you must follow, and gives you a PR checklist.

> Looking for character authoring rules or deep architectural background? See `docs/CHARACTERS.md` and `docs/ARCHITECTURE.md` (tracked in separate tickets).

## Table of contents

1. [Prerequisites](#prerequisites)
2. [Quick start](#quick-start)
3. [The development loop](#the-development-loop)
4. [Reloading GNOME Shell](#reloading-gnome-shell)
5. [Inspecting logs](#inspecting-logs)
6. [Code style and GJS conventions](#code-style-and-gjs-conventions)
7. [Pull request checklist](#pull-request-checklist)

## Prerequisites

You need:

- GNOME Shell 45 or newer (50 supported).
- `glib-compile-schemas` (ships with `glib2`/`libglib2.0-bin`).
- `gnome-extensions` CLI (ships with `gnome-shell`).
- `zip` (for the `--zip` and `pack.sh` workflows).
- A working knowledge of GJS would help, but the conventions section below should be enough to get you started.

There is **no test suite**. Validation is manual: install, reload the shell, observe behaviour, and tail `journalctl`.

## Quick start

```bash
git clone https://github.com/olafkfreund/gnomedoom.git
cd gnomedoom
./scripts/install.sh
# Then reload GNOME Shell — see "Reloading GNOME Shell" below.
gnome-extensions enable gnomedoom@olafkfreund.github.io
```

That's it. The script compiles the GSettings schema and copies the extension into `~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io/`.

## The development loop

### Installing your local checkout

`scripts/install.sh` is the canonical dev-install entrypoint. It does two things in order:

1. Compiles `src/schemas/` with `glib-compile-schemas` (the shell only reads `gschemas.compiled`, never the XML).
2. Copies the runtime files (`extension.js`, `prefs.js`, `metadata.json`, `schemas/`, `images/`, `manager.js`, `gnomelet.js`, `indicator.js`, `utils.js`) into `~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io/`.

```bash
./scripts/install.sh
```

### Producing a zip (for the GNOME Extensions website or sharing)

Pass `--zip` to skip the copy and produce `temp/gnomedoom@olafkfreund.github.io.zip` instead:

```bash
./scripts/install.sh --zip
```

For the release zip that the GNOME Extensions website expects (with `README.md` bundled), use the dedicated packing script:

```bash
./scripts/pack.sh
# Produces temp/gnomedoom.zip
```

The `temp/` directory is gitignored.

### Compiling the schema by hand

`install.sh` runs this for you, but if you are iterating on `src/schemas/org.gnome.shell.extensions.gnomedoom.gschema.xml` and don't want to reinstall, you can compile in place:

```bash
glib-compile-schemas src/schemas/
```

**Any schema change requires a recompile *and* a reinstall.** The shell will read the stale `gschemas.compiled` from your install dir otherwise, and your "new" key will appear to be missing.

### Enabling and disabling

```bash
gnome-extensions enable  gnomedoom@olafkfreund.github.io
gnome-extensions disable gnomedoom@olafkfreund.github.io
gnome-extensions info    gnomedoom@olafkfreund.github.io
gnome-extensions prefs   gnomedoom@olafkfreund.github.io
```

## Reloading GNOME Shell

You must reload the shell after `install.sh` for changes to take effect. The procedure depends on your session type — check with `echo $XDG_SESSION_TYPE`.

### On X11

Press `Alt+F2`, type `r`, press Enter. The shell restarts in place; your apps keep running.

### On Wayland

There is no in-place restart on Wayland. You have two options:

1. **Log out and log back in.** The reliable option.
2. **Run a nested shell** — develop and test inside a windowed GNOME Shell on top of your current session. This is the fastest inner loop:

   ```bash
   dbus-run-session -- gnome-shell --nested --wayland
   ```

   Inside the nested shell, the extension will pick up your latest install. Quit the nested window to return to your real session.

## Inspecting logs

Errors from `console.error(...)` inside the extension end up in the user journal under the `gnome-shell` unit. Tail them with:

```bash
journalctl --user -b -t gnome-shell -f
```

- `--user` scopes to your session.
- `-b` limits to the current boot.
- `-t gnome-shell` filters by syslog identifier.
- `-f` follows.

If you prefer a single, terse stream of just gnome-shell stderr, this also works:

```bash
journalctl -f -o cat /usr/bin/gnome-shell
```

When something crashes the shell, search backwards from the crash time for the first `JS ERROR:` line — that's almost always your stack trace.

## Code style and GJS conventions

GnomeDoom uses a small but strict set of patterns. They exist because GNOME Shell extensions run inside the shell process: a stray dangling callback or leaked signal will not just throw — it can crash your desktop. Stick to these.

### 1. The cancellable pattern (every async GIO call)

All async work in the manager is guarded by a single `Gio.Cancellable` stored on `this._cancellable`. It is constructed in `enable()` and cancelled in `disable()`. Every async callback must check `_cancellable.is_cancelled()` before mutating any `this.*` state — otherwise a callback that completes after the extension was disabled will dereference torn-down members and bring down the shell.

Construction in `enable()`:

```javascript
enable() {
    this._cancellable = new Gio.Cancellable();
    this._settings.connectObject('changed', this._onSettingsChanged.bind(this), this);
    // ...
    this._loadStateAsync();
    // ...
}
```

Cancellation in `disable()`:

```javascript
disable() {
    // Cancel any pending async load
    if (this._cancellable) {
        this._cancellable.cancel();
        this._cancellable = null;
    }
    // ...
}
```

**Rule:** when you add a new async GIO call (anything ending in `_async`), pass `this._cancellable` to it, and in the callback bail early if the cancellable is cancelled or `null`. Do not silently swallow `Gio.IOErrorEnum.CANCELLED` — it's the normal exit path during disable.

### 2. `connectObject` / `disconnectObject` (never raw `connect`)

GJS provides `connectObject(signal, handler, owner)` and the matching `disconnectObject(owner)` for bulk teardown. Using these instead of raw `connect()`/`disconnect()` removes the need to track signal-id integers and guarantees all signals owned by `this` are disconnected on teardown.

```javascript
// enable()
this._settings.connectObject('changed', this._onSettingsChanged.bind(this), this);

let themeContext = St.ThemeContext.get_for_stage(global.stage);
if (themeContext) {
    themeContext.connectObject('notify::scale-factor',
        () => this._updateScale(), this);
}
```

```javascript
// disable() — one call per object, no id bookkeeping
let themeContext = St.ThemeContext.get_for_stage(global.stage);
if (themeContext) {
    themeContext.disconnectObject(this);
}
// ...
this._settings.disconnectObject(this);
```

**Rule:** never use `obj.connect(...)` and manual `obj.disconnect(id)` in this codebase. If you mix idioms, signals get leaked across enable/disable cycles and you'll see double-fired handlers on the second enable.

### 3. Synchronous I/O only in `_saveState()` during `disable()`

The single legitimate use of blocking file I/O is `_saveState()`, called from `disable()`. Everywhere else — and that emphatically includes `_loadStateAsync`, `_loadResourcesAndSpawn`, `_resolveImageFolderAsync` — use the `*_async` GIO variants and pass the cancellable.

The rationale: `disable()` is the last moment the extension is alive. If we kicked off an async save, the extension would be torn down before the write hit disk, and the cache file (`~/.cache/gnomedoom-state.json`) would be lost or truncated. A short blocking write here is the lesser evil.

```javascript
disable() {
    if (this._cancellable) {
        this._cancellable.cancel();
        this._cancellable = null;
    }
    // ...
    this._saveState();   // <-- sync save, intentional
    this._stopTimer();
    // ...
}
```

**Rule:** if you find yourself reaching for `Gio.File.prototype.replace_contents` or `load_contents` (the sync variants) outside `_saveState`, stop and use the async ones.

### 4. Errors inside `_tick()` are swallowed on purpose

The 50 ms tick (`_tick()`) drives the entire animation. A single thrown exception in the loop would kill the `GLib.timeout_add` timer and freeze the world. The loop therefore wraps its body in `try/catch` and routes errors through `console.error(e)` to keep ticking. **Preserve this behaviour** when editing the loop:

```javascript
_tick() {
    try {
        // scan windows, classify, pick docks, update each gnomelet...
    } catch (e) {
        console.error(e);
    }
    return GLib.SOURCE_CONTINUE;
}
```

When you investigate weird behaviour mid-animation, the trail is in `journalctl` (see [Inspecting logs](#inspecting-logs)) — not in a crash, because we never let it crash.

### 5. Other notes

- Internal class/variable names (`Gnomelet`, `GnomeletManager`, schema keys like `gnomelet-type` / `gnomelet-count` / `gnomelet-scale`) intentionally keep the original upstream names so the fork stays diffable against upstream history. Don't rename them in a routine PR.
- The schema id is `org.gnome.shell.extensions.gnomedoom` and the extension UUID is `gnomedoom@olafkfreund.github.io`. Both are distinct from upstream so the two extensions can be installed side by side.
- Characters are discovered, not registered: dropping a `src/images/<Name>/` folder with `0.png`–`7.png` is enough.

## Pull request checklist

Copy this block into your PR description and tick the items as you go:

```markdown
- [ ] Tested on X11 (`Alt+F2`, `r`) where possible
- [ ] Tested on Wayland (log out / log in, or nested `dbus-run-session -- gnome-shell --nested --wayland`)
- [ ] Schema recompiled if `*.gschema.xml` changed (`glib-compile-schemas src/schemas/`) and `gschemas.compiled` is committed
- [ ] All new async GIO calls use `this._cancellable` and check it in callbacks
- [ ] All new signal connections use `connectObject` / `disconnectObject` (no raw `connect`)
- [ ] Synchronous I/O is confined to `_saveState()` on `disable()`
- [ ] `_tick()` still catches and `console.error`s exceptions instead of throwing
- [ ] No `gnomelets` strings reintroduced outside fork-attribution context
- [ ] `journalctl --user -b -t gnome-shell` is clean after enable + a few minutes of activity
- [ ] README.md / CHANGELOG.md updated if user-visible behaviour changed
```

Thanks for contributing!
