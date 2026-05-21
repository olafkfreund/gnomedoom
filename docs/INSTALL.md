# Installing GnomeDoom

GnomeDoom is a GNOME Shell extension. Its UUID is
`gnomedoom@olafkfreund.github.io` and per-user extensions live in
`~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io/`.

Supported GNOME Shell versions: 45, 46, 47, 48, 49, 50 (see
`src/metadata.json`).

> **Wayland reload requirement (read this first)**
>
> After **any** install, update, or uninstall you must reload GNOME
> Shell before changes take effect:
>
> - **Wayland:** log out and log back in. There is no in-session reload
>   on Wayland — this is standard GNOME behaviour, not a GnomeDoom
>   limitation.
> - **X11:** press `Alt+F2`, type `r`, and press Enter.
>
> Then enable the extension:
>
> ```bash
> gnome-extensions enable gnomedoom@olafkfreund.github.io
> ```

---

## Method 1 — NixOS via the flake (recommended on NixOS)

The repository ships a `flake.nix` exposing `packages.<system>.default`
that builds the extension (compiled schema included).

### One-shot install with `nix profile`

```bash
nix profile install github:olafkfreund/gnomedoom
```

This puts the extension under your Nix profile at
`~/.nix-profile/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io/`.
GNOME Shell only reads `~/.local/share/gnome-shell/extensions/` and
`/run/current-system/sw/share/gnome-shell/extensions/`, so you must
either symlink it into the per-user directory:

```bash
mkdir -p ~/.local/share/gnome-shell/extensions
ln -sfn ~/.nix-profile/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io \
        ~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io
```

…or reference the package from your system / Home Manager config (see
below) so it lands in a path the shell already scans.

### System-wide via a NixOS module

Add the flake to your system flake inputs and install the extension as
a system package:

```nix
# flake.nix (system)
{
  inputs.gnomedoom.url = "github:olafkfreund/gnomedoom";

  outputs = { self, nixpkgs, gnomedoom, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            gnomedoom.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

After `nixos-rebuild switch`, log out and back in on Wayland (or Alt+F2
→ `r` on X11), then `gnome-extensions enable
gnomedoom@olafkfreund.github.io`.

### Per-user via Home Manager

```nix
# home.nix
{ pkgs, gnomedoom, ... }:
{
  home.packages = [ gnomedoom.packages.${pkgs.system}.default ];

  # Optional: also have Home Manager enable it for you.
  dconf.settings."org/gnome/shell".enabled-extensions =
    [ "gnomedoom@olafkfreund.github.io" ];
}
```

Pass `gnomedoom` through as a Home Manager `extraSpecialArgs` from your
flake outputs.

### Development shell

For working on the source tree (compiling schemas, packing zips):

```bash
nix develop github:olafkfreund/gnomedoom
# provides glib (glib-compile-schemas) and zip
```

### Uninstall (Nix)

- `nix profile install` path:
  ```bash
  nix profile remove gnomedoom
  rm -f ~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io
  ```
- NixOS / Home Manager: remove the package from your config and
  rebuild. Then log out / log in (Wayland) or Alt+F2 → `r` (X11).

---

## Method 2 — Generic Linux via `./scripts/install.sh`

Works on any distro that ships GNOME Shell 45+. Requirements:

- `bash`
- `glib2` development tools providing `glib-compile-schemas` (Ubuntu /
  Debian: `libglib2.0-bin`; Fedora: `glib2-devel`; Arch: `glib2`)
- `zip` if you intend to use `--zip`

```bash
git clone https://github.com/olafkfreund/gnomedoom.git
cd gnomedoom
./scripts/install.sh
```

This compiles `src/schemas/`, copies the listed files into
`~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io/`,
and prints the standard post-install message:

> Please restart GNOME Shell (Alt+F2, then 'r' on X11, or Log Out/In
> on Wayland) to see changes.

To get a packaged zip instead of installing in place:

```bash
./scripts/install.sh --zip
# -> temp/gnomedoom@olafkfreund.github.io.zip
```

### Uninstall

```bash
gnome-extensions disable gnomedoom@olafkfreund.github.io
rm -rf ~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io
```

Log out / log in (Wayland) or Alt+F2 → `r` (X11).

---

## Method 3 — Manual placement / `gnome-extensions install`

Useful if you only have a release zip (e.g. produced by
`scripts/install.sh --zip` or `scripts/pack.sh`).

### Option A: `gnome-extensions install`

```bash
gnome-extensions install --force gnomedoom@olafkfreund.github.io.zip
gnome-extensions enable  gnomedoom@olafkfreund.github.io
```

### Option B: unzip by hand

```bash
mkdir -p ~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io
unzip gnomedoom@olafkfreund.github.io.zip \
      -d ~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io
glib-compile-schemas \
      ~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io/schemas/
```

(`glib-compile-schemas` is only needed if the zip didn't already
include a `gschemas.compiled`. Zips produced by this repo currently do
not — the flake build does.)

Then reload the shell (Wayland: log out / log in. X11: Alt+F2 → `r`)
and enable:

```bash
gnome-extensions enable gnomedoom@olafkfreund.github.io
```

### Uninstall

```bash
gnome-extensions uninstall gnomedoom@olafkfreund.github.io
```

or just remove the directory:

```bash
rm -rf ~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io
```

Log out / log in (Wayland) or Alt+F2 → `r` (X11).

---

## Method 4 — Ubuntu / Fedora via the GNOME Extensions website

GnomeDoom is **not yet** published on
[extensions.gnome.org](https://extensions.gnome.org/). Submission is
tracked as a future epic. Until then, Ubuntu and Fedora users should
follow **Method 2** (`./scripts/install.sh`) or **Method 3** (zip /
`gnome-extensions install`).

Distro-specific prerequisites:

- **Ubuntu / Debian:**
  ```bash
  sudo apt install gnome-shell-extension-prefs libglib2.0-bin
  ```
  Toggle extensions on with the *Extensions* (or *Extension Manager*)
  app, or `gnome-extensions enable …`.
- **Fedora:**
  ```bash
  sudo dnf install gnome-extensions-app glib2-devel
  ```
  Use the *Extensions* app to flip the toggle, or `gnome-extensions
  enable …`.

---

## Migrating from upstream `gnomelets@mcast.gnomext.com`

GnomeDoom is a fork of the upstream **Gnomelets** extension, renamed so
the two can coexist. If you previously installed the upstream version,
you do **not** need to remove it — the UUIDs are different
(`gnomelets@mcast.gnomext.com` vs `gnomedoom@olafkfreund.github.io`)
and they use different GSettings schema ids
(`org.gnome.shell.extensions.gnomelets` vs
`org.gnome.shell.extensions.gnomedoom`).

That said, running both at once doubles the on-screen characters and
the tick loops. To switch cleanly:

```bash
# Disable / remove the upstream extension
gnome-extensions disable gnomelets@mcast.gnomext.com 2>/dev/null || true
gnome-extensions uninstall gnomelets@mcast.gnomext.com 2>/dev/null || true
rm -rf ~/.local/share/gnome-shell/extensions/gnomelets@mcast.gnomext.com

# Then install GnomeDoom using any method above.
gnome-extensions enable gnomedoom@olafkfreund.github.io
```

Saved character positions are kept under
`~/.cache/gnomedoom-state.json` (separate from the upstream
`~/.cache/gnomelets-state.json`), so neither extension can corrupt the
other's state.

After the switch, log out / log in (Wayland) or Alt+F2 → `r` (X11) to
let the shell pick everything up.

---

## Troubleshooting

- **Extension does not appear in `gnome-extensions list`:** the shell
  has not been reloaded yet. Wayland: log out and back in. X11:
  Alt+F2 → `r`.
- **`Schema 'org.gnome.shell.extensions.gnomedoom' is not installed`
  in the logs:** the schema was not compiled. Re-run
  `glib-compile-schemas
  ~/.local/share/gnome-shell/extensions/gnomedoom@olafkfreund.github.io/schemas/`
  or reinstall via the flake (which compiles automatically).
- **Errors at runtime:** tail the shell journal:
  ```bash
  journalctl -f -o cat /usr/bin/gnome-shell
  ```
