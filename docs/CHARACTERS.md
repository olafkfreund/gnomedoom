# Authoring Characters for GnomeDoom

This guide walks you through adding a new playable character to GnomeDoom.
Characters are discovered automatically from the filesystem — no code changes
are required to register a new one. You either:

1. **Drop hand-authored frames** directly into `src/images/<Name>/` as
   `0.png` through `5.png` (and optionally `6.png` / `7.png`), or
2. **Process a sprite sheet** with `scripts/slice_doom_band.py`, which slices
   a 4×2 sheet, removes a green-screen background, trims grid borders, and
   writes the per-frame PNGs for you.

Both paths produce the same on-disk layout. The runtime does not care which
tool you used.

---

## 1. Runtime PNG layout

Each character lives in its own directory under `src/images/`. The folder
name is the **character type string** — it is what gets stored in the
`gnomelet-type` GSettings array and shown verbatim in the preferences UI, so
choose something that reads well (PascalCase is the convention used by the
existing characters: `SkeletonGuitarist`, `SkullDancer`, …).

```
src/images/<Name>/
├── 0.png   # walk frame 1
├── 1.png   # walk frame 2
├── 2.png   # walk frame 3
├── 3.png   # walk frame 4
├── 4.png   # idle
├── 5.png   # jump / fall
├── 6.png   # (optional) drag frame A
└── 7.png   # (optional) drag frame B
```

| File      | Animation state    | Required?                              |
| --------- | ------------------ | -------------------------------------- |
| `0.png`   | Walk cycle frame 1 | **Yes**                                |
| `1.png`   | Walk cycle frame 2 | **Yes**                                |
| `2.png`   | Walk cycle frame 3 | **Yes**                                |
| `3.png`   | Walk cycle frame 4 | **Yes**                                |
| `4.png`   | Idle               | **Yes**                                |
| `5.png`   | Jump / fall        | **Yes**                                |
| `6.png`   | Drag frame A       | Optional — falls back to `1.png`       |
| `7.png`   | Drag frame B       | Optional — falls back to `3.png`       |

### The 6/7 → 1/3 drag-frame fallback

If `6.png` and `7.png` are **both** present and load successfully, the runtime
uses them as the two-frame "being dragged" flipbook. Otherwise it reuses
walk-cycle frames `1.png` and `3.png` for the drag animation. This logic
lives in `src/gnomelet.js` (around the drag-animation branch):

```js
let dragFrames = [1, 3];
if (this._frameImages[6] && this._frameImages[7]) {
    dragFrames = [6, 7];
}
```

So you can ship a perfectly good character with just six frames (`0`–`5`)
and the drag interaction will still animate — just with the walk frames
instead of bespoke ones. Author dedicated `6`/`7` frames only when the
walking pose looks wrong while being held by the cursor (e.g. you want a
"flailing arms" or "limp ragdoll" pose specifically for drag).

### Recommended dimensions

- **Transparent background** is required. Any opaque background colour will
  appear as a solid rectangle around the character on the desktop.
- **Consistent canvas size across all frames.** The runtime samples width
  and height from the first frame that loads (`src/manager.js`) and reuses
  those dimensions for the whole character — frames with different sizes
  will not be rescaled, they will simply be drawn at their authored
  dimensions and may appear to "shake" or "stretch" when the animation
  switches between them.
- A canvas of roughly **240 × 280 px** comfortably fits the existing
  skeleton-band characters after trimming. If you use the slicer, it
  produces a canvas sized to the union bounding box of all six frames plus
  16 px of padding (see [Trim and centre](#trim-and-centre) below).
- The `gnomelet-scale` preference scales the character at runtime, so you do
  not need to pre-scale for visual size — author at a generous size and let
  the user scale down if needed.
- PNG-32 with straight alpha. Avoid pre-multiplied alpha.

---

## 2. Auto-discovery in the preferences UI

There is **no registration step**. After you create `src/images/<Name>/`,
reinstall the extension (`./scripts/install.sh`) and reload GNOME Shell:

- X11: `Alt+F2`, then type `r` and press Enter.
- Wayland: log out and back in.

The preferences window enumerates `src/images/` on every open and lists
every subdirectory it finds as a tickable character. The relevant code is
[`src/prefs.js` lines 27–46](../src/prefs.js):

```js
imagesDir.enumerate_children_async(
    'standard::name,standard::type',
    Gio.FileQueryInfoFlags.NONE,
    GLib.PRIORITY_DEFAULT,
    null,
    (obj, res) => {
        let types = [];
        try {
            let enumerator = obj.enumerate_children_finish(res);
            let info;
            while ((info = enumerator.next_file(null))) {
                if (info.get_file_type() === Gio.FileType.DIRECTORY) {
                    types.push(info.get_name());
                }
            }
        } catch (e) {
            console.error('Failed to list gnomelet types:', e);
        }

        types.sort();
        if (types.length === 0) types.push('SkeletonGuitarist');
        // …
    }
);
```

Notes on this behaviour:

- Listing is **case-sensitive** and uses the raw directory name as the
  display title — no transformation is applied.
- The list is **sorted alphabetically** before rendering.
- If `src/images/` is empty for any reason, the UI falls back to a single
  entry: `SkeletonGuitarist`.
- The folder name is also the value persisted in the `gnomelet-type`
  GSettings key. **Renaming a folder will orphan any saved state that
  refers to the old name** — users will need to re-tick the character.

---

## 3. Sprite-sheet workflow: `scripts/slice_doom_band.py`

If you are starting from a single sprite sheet rather than per-frame PNGs,
the slicer automates the conversion. Read
[`scripts/slice_doom_band.py`](../scripts/slice_doom_band.py) for the full
implementation — what follows documents it as implemented.

### Inputs and outputs

| Convention            | Path                                               |
| --------------------- | -------------------------------------------------- |
| Sheet input directory | `temp/images/`                                     |
| Sheet filename        | `<Name>_sheet.png` (matches `file` in the config)  |
| Frame output dir      | `src/images/<Name>/`                               |

`temp/` is git-ignored — it is a scratch space for the install/pack scripts
and the slicer alike. Put your raw sheets there.

### Sheet layout

The slicer expects a **4-column × 2-row grid** of cells. Each cell is
**256 px wide by 512 px tall**, giving a full sheet of **1024 × 1024 px**.

These numbers are hard-coded in `slice_doom_band.py`:

```python
# Grid parameters (4 columns, 2 rows)
cell_w = 256
cell_h = 512
```

ASCII map of the cells the slicer reads:

```
                col 0           col 1           col 2           col 3
              ┌───────────────┬───────────────┬───────────────┬───────────────┐
   row 0      │   walk 0      │   walk 1      │   walk 2      │   walk 3      │
   (y =   0)  │   256×512     │   256×512     │   256×512     │   256×512     │
              │   → 0.png     │   → 1.png     │   → 2.png     │   → 3.png     │
              ├───────────────┼───────────────┼───────────────┼───────────────┤
   row 1      │ pose A        │ pose B        │ pose C        │ pose D        │
   (y = 512)  │ idle/jump     │ idle/jump     │ idle/jump     │ idle/jump     │
              │ candidate     │ candidate     │ candidate     │ candidate     │
              └───────────────┴───────────────┴───────────────┴───────────────┘
```

- **Row 0** is always the walk cycle, left-to-right, written to `0.png`
  through `3.png`.
- **Row 1** holds four candidate poses; the slicer picks one for idle and
  one for jump/fall based on the per-character config:
  - `idle_col` (default `1`) → `4.png`
  - `jumping_col` (default `2`) → `5.png`

The slicer writes only six frames per run (`0.png` through `5.png`). It
does **not** produce `6.png` / `7.png` — if you want dedicated drag frames,
hand-author them and drop them into `src/images/<Name>/` after the slicer
finishes. Otherwise the runtime applies the [`6/7 → 1/3`
fallback](#the-67--13-drag-frame-fallback).

### `characters` list config

At the bottom of `slice_doom_band.py` is the per-character config the
slicer iterates over:

```python
characters = [
    {"name": "SkeletonGuitarist", "file": "SkeletonGuitarist_sheet.png", "jump": 2, "idle": 1},
    {"name": "SkeletonDrummer",   "file": "SkeletonDrummer_sheet.png",   "jump": 2, "idle": 1},
    {"name": "SkeletonVocalist",  "file": "SkeletonVocalist_sheet.png",  "jump": 2, "idle": 0},
    {"name": "SkeletonDancer",    "file": "SkeletonDancer_sheet.png",    "jump": 2, "idle": 1},
    {"name": "SkullDancer",       "file": "SkullDancer_sheet.png",       "jump": 2, "idle": 1},
]
```

| Field  | Meaning                                                            |
| ------ | ------------------------------------------------------------------ |
| `name` | Output folder name under `src/images/` and the character's type.   |
| `file` | Sheet filename, looked up under `temp/images/`.                    |
| `jump` | Row-1 column index used as `5.png` (jump/fall). Usually `2` or `3`. |
| `idle` | Row-1 column index used as `4.png` (idle). Usually `0`, `1`, or `2`. |

To process a new character you append one entry and re-run the script. The
existing entries are kept so the run is idempotent for the shipped
characters — the script simply overwrites their output folders.

### Green-screen removal

The slicer assumes a **bright green** background (`#00FF00` and friends —
the classic green-screen colour). `clean_green_and_grid` converts the sheet
to RGBA and zeroes the alpha of any pixel matching either of two rules:

```python
if g > 130 and r < 100 and b < 100:      # core bright greens
    new_data.append((0, 0, 0, 0))
elif g > 180 and r < 150 and b < 150:    # lighter/yellower greens
    new_data.append((0, 0, 0, 0))
```

If your sheet uses magenta, blue, or anything else as the background, either
recolour the background to `#00FF00` in your image editor before saving, or
fork the function and adjust the thresholds. There is no CLI flag for this.

### Border trimming

After cropping each cell out of the sheet, `clear_borders(cell, border=12)`
zeroes the outer **12 pixels** of every cell. This wipes residual grid
lines that some sprite-sheet exporters draw between cells. If your sheet
has thicker grid lines, you will need to bump that value; if it has no
grid at all the call is harmless (it just clips 12 px of margin you
probably did not want anyway).

### Trim and centre

`trim_and_center` performs the final pass:

1. For each of the six frames, compute the tight non-transparent bounding
   box (`PIL.Image.getbbox`).
2. Compute the **union** of all six bounding boxes — the maximum width and
   the maximum height across the set.
3. Add **16 px of padding** (`max_w += 16; max_h += 16`).
4. Crop each frame to its own content, then paste it centred onto a
   transparent canvas of those final unified dimensions.

The result is six PNGs that are all exactly the same size, with the
character horizontally and vertically centred. This is what prevents the
character from "shaking" between frames at runtime.

---

## 4. Worked example: adding a Robot character

This walks through the slicer path end-to-end. If you are hand-authoring
PNGs, skip ahead to step 6.

1. **Prepare the sprite sheet.** Export a 1024 × 1024 px PNG with a
   `#00FF00` background and exactly **4 columns × 2 rows** of cells. Each
   cell must be 256 × 512 px. Place the robot's four walking frames in
   row 0 (left to right), and four pose candidates (some idle, some
   jumping) in row 1.
2. **Drop it in the scratch directory.** Save the sheet as
   `temp/images/Robot_sheet.png` at the project root. Create the
   `temp/images/` directory if it does not exist — it is git-ignored.
3. **Pick your idle and jump columns.** Look at row 1 and decide which
   cell is the idle pose and which is the jump/fall pose. Cell indices are
   0-based from the left. For this example, say idle is in column 1 and
   jump is in column 3.
4. **Add the config entry.** Open `scripts/slice_doom_band.py` and append
   to the `characters` list:

   ```python
   characters = [
       # … existing entries …
       {"name": "Robot", "file": "Robot_sheet.png", "jump": 3, "idle": 1},
   ]
   ```
5. **Run the slicer.** From the project root:

   ```bash
   python3 scripts/slice_doom_band.py
   ```

   Expected output (the slicer is verbose, one line per character):

   ```
   🎬 Processing Robot...
   ✅ Saved 6 processed frames to <…>/src/images/Robot (Width: NNNpx, Height: NNNpx)
   ```

   You should now have `src/images/Robot/0.png` through `src/images/Robot/5.png`.
6. **(Optional) Add dedicated drag frames.** If you have artwork for the
   drag-held pose, save it as `src/images/Robot/6.png` and
   `src/images/Robot/7.png`. Match the canvas dimensions of the other six
   files. Skip this step to let the runtime reuse `1.png` / `3.png` via
   the [fallback](#the-67--13-drag-frame-fallback).
7. **Install and reload.** From the project root:

   ```bash
   ./scripts/install.sh
   ```

   Then reload GNOME Shell (`Alt+F2` → `r` on X11; log out / log in on
   Wayland).
8. **Enable the character.** Open the GnomeDoom preferences (either via
   GNOME Extensions or the top-bar indicator's Settings entry). Expand
   the **Characters** group — `Robot` will be in the list, sorted
   alphabetically alongside the existing entries. Tick the checkbox.
9. **Verify.** A Robot should spawn on the desktop. Walk, idle, jump, and
   drag interactions should all animate. If a frame is missing or
   transparent-but-not-blank, watch `journalctl -f -o cat /usr/bin/gnome-shell`
   for `Pixbuf` load errors.

### Troubleshooting

| Symptom                                  | Likely cause                                                                |
| ---------------------------------------- | --------------------------------------------------------------------------- |
| Character does not appear in prefs list  | Folder not under `src/images/`, or extension not reinstalled / shell not reloaded. |
| Solid green halo around character        | Background colour is off-key from `#00FF00`; recolour the sheet or adjust thresholds in `clean_green_and_grid`. |
| Visible grid lines around character      | Increase the `border` value passed to `clear_borders` (default `12`).       |
| Character "shakes" between frames        | Frames have inconsistent canvas sizes. Re-run the slicer (which unifies them) or re-export hand-authored frames at a single canvas size. |
| Drag animation looks like the walk cycle | `6.png` / `7.png` are missing — this is the intended fallback. Add them to override. |

---

## 5. Reference files

- [`scripts/slice_doom_band.py`](../scripts/slice_doom_band.py) — the slicer.
- [`src/manager.js`](../src/manager.js) — frame loader; tries `0.png`–`7.png`,
  tolerates missing slots.
- [`src/gnomelet.js`](../src/gnomelet.js) — animation state machine; contains
  the 6/7 → 1/3 drag-frame fallback.
- [`src/prefs.js`](../src/prefs.js) lines 27–46 — auto-discovery of
  `src/images/` subdirectories.
- [`src/images/SkeletonGuitarist/`](../src/images/SkeletonGuitarist) —
  canonical example of a finished character output folder.
