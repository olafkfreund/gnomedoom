# GnomeDoom 💀

**GnomeDoom** is a GNOME Shell extension that drops a cast of animated pixel-art skeletons onto your desktop. They fall from the top of the screen, land on your open windows, walk along title bars, jump between window edges, and can be picked up and flung around with the mouse. GnomeDoom targets GNOME Shell 45 through 50 and runs as plain GJS (no build step, no transpilation).

![GnomeDoom demo](docs/assets/demo.gif)

## Fork attribution

GnomeDoom is a hard fork of the upstream [gnomelets](https://github.com/ihpled/gnomelets) extension by `ihpled`. It carries a distinct UUID (`gnomedoom@olafkfreund.github.io`) and GSettings schema id (`org.gnome.shell.extensions.gnomedoom`) so the two extensions can be installed side-by-side without colliding. Internal symbol names (the `Gnomelet` class, `GnomeletManager`, and several settings keys) intentionally preserve the upstream naming to keep the fork diff small; everything user-visible has been rebranded.

## Features

- **Skeleton character cast** — ships with five pixel-art characters: `SkeletonGuitarist`, `SkeletonDrummer`, `SkeletonVocalist`, `SkeletonDancer`, and `SkullDancer`. Drop more folders into `src/images/` and they appear in the preferences automatically.
- **Physics-based movement** — characters obey gravity, fall naturally, and land on solid surfaces (window top edges, title bars, docks).
- **Window interaction** — every 50 ms the extension scans `global.window_group`, classifies windows, and lets characters walk along their visible edges.
- **Momentum throw on drag-release** (commit `f1a95ef`) — pick a character up with the mouse and toss it. Velocity at release is preserved, so flicking the cursor flings the character across the screen.
- **Configurable spawn offset** (commit `559118e`) — control where characters drop in from with the `spawn-offset` setting.
- **Fullscreen-aware distraction-free modes** (commit `559118e`) — the `partial` and `disallow` floor-z-order modes treat fullscreen windows the same as maximized ones, so characters don't intrude when you're watching video or gaming.
- **GNOME 45–50 support** (commit `a4d5da6`) — runs on every shell release in that range without code changes.
- **Multi-monitor** — characters can spawn on and travel across all connected monitors.
- **Smart jump AI** — characters detect edges, leap when it makes sense, and target reachable windows when climbing.
- **Top-bar menu** — a skull indicator in the top panel exposes Re-spawn, Toggle on/off, and Settings without opening preferences.
- **Dash to Dock / Dash to Panel awareness** — when one of those extensions is present, characters can land on and walk along its surface.
- **State persistence** — character positions survive shell restart and extension disable/enable via `~/.cache/gnomedoom-state.json`.

## Configuration

GnomeDoom is configured through the standard extension preferences window (`gnome-extensions prefs gnomedoom@olafkfreund.github.io`). Every preference is backed by a key in [`src/schemas/org.gnome.shell.extensions.gnomedoom.gschema.xml`](src/schemas/org.gnome.shell.extensions.gnomedoom.gschema.xml):

| User-facing label | GSettings key | Type | Default | What it does |
|---|---|---|---|---|
| Characters | `gnomelet-type` | `as` | `['SkeletonGuitarist', 'SkeletonDrummer', 'SkeletonVocalist', 'SkeletonDancer', 'SkullDancer']` | One or more character folders from `src/images/`. If multiple are chosen, each spawn picks one at random. |
| Number of Characters | `gnomelet-count` | `i` | `5` | How many characters live on the desktop at once. |
| Character Scale | `gnomelet-scale` | `i` | `64` | Target character height in pixels. |
| In Front of Maximized | `floor-z-order` | `s` (`allow` / `partial` / `disallow`) | `allow` | Z-order policy versus maximized windows. See [Floor z-order semantics](#floor-z-order-semantics) below. |
| In Front of Dock | `dock-z-order` | `b` | `false` | When `true`, characters render in front of the Dash to Dock or Dash to Panel surface; when `false`, behind it. |
| Dock Support | `dock-support` | `s` (`none` / `dash-to-dock` / `dash-to-panel`) | `none` | Selects which dock extension, if any, GnomeDoom should treat as a walkable surface. |
| Allow Interaction | `allow-interaction` | `b` | `false` | Enables mouse drag-and-drop (with momentum throw on release). |
| Jump Power | `jump-power` | `i` | `20` | Vertical jump force. Higher values mean higher hops. |
| Spawn Offset from Top | `spawn-offset` | `i` | `0` | Vertical pixel offset below the top of the screen where new characters appear. |
| Is Enabled | `is-enabled` | `b` | `true` | Master visibility/activity switch, also toggled by the top-bar menu. |
| Show Indicator | `show-indicator` | `b` | `true` | Whether the skull indicator appears in the top panel. |
| Reset Trigger | `reset-trigger` | `b` | `false` | Internal pulse key — flip it to re-spawn every character from scratch. Bound to the top-bar "Re-spawn" entry. |

### Floor z-order semantics

The `floor-z-order` setting (label: *In Front of Maximized*) controls how characters stack against maximized and fullscreen windows. The authoritative implementation lives in `_tick()` in [`src/manager.js`](src/manager.js) (lines 465–597). The three modes work as follows:

- **`allow`** — characters are always drawn in front, but are occluded by anything stacked above the *topmost* maximized window. In practice this means characters appear on top of normal windows but cannot climb over the maximized window itself.
- **`partial`** — if the currently focused window is maximized (or fullscreen), characters are forced into the background and clipped to the stack range *between* the previous maximized window and the focused one — so they only show through the visible sliver of the desktop, not over the focused content. If the focused window is **not** maximized, `partial` behaves identically to `allow`.
- **`disallow`** — whenever *any* visible window is maximized or fullscreen, characters are forced into the background and clipped behind the bottommost maximized window. With no maximized windows present, behaviour falls back to normal.

Fullscreen windows are treated as maximized in all three modes (see `isWindowMaximized()` in `src/utils.js`), so video players and games entering fullscreen will trigger `partial`/`disallow` distraction-free behaviour just like a regular maximized window.

## Installation

Quick start:

```bash
./scripts/install.sh                                           # compile schema + install into ~/.local/share/gnome-shell/extensions/
gnome-extensions enable gnomedoom@olafkfreund.github.io        # enable it
gnome-extensions prefs  gnomedoom@olafkfreund.github.io        # open preferences
```

After installing you need to reload GNOME Shell: on X11 press `Alt+F2` then `r`; on Wayland log out and back in.

For packaging instructions, manual install steps, and zip-based distribution, see [`docs/INSTALL.md`](docs/INSTALL.md).

## Adding custom characters

Characters are discovered by directory enumeration, not by a registry. Create `src/images/<Name>/` containing PNG frames:

- `0.png`–`3.png` — walk cycle
- `4.png` — idle
- `5.png` — jump / fall
- `6.png`, `7.png` — optional drag frames (fall back to `1.png` and `3.png` if absent)

The folder name becomes the type string stored in the `gnomelet-type` GSettings array, so renaming a folder orphans any saved state pointing at it. Re-run `./scripts/install.sh` (or restart the shell after a dev install) and the new character will appear in the preferences dropdown.

For full character authoring guidance — sprite sizing, transparent backgrounds, the doom-band slicer at `scripts/slice_doom_band.py`, palette conventions — see [`docs/CHARACTERS.md`](docs/CHARACTERS.md).

## Logs and debugging

The extension swallows errors inside its 50 ms tick on purpose so transient failures don't kill the timer. Anything serious is sent to `console.error`, which shows up in the shell journal:

```bash
journalctl -f -o cat /usr/bin/gnome-shell
```

State is cached at `~/.cache/gnomedoom-state.json`; delete it to force a clean spawn on next enable.

## License

MIT — see [`LICENSE`](LICENSE).
