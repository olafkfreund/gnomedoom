{
  description = "GnomeDoom - a GNOME Shell extension that spawns animated pixel-art characters on your desktop";

  # nixpkgs is pinned to nixos-unstable. Pick a recent stable channel
  # (e.g. nixos-25.05) if you need long-term stability; unstable is
  # used here so the latest glib / GNOME tooling is available.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        uuid = "gnomedoom@olafkfreund.github.io";

        # Files that scripts/install.sh copies into the extension dir.
        # Keep this list in sync with FILES_TO_INSTALL in scripts/install.sh.
        extensionFiles = [
          "extension.js"
          "prefs.js"
          "metadata.json"
          "schemas"
          "images"
          "manager.js"
          "gnomelet.js"
          "indicator.js"
          "utils.js"
        ];

        gnomedoom = pkgs.stdenv.mkDerivation {
          pname = "gnomedoom";
          version = "1";

          src = ./src;

          # glib provides glib-compile-schemas, used to compile the
          # GSettings schema before the shell can read it.
          nativeBuildInputs = [ pkgs.glib ];

          # No configure / build step — this is plain GJS.
          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall

            install_dir="$out/share/gnome-shell/extensions/${uuid}"
            mkdir -p "$install_dir"

            for f in ${pkgs.lib.escapeShellArgs extensionFiles}; do
              if [ ! -e "$f" ]; then
                echo "error: expected source file '$f' not found" >&2
                exit 1
              fi
              cp -r "$f" "$install_dir/"
            done

            # Compile the GSettings schema in place so the shell can
            # load it directly from $out without any post-install hook.
            glib-compile-schemas "$install_dir/schemas/"

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "GNOME Shell extension that spawns animated pixel-art characters on your desktop";
            homepage = "https://github.com/olafkfreund/gnomedoom";
            license = licenses.gpl2Plus;
            platforms = platforms.linux;
            maintainers = [ ];
          };
        };
      in
      {
        packages = {
          default = gnomedoom;
          gnomedoom = gnomedoom;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            glib # glib-compile-schemas
            zip # used by scripts/install.sh --zip and scripts/pack.sh
          ];

          shellHook = ''
            echo "gnomedoom devShell — glib-compile-schemas and zip available"
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
