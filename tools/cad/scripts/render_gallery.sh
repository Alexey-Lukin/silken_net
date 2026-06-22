#!/usr/bin/env bash
# Build the committed presentation gallery (docs/images/cad/) — deterministic, re-runnable.
#
#   CEM-native drawings → SVG (vector; GitHub renders inline, wiki:sync carries it)
#   PicoGK native 3D renders → TGA → PNG (presentation-sized; GitHub raster)
#
# The SSOT stays cem/*.json + the .cs generators — these are PUBLISHED snapshots for fundraising /
# README / wiki, not source of truth (regenerate any time). STL stays gitignored (too big).
#
# Render is viewer-window-gated (PicoGK opens a GL window + screenshots it): macOS desktop OK; a
# headless/CI box needs a display (xvfb) or the f3d fallback on the STL.
#
# Usage:  tools/cad/scripts/render_gallery.sh
set -euo pipefail
export PATH="$HOME/.dotnet:$PATH"
cd "$(dirname "$0")/.."                                  # → tools/cad
GAL="../../docs/images/cad"; mkdir -p "$GAL"
run() { dotnet run --project src/SilkenCad -- "$@" >/dev/null; }

echo "▸ drawings (SVG)…"
for c in ti_coin cathode_flange; do
  run draw "cem/$c.json"
  cp "out/$c.drawing.svg" "$GAL/$c.drawing.svg"
done

echo "▸ 3D renders (PicoGK → TGA)…"
for c in ti_coin cathode_flange anchor_zone1.pine anchor_assembly; do
  run render "cem/$c.json"
done

echo "▸ section reveals (monolithic bus rod, 01_01 §1.4)…"
run section "cem/anchor_zone1.pine.json"      # anode close-up: rod core in the gyroid annulus
run section "cem/anchor_axial_stack.json"     # full path: rod anode → cathode channel → flange-top pad

echo "▸ TGA → PNG (presentation-sized 1600px)…"
for t in out/*.tga; do
  b="$(basename "$t" .tga)"
  sips -s format png -Z 1600 "$t" --out "$GAL/$b.png" >/dev/null    # macOS; CI: magick convert
done

echo "▸ gallery → docs/images/cad/"
ls -la "$GAL"
