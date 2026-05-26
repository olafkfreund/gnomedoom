#!/bin/bash
# scripts/record-demo.sh — Record a demo GIF for docs/assets/demo.gif
#
# Detects the current session type (X11 or Wayland) and uses the appropriate
# screen-capture toolchain to produce an optimised GIF.
#
# X11   : byzanz-record  →  gifsicle
# Wayland: wf-recorder → ffmpeg (frames) → gifski → gifsicle
#
# Usage:
#   bash scripts/record-demo.sh [--duration SECONDS] [--region X,Y,W,H]
#
# Options:
#   --duration SECONDS   Recording length in seconds          (default: 8)
#   --region X,Y,W,H    Capture region, e.g. 0,0,1920,1080
#                        X11 default: full screen
#                        Wayland default: interactive via slurp (if available)
#   --help               Show this message and exit
#
# Output:
#   docs/assets/demo.gif (overwritten on every run — safe to re-run)
#
# The script:
#   1. Verifies all required tools are present (prints install hints if not).
#   2. Records the screen for the requested duration.
#   3. Runs 'gifsicle -O3 --lossy=80' to shrink the GIF.
#   4. Prints the final file size and warns if it exceeds 5 MB.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DURATION=8
REGION=""
OUTPUT="docs/assets/demo.gif"
SIZE_LIMIT_BYTES=$(( 5 * 1024 * 1024 ))   # 5 MB

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --duration=*)
            DURATION="${1#*=}"
            shift
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --region=*)
            REGION="${1#*=}"
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/record-demo.sh [--duration SECONDS] [--region X,Y,W,H]

Record a demo GIF for docs/assets/demo.gif.
Detects X11 or Wayland automatically and uses the appropriate toolchain.

Options:
  --duration SECONDS   Recording length in seconds           (default: 8)
  --region X,Y,W,H    Capture region, e.g. 0,0,1920,1080
                       X11 default:     full screen
                       Wayland default: interactive via slurp (if available),
                                        otherwise full screen
  --help               Show this message and exit

Required tools (checked at runtime):
  X11:     byzanz-record, gifsicle
  Wayland: wf-recorder, ffmpeg, gifski, gifsicle
           Optional: slurp  (interactive region selection)

Output:
  docs/assets/demo.gif  — overwritten on every run (safe to re-run)
EOF
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1" >&2
            echo "   Run '$0 --help' for usage." >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# require <cmd> <install_hint>
require() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Required tool not found: $cmd" >&2
        [[ -n "$hint" ]] && echo "   Install hint: $hint" >&2
        exit 1
    fi
}

# parse_region "X,Y,W,H" → sets REGION_X REGION_Y REGION_W REGION_H
parse_region() {
    IFS=',' read -r REGION_X REGION_Y REGION_W REGION_H <<< "$1"
    if [[ -z "${REGION_X:-}" || -z "${REGION_Y:-}" || \
          -z "${REGION_W:-}" || -z "${REGION_H:-}" ]]; then
        echo "❌ --region must be in X,Y,W,H format (e.g. 0,0,1920,1080)" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Resolve paths and set up temp-file cleanup
# ---------------------------------------------------------------------------
mkdir -p "$REPO_ROOT/docs/assets"
OUT="$REPO_ROOT/$OUTPUT"

TMP_MP4="${TMPDIR:-/tmp}/gnomedoom-demo-$$.mp4"
TMP_FRAMES_DIR="${TMPDIR:-/tmp}/gnomedoom-frames-$$"

cleanup() {
    rm -f  "$TMP_MP4"
    rm -rf "$TMP_FRAMES_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Detect session type
# ---------------------------------------------------------------------------
SESSION="${XDG_SESSION_TYPE:-}"
if [[ -z "$SESSION" ]]; then
    if [[ -n "${DISPLAY:-}" ]]; then
        SESSION="x11"
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        SESSION="wayland"
    else
        echo "❌ Cannot detect session type." >&2
        echo "   Set XDG_SESSION_TYPE to 'x11' or 'wayland' and retry." >&2
        exit 1
    fi
fi
SESSION="${SESSION,,}"   # normalise to lowercase

echo "🖥️  Session type: $SESSION"
echo "⏱️  Duration:     ${DURATION}s"
echo "📄 Output:       $OUT"
[[ -n "$REGION" ]] && echo "📐 Region:       $REGION"
echo ""

# ---------------------------------------------------------------------------
# Record — session-specific paths
# ---------------------------------------------------------------------------
case "$SESSION" in

    # ------------------------------------------------------------------
    x11)
        require byzanz-record \
            "sudo apt install byzanz  (Ubuntu/Debian)  or  sudo dnf install byzanz  (Fedora)"
        require gifsicle \
            "sudo apt install gifsicle  (Ubuntu/Debian)  or  sudo dnf install gifsicle  (Fedora)"

        BYZANZ_ARGS=(
            "--duration=$DURATION"
            "--delay=1"
        )

        if [[ -n "$REGION" ]]; then
            parse_region "$REGION"
            BYZANZ_ARGS+=(
                "--x=$REGION_X"
                "--y=$REGION_Y"
                "--width=$REGION_W"
                "--height=$REGION_H"
            )
        fi

        # byzanz-record writes directly to the output GIF
        BYZANZ_ARGS+=("$OUT")

        echo "🎬 Starting byzanz-record (${DURATION}s recording with 1s initial delay)…"
        byzanz-record "${BYZANZ_ARGS[@]}"
        ;;

    # ------------------------------------------------------------------
    wayland)
        require wf-recorder \
            "sudo apt install wf-recorder  (Ubuntu/Debian)  or  sudo pacman -S wf-recorder  (Arch)"
        require ffmpeg \
            "sudo apt install ffmpeg  (Ubuntu/Debian)  or  sudo pacman -S ffmpeg  (Arch)"
        require gifski \
            "cargo install gifski  or  sudo pacman -S gifski  (Arch)"
        require gifsicle \
            "sudo apt install gifsicle  (Ubuntu/Debian)  or  sudo dnf install gifsicle  (Fedora)"

        WF_ARGS=("-f" "$TMP_MP4")

        if [[ -n "$REGION" ]]; then
            parse_region "$REGION"
            # wf-recorder expects geometry as "X,Y WxH"
            WF_ARGS+=("-g" "${REGION_X},${REGION_Y} ${REGION_W}x${REGION_H}")
        else
            if command -v slurp &>/dev/null; then
                echo "🖱️  Select capture region with your mouse…"
                GEOM="$(slurp)"
                WF_ARGS+=("-g" "$GEOM")
            else
                echo "⚠️  slurp not found; recording full screen." >&2
                echo "   Install 'slurp' for interactive region selection." >&2
            fi
        fi

        echo "🎬 Starting wf-recorder (${DURATION}s)…"
        # Use 'timeout' to stop recording after DURATION seconds.
        # timeout exits 124 on expiry, 0 if the process stops itself — both are fine.
        timeout "$DURATION" wf-recorder "${WF_ARGS[@]}" || true

        if [[ ! -s "$TMP_MP4" ]]; then
            echo "❌ wf-recorder did not produce output. Check that the Wayland capture portal is available." >&2
            exit 1
        fi

        # Convert MP4 → PNG frames → GIF
        echo "🔄 Extracting frames with ffmpeg (fps=20, 800 px wide)…"
        mkdir -p "$TMP_FRAMES_DIR"
        ffmpeg -i "$TMP_MP4" \
            -vf "fps=20,scale=800:-1:flags=lanczos" \
            "$TMP_FRAMES_DIR/frame-%04d.png" \
            -hide_banner -loglevel warning

        FRAME_COUNT=$(find "$TMP_FRAMES_DIR" -name 'frame-*.png' | wc -l)
        if [[ "$FRAME_COUNT" -eq 0 ]]; then
            echo "❌ ffmpeg produced no frames. The MP4 may be corrupted." >&2
            exit 1
        fi
        echo "   Extracted $FRAME_COUNT frames."

        echo "🎞️  Encoding GIF with gifski…"
        gifski -o "$OUT" "$TMP_FRAMES_DIR"/frame-*.png
        ;;

    # ------------------------------------------------------------------
    *)
        echo "❌ Unsupported session type: '$SESSION'. Expected 'x11' or 'wayland'." >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Verify the GIF was produced before optimising
# ---------------------------------------------------------------------------
if [[ ! -s "$OUT" ]]; then
    echo "❌ Recording step did not produce $OUT. Aborting." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Optimise with gifsicle
# ---------------------------------------------------------------------------
echo ""
echo "✂️  Optimising with gifsicle -O3 --lossy=80…"
gifsicle -O3 --lossy=80 "$OUT" -o "$OUT"

# ---------------------------------------------------------------------------
# Report file size
# ---------------------------------------------------------------------------
SIZE_BYTES=$(stat -c '%s' "$OUT" 2>/dev/null || stat -f '%z' "$OUT")
SIZE_KB=$(( SIZE_BYTES / 1024 ))

# Simple fixed-point MB: 1 decimal place
SIZE_MB_INT=$(( SIZE_BYTES / 1048576 ))
SIZE_MB_FRAC=$(( (SIZE_BYTES % 1048576) * 10 / 1048576 ))

echo ""
echo "📊 Output: $OUT"
printf "   Size:   %d KB  (%d.%d MB)\n" "$SIZE_KB" "$SIZE_MB_INT" "$SIZE_MB_FRAC"

if (( SIZE_BYTES > SIZE_LIMIT_BYTES )); then
    echo ""
    echo "⚠️  WARNING: file exceeds the 5 MB guideline."
    echo "   Tips to reduce size:"
    echo "     • Shorten the recording (--duration)"
    echo "     • Capture a smaller region (--region)"
    echo "     • Lower the frame rate (edit fps=20 in this script)"
    echo "     • Increase lossy compression (gifsicle --lossy=100 or higher)"
    exit 0   # not a hard error; the file is still usable
fi

echo ""
echo "✅ Under 5 MB — ready to commit:"
echo "   git add $OUTPUT"
echo "   git commit -m 'docs: add demo.gif showing skeleton cast in action'"
