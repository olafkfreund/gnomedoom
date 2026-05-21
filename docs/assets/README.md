# docs/assets/

This directory is the canonical home for all visual documentation media in
GnomeDoom: demo GIFs, screenshots, and any stills referenced from the
top-level `README.md`, `CONTRIBUTING.md`, or other docs.

> Sprite art for the in-extension characters (SkeletonDancer, SkeletonDrummer,
> SkullDancer, etc.) lives under `src/images/` and is **not** part of this
> directory. Keep the two paths separate: `src/images/` ships inside the
> extension at runtime, `docs/assets/` exists purely for repository
> documentation and is never read by `manager.js`.

## Convention

| Filename                 | Purpose                                                      |
| ------------------------ | ------------------------------------------------------------ |
| `demo.gif`               | Hero demo on the README; skeleton cast in motion, ~3-8 s.    |
| `indicator-menu.png`     | Still of the panel indicator menu open.                      |
| `<feature>-<n>.png`      | Optional supplementary stills (e.g. `drag-throw-1.png`).     |

Rules:

- All assets MUST live in this directory. No upstream GitHub attachment URLs
  or other off-repo hosting for documentation media.
- Reference assets from Markdown with relative links, e.g.
  `![demo](docs/assets/demo.gif)` from the repo root.
- Keep individual files **<= 5 MB** wherever feasible. GitHub renders larger
  GIFs poorly and inflates clone size.
- Prefer GIF for short loops, PNG for stills, MP4 only if a feature genuinely
  requires audio or >10 s of footage.

## Recording a fresh demo

The exact tooling depends on your session type.

### X11

```bash
# peek (simple GUI recorder)
peek

# or byzanz-record (CLI, 10 s of a 1024x768 region from (100,100))
byzanz-record --duration=10 --x=100 --y=100 --width=1024 --height=768 demo.gif
```

### Wayland

`peek` and `byzanz-record` do not work on Wayland. Use one of:

```bash
# wf-recorder produces MP4; convert with ffmpeg + gifski
wf-recorder -g "$(slurp)" -f /tmp/demo.mp4
ffmpeg -i /tmp/demo.mp4 -vf "fps=20,scale=800:-1:flags=lanczos" /tmp/frames-%04d.png
gifski -o demo.gif /tmp/frames-*.png

# or OBS Studio with the PipeWire screen capture source
```

## Optimising

After recording, shrink the GIF before committing:

```bash
gifsicle -O3 --lossy=80 demo.gif -o demo.gif

# Check the result is under the 5 MB ceiling
du -h demo.gif
```

For PNGs, use `oxipng -o max indicator-menu.png` or `pngquant --quality=70-90`.

## Suggested demo content

A good `demo.gif` should show, in this order:

1. The skeleton cast (Dancer, Drummer, Guitarist, Vocalist, SkullDancer)
   walking across the desktop.
2. A click-and-drag throw with momentum release.
3. The panel indicator menu opened to show the spawn controls.

Keep it tight: 3-8 seconds is plenty.

## Related issues

- Epic: #1
- README rewrite: #2 (will add the `![demo](docs/assets/demo.gif)` reference)
- This convention: #8
