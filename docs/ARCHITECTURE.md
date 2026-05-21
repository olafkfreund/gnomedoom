# GnomeDoom Architecture

> Audience: human contributors. Companion to the AI-targeted `CLAUDE.md` at the repo root.
> Scope: descriptive of current behaviour as of this commit. No refactor proposals.

This document walks through the moving parts of GnomeDoom in roughly the order data flows: from the central tick loop, through the per-character state machine, down to the small mechanics (edge-jump AI, drag-overlay momentum, animation timing) that give the characters their feel. Read top to bottom on a first pass; jump by section once you know the shape.

For the high-level file map (`extension.js` → `manager.js` → `gnomelet.js` → `indicator.js` → `prefs.js` → `utils.js`), see the "Architecture" section of `CLAUDE.md`.

---

## 1. The tick loop and 50 ms cadence

GnomeDoom runs on a single recurring timer owned by `GnomeletManager`. `_startTimer()` registers a `GLib.timeout_add(GLib.PRIORITY_DEFAULT, UPDATE_INTERVAL_MS, ...)` callback that fires every `UPDATE_INTERVAL_MS = 50` milliseconds (about 20 FPS). The callback simply invokes `_tick()` and returns `GLib.SOURCE_CONTINUE` to keep the timer alive. `_stopTimer()` removes the source by id; the manager tracks `this._timerId` and refuses to register a second timer if one is already live, so toggling `is-enabled` cannot stack callbacks.

Each call to `_tick()` performs the same fixed pipeline:

1. Snapshot the actor list under `global.window_group` and read the currently focused window.
2. Walk that snapshot once to compute `focusedIndex` and a sorted `maximizedIndices` array (sorted ascending because indices are pushed in order during a single forward scan).
3. Compute filter bounds `minIndex`/`maxIndex` and a `forceBackground` flag from the current `floor-z-order` setting (see section 4 for the exact semantics).
4. Walk the actor list a second time to collect non-minimised, non-maximised, non-DING windows whose stack index falls inside `(minIndex, maxIndex)`, recording each as `{ rect, actor }`.
5. Call `_scanForDocks()` (section 5) and append any returned dock surfaces to the same `this._windows` list.
6. For every gnomelet, call `p.update(this._windows, forceBackground, dockContainer)`.

The whole body is wrapped in `try { ... } catch (e) { console.error(e); }`. The catch is deliberate: a transient error from any one tick must not kill the timer, because GNOME Shell will not restart it on its own. New contributors editing `_tick()` should preserve that swallow-and-log behaviour.

See: `src/manager.js:164-181`, `src/manager.js:465-597`, `src/utils.js:1-3`.

---

## 2. The per-character state machine

Each `Gnomelet` instance carries a `_state` field whose value is one of the five strings defined in the `State` enum (`FALLING`, `WALKING`, `IDLE`, `JUMPING`, `DRAGGING`). New gnomelets always start in `FALLING` so they drop from their spawn point and land naturally.

Transitions all live inside `Gnomelet.update()` and a small helper, `_pickNewAction()`:

- `FALLING` / `JUMPING` → `IDLE` or `WALKING`: when collision detection finds ground (a non-dock window top edge, a dock surface, or the floor), `_pickNewAction()` rolls a single random number — 60% chance to enter `WALKING` with a random horizontal direction at `WALK_SPEED`, otherwise `IDLE` with `_idleTimer = Math.random() * 60 + 20` ticks.
- `WALKING` → `FALLING` / `JUMPING`: detected by "not on ground" while the previous state was `WALKING`. The edge-jump AI in section 7 decides which.
- `WALKING` → `IDLE`: on every tick while walking, a 2% chance to stop and re-enter idle (`_idleTimer = Math.random() * 60 + 20`).
- `IDLE` → `WALKING` / `IDLE`: each idle tick decrements `_idleTimer`; on reaching zero, `_pickNewAction()` rolls again.
- `* → DRAGGING`: entered exclusively by the GNOME DND signal `drag-begin`; velocities are zeroed and the animation timer is reset. While dragging, physics and AI are skipped — only `_updateAnimation()` runs.
- `DRAGGING → FALLING`: on `drag-end`, momentum is computed from drag history (section 9) and the state goes back to `FALLING`.

Gravity is applied in `update()` only when the state is `FALLING` or `JUMPING`, so a stationary `IDLE` character does not slide and a `WALKING` character on a flat surface holds its horizontal velocity.

See: `src/utils.js:5-11`, `src/gnomelet.js:30-39`, `src/gnomelet.js:174-263`, `src/gnomelet.js:369-616`, `src/gnomelet.js:716-726`.

---

## 3. Resource cache and async loading

Character sprites are loaded once per type into a manager-owned dictionary, `this._resources`, keyed by directory name (`SkeletonDrummer`, `SkullDancer`, …). Each value is `{ frames: Gio.FileIcon[8], w: int, h: int }`. The `w`/`h` come from the first successfully decoded frame.

All filesystem and decode work goes through GIO async APIs, guarded by a single `Gio.Cancellable` allocated in `enable()`:

- `_resolveImageFolderAsync()` calls `Gio.File.query_info_async()` to confirm the directory exists.
- For each of the eight expected frames `0.png`–`7.png`, `loadFrame()` calls `imgFile.read_async()` followed by `GdkPixbuf.Pixbuf.new_from_stream_async()`. The eight per-frame promises run concurrently inside `Promise.all`.
- `_loadResourcesAndSpawn()` awaits all selected types in parallel, then either hard-resets or spawns into the saved state. Missing frames are stored as `null` and the type is registered only if at least one frame decoded successfully and the first frame had non-zero dimensions.

The cancellable is the contract that keeps async cleanup safe: `disable()` calls `this._cancellable.cancel()` before anything else, so in-flight reads either short-circuit or raise `Gio.IOErrorEnum.CANCELLED` which the manager swallows. Without this, a slow decode could fire its callback after the extension object had been torn down and crash the shell. The same cancellable also guards `_loadStateAsync()`, so reading the cache file can be aborted mid-flight.

See: `src/manager.js:18-31`, `src/manager.js:36-146`, `src/manager.js:187-244`, `src/manager.js:247-269`.

---

## 4. The three floor-z-order modes

`_tick()` implements three floor-z-order modes — `allow`, `partial`, `disallow` — selected by the `floor-z-order` GSettings key. The modes are expressed as a `(minIndex, maxIndex)` window-collection range plus a boolean `forceBackground` that decides whether the gnomelet actor lives in `Main.layoutManager.uiGroup` (chrome) or `Main.layoutManager._backgroundGroup` (behind everything). Indices refer to positions inside `global.window_group.get_children()`.

**`allow`** — characters are always in front. `forceBackground` stays `false`, so the actor lives in `uiGroup` and is drawn on top of normal app windows. The only concession to maximised windows is occlusion: if any window is maximised, `minIndex` is set to the index of the top-most maximised window, so windows below it are not collected as collision surfaces. The character is still rendered, but it cannot land on a window the user can no longer see.

**`partial`** — the focused window's state decides everything. If the focused window is maximised, the character is pushed to the background (`forceBackground = true`) and the collection range becomes `(prevMax, focusedIndex)` where `prevMax` is the highest index in `maximizedIndices` strictly below `focusedIndex` (so the character renders between the previous maximised window and the currently focused one in stack order). If the focused window is not maximised, the mode collapses to `allow`-like behaviour: `forceBackground = false`, `minIndex` is the top-most maximised index when one exists.

**`disallow`** — characters always render behind any visible maximised window. When `maximizedIndices` is non-empty, `forceBackground = true` and `maxIndex` is set to `maximizedIndices[0]` (the bottom-most maximised window, because the indices were pushed in ascending order), so only windows below the bottom-most maximised window are collected. When no window is maximised, `forceBackground = false` and the mode behaves like `allow` with no occlusion.

The same modes also gate dock visibility for collision: in `disallow`, docks are never collected when any maximised window exists; in `partial`, docks are only collected when the focused window is unmaximised; in `allow`, docks are always candidates for collision.

See: `src/manager.js:465-597` (especially the `floorMode` branches at lines 502-551 and dock gating at lines 570-584).

---

## 5. Dock detection (Dash to Dock and Dash to Panel)

`_scanForDocks(allowDock, dockSupportMode)` walks the children of `Main.layoutManager.uiGroup` looking for one of two known dock actors, decided by the `dock-support` GSettings key (`'none'` short-circuits and returns an empty result).

For **Dash to Dock**, the scanner matches `child.constructor?.name === 'DashToDock'`. If `allowDock` is true, it expects the last child to be a `DashSlideContainer` (the non-transparent panel inside the slide animation), reads its transformed position and size, and pushes a `{ rect, actor, isDock: true }` entry. The outer container is returned separately as `dockContainer` and is used by per-gnomelet z-order logic to render either above or below the dock based on the `dock-z-order` setting.

For **Dash to Panel**, the scanner is structurally different because the panel lives two children deep. It tests `child.first_child?.first_child?.style_class?.startsWith('dashtopanelPanel')`, then takes the panel actor's transformed bounds. The `dockContainer` returned in this case is the outermost child found in `uiGroup` so that the same "above/below sibling" reordering call in `gnomelet.js` still finds a valid sibling.

In both branches the first match wins (`break` after a match) — Dash to Dock takes precedence when its mode is selected, otherwise Dash to Panel is the only candidate.

See: `src/manager.js:396-460`.

---

## 6. State persistence to `~/.cache/gnomedoom-state.json`

The cache path is built once in `_init()` as `GLib.get_user_cache_dir() + '/gnomedoom-state.json'`. The lifecycle is intentionally asymmetric:

- **Load — async.** `_loadStateAsync()` runs during `enable()` and calls `Gio.File.load_contents_async()`. On success the bytes are JSON-decoded into an array (one entry per gnomelet) and stashed in `this._pendingState`. `_loadResourcesAndSpawn(false)` is then chained from inside the callback so that resource loading and spawning only start after the state is known. Missing files, decode failures, and the cancellable's `Gio.IOErrorEnum.CANCELLED` are all silently ignored — they collapse to "no saved state, spawn fresh".
- **Save — sync.** `_saveState()` runs from `disable()` and uses `GLib.file_set_contents()`. The synchronous write is deliberate: the extension object is being destroyed and there is no event loop left to drain an async callback, so flushing before exit is the only correct option. The serialised data is `this._gnomelets.map(p => p.serialize())`, where `Gnomelet.serialize()` captures `{ type, x, y, vx, vy, state, facing, idleTimer }`.

On spawn, `_spawnGnomelets()` consults `stateToUse[i].type` to pick a specific resource for slot `i`; if that type is no longer installed, it falls back to a random valid resource. Each gnomelet then calls `deserialize()` to restore position, velocity, state, facing, and `idleTimer`. `_hardReset()` deletes the cache file synchronously (`f.delete(null)`) — this path is rare and user-triggered (the "Re-spawn" indicator entry or the `reset-trigger` setting), so the synchronous call is acceptable.

See: `src/manager.js:18-31`, `src/manager.js:247-302`, `src/gnomelet.js:319-364`.

---

## 7. Edge-jump AI

When a gnomelet walks off a window or platform, `update()` detects "previous state was `WALKING`, now not on ground" and offers a coin flip: with 50% probability it calls `_performJump()` (entering `JUMPING` with the configured `_jumpVelocity` and a doubled horizontal speed in the current facing direction), otherwise it falls into `FALLING`. This is the "jump for falling" behaviour — half the time, a character that walks off a ledge will hop instead of just dropping, which reads as deliberate movement rather than an accident.

This is intentionally not a planned jump: there is no check for whether the jump is reachable, no aiming, no target window. The reachability check exists separately, on a different code path (section 8). Edge-jumps simply add a small amount of joyful chaos at the moment of leaving a surface.

See: `src/gnomelet.js:533-548`, `src/gnomelet.js:728-736`.

---

## 8. Window-reachability prediction

While a character is in `WALKING` state and standing on a surface, the AI scans the current window list to decide whether jumping would be useful. The check uses two precomputed reach metrics in `updateJumpPower()`:

- `_jumpReachX = (WALK_SPEED * 2) * Math.abs(_jumpVelocity / GRAVITY)` — horizontal distance covered before peak.
- `_maxJumpHeight = (_jumpVelocity * _jumpVelocity) / (2 * GRAVITY)` — peak height above the launch point.

For each candidate window (excluding the one currently underneath the character), the AI extends the window's horizontal range by `_jumpReachX` on the side the character is facing, so a window slightly out of reach but in the direction of travel still counts. If the character's feet are inside that extended X range, it checks the vertical distance from feet to window top against `_maxJumpHeight`. A final ceiling check ensures the character can fit on top of the target without clipping into the monitor's top edge (`rect.y - this._displayH >= currentMonitor.y`).

If at least one window passes all three checks, the character flips a 25% chance to actually jump. The result is that characters appear to make decisions: they never attempt jumps they cannot complete, and they ignore windows that are not roughly in their line of travel.

See: `src/gnomelet.js:141-150`, `src/gnomelet.js:551-604`.

---

## 9. Full-screen drag overlay for momentum throws

GnomeDoom uses GNOME Shell's `DND.makeDraggable()` to make characters draggable, but adds two extra mechanics on top: an invisible full-screen overlay and a recent-history-based momentum calculator.

On `drag-begin`, `_onDragBegin()` zeroes velocities, switches the state to `DRAGGING`, and creates a `Clutter.Actor` sized to `global.stage.width` × `global.stage.height` with `reactive: true`. The actor's `_delegate` is set to the gnomelet itself so DND events route correctly, and it is added directly to `Main.layoutManager.uiGroup`. The purpose is to be the drop target for releases anywhere on screen — without it, dropping the character outside any explicit DND-aware actor would either bounce back to its original position or trigger a shell-side actor-unparenting path that has been known to crash the shell.

While dragging, `handleDragOver()` is called repeatedly with the cursor position. Each call appends `{ x, y, time: Date.now() }` to `this._dragHistory` and prunes entries older than 200 ms. On `drag-end`, `_onDragEnd()` destroys the overlay and calls `_calculateMomentum()`, which:

1. Verifies at least two history points exist.
2. Ignores momentum if the drop occurred more than 100 ms after the last recorded motion (the user paused before releasing — not a throw).
3. Picks a baseline sample roughly 50–150 ms in the past, defaulting to the oldest sample if no match.
4. Computes pixels-per-ms, multiplies by `UPDATE_INTERVAL_MS` (50) and a `SCALE_FACTOR` of 0.25 to convert to pixels-per-frame, and clamps the result to ±50 px/frame on each axis.

The result is set as `_vx`/`_vy` and the state returns to `FALLING`, so the throw is just a falling character with initial velocity. `acceptDrop()` also reparents the actor into `global.window_group` to bypass `dnd.js`'s post-drop auto-destruction; the correct layer is restored at the end of `_onDragEnd()` via `_resetLayer()`.

See: `src/gnomelet.js:174-263`, `src/gnomelet.js:265-317`, `src/gnomelet.js:646-669`.

---

## 10. Idle timer cadence

`IDLE` is the only state that uses a count-down timer. Two code paths seed it with the same formula, `Math.random() * 60 + 20` — so an idle period lasts 20 to 80 ticks, which at the 50 ms tick rate is one to four seconds of standing still.

The two seeding sites are:

- `_pickNewAction()`, when the random roll selects `IDLE` instead of `WALKING` after landing.
- `update()` itself, when a `WALKING` character's per-tick 2% stop check fires.

While idle, `update()` zeroes `_vx` to prevent any residual sliding, decrements `_idleTimer`, and on reaching zero calls `_pickNewAction()` again to pick the next behaviour. The randomness in both the duration and the next-action choice is what gives characters their unpredictable rhythm — a character may stand for a second and walk for ten, or vice versa.

See: `src/gnomelet.js:551-558`, `src/gnomelet.js:606-612`, `src/gnomelet.js:716-726`.

---

## 11. Animation frame timing

Each gnomelet ticks `this._animationTimer++` once per `update()` call, then `_updateAnimation()` consults the current state to pick a frame index:

- **`WALKING`** — a four-frame cycle `[0, 1, 2, 3]` advancing every 4 ticks (`speed = 4`), so a full cycle takes 16 ticks (~800 ms). Frame index is `walkFrames[Math.floor(_animationTimer / 4) % 4]`.
- **`IDLE`** — single static frame 4.
- **`JUMPING` / `FALLING`** — single static frame 5 (shared "in the air" pose).
- **`DRAGGING`** — two-frame cycle advancing every 8 ticks. Prefers dedicated drag frames `[6, 7]` if both are present in `_frameImages`, otherwise falls back to `[1, 3]` (two walk-cycle frames). That makes drag frames optional for new characters.

`setFrame()` is a small filter on top: it only sets the icon image if either the frame index changed or the character's facing flipped since the last call (tracked via `_lastFacing`). Horizontal mirroring is achieved by setting `_icon.scale_x` to `-1` when facing left, with a `(0.5, 0.5)` pivot to flip in place.

See: `src/gnomelet.js:741-770`, `src/gnomelet.js:775-792`.

---

## Cross-reference

The methods named in issue #6 and where they live:

- `_tick` — `src/manager.js:465-597`
- `_scanForDocks` — `src/manager.js:396-460`
- `_loadResourcesAndSpawn` — `src/manager.js:69-146`
- `_pickNewAction` — `src/gnomelet.js:716-726`
- `_performJump` — `src/gnomelet.js:728-736`
- `_updateAnimation` — `src/gnomelet.js:741-770`
