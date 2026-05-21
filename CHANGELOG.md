# Changelog

All notable changes to this project will be documented in this file.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

History begins at the fork point (commit `4150740`, the last shared commit with the upstream Gnomelets project). Pre-fork history is documented in the upstream repository.

## [0.2.0] - 2026-05-21

This release rebrands the extension from **Gnomelets** to **GnomeDoom** so the fork can coexist with upstream, swaps the cast of characters for a doom-metal skeleton band, and adds AI-agent documentation.

### BREAKING CHANGES

The extension identity has changed across every user-visible identifier. Existing Gnomelets installs will **not** auto-migrate to GnomeDoom.

- **UUID:** `gnomelets@mcast.gnomext.com` → `gnomedoom@olafkfreund.github.io`
- **GSettings schema id:** `org.gnome.shell.extensions.gnomelets` → `org.gnome.shell.extensions.gnomedoom`
- **GSettings schema path:** `/org/gnome/shell/extensions/gnomelets/` → `/org/gnome/shell/extensions/gnomedoom/`
- **Cache file:** `~/.cache/gnomelets-state.json` → `~/.cache/gnomedoom-state.json`
- **Status-area id:** `gnomelets-indicator` → `gnomedoom-indicator`

#### Migration steps

1. Uninstall the previous Gnomelets extension if installed:

   ```sh
   gnome-extensions uninstall gnomelets@mcast.gnomext.com
   ```

   Or remove the directory manually:

   ```sh
   rm -rf ~/.local/share/gnome-shell/extensions/gnomelets@mcast.gnomext.com
   ```

2. Install GnomeDoom under its new UUID (`gnomedoom@olafkfreund.github.io`).
3. Accept fresh dconf state under the new schema. Old `org.gnome.shell.extensions.gnomelets` keys will **not** carry over; reconfigure your preferences via the prefs window.
4. Saved character positions in the old cache file (`~/.cache/gnomelets-state.json`) do not migrate automatically — characters will respawn at defaults on first run.

Internal class names (`Gnomelet`, `GnomeletManager`, `GnomeletIndicator`) and GSettings key names (`gnomelet-type`, `gnomelet-count`, `gnomelet-scale`) are intentionally kept under the new unique schema id to limit churn.

Commit: `4c6ebcf`.

### Added

- Doom-themed skeleton band cast: **SkeletonGuitarist**, **SkeletonDrummer**, **SkeletonVocalist**, **SkeletonDancer**, and **SkullDancer**. (`a546030`)
- `scripts/slice_doom_band.py` helper for slicing sprite-sheet frames out of the band artwork. (`a546030`)
- `CLAUDE.md` with codebase guidance for AI agents — covers install/build commands, the manager/gnomelet/indicator architecture, tick loop, floor-z-order semantics, dock detection, and GJS conventions (`Gio.Cancellable`, `connectObject`, sync I/O only on disable, error handling in `_tick()`). (`182cc39`)
- `.gitignore` entries for AI tooling caches. (`0d24483`)

### Changed

- Rebranded all user-facing labels (indicator menu, prefs window, schema summaries) and the README from Gnomelets to GnomeDoom. (`4c6ebcf`)
- Top-bar indicator icon replaced with a line-art skull sourced from OpenMoji (codepoint `1F480`, black style), keeping the symbolic monochrome look that renders cleanly in the GNOME panel. The source SVG is committed alongside the rendered PNG so the icon can be regenerated at any size. OpenMoji asset is CC BY-SA 4.0 with attribution embedded in `src/images/icon.svg`. (`c4cbc83`)

### Removed

- Original animal cast: **Kitten**, **Mouse**, **Puppy**, **Santa**, **Squirrel**, and **Tux** sprite directories. (`a546030`)

## [0.1.4] - 2026-05-01

### Removed

- Christmas special-edition branding from documentation and `metadata.json`. (`d710927`)

## [0.1.3] - 2026-04-28

### Added

- Configurable spawn-offset preference, exposed in the prefs window and persisted via GSettings. (`559118e`)

### Changed

- Full-screen windows are now included in the `partial` and `disallow` distraction-free modes, so characters get out of the way when watching video full-screen. (`559118e`)

## [0.1.2] - 2026-04-01

### Changed

- Updated metadata for GNOME Shell 50 compatibility. (`a4d5da6`)

## [0.1.1] - 2025-12-27

### Added

- Momentum-based throwing for characters during drag-and-drop: releasing a character with velocity now imparts that velocity to the sprite, so it slides / arcs naturally instead of dropping in place. (`f1a95ef`)

[0.2.0]: https://github.com/olafkfreund/gnomedoom/releases/tag/v0.2.0
[0.1.4]: https://github.com/olafkfreund/gnomedoom/commit/d710927
[0.1.3]: https://github.com/olafkfreund/gnomedoom/commit/559118e
[0.1.2]: https://github.com/olafkfreund/gnomedoom/commit/a4d5da6
[0.1.1]: https://github.com/olafkfreund/gnomedoom/commit/f1a95ef
