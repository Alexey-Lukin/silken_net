#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Build the committed presentation gallery (docs/images/cad/) — deterministic, re-runnable.
#
#   CEM-native drawings → SVG (vector; GitHub renders them inline from the blob).
#   ⛔ `wiki:sync` does NOT carry these, and this header said it did until 2026-09-11 — a fabricated
#   mechanism, measured: `lib/tasks/wiki.rake` copies an image only where a canon doc EMBEDS it as
#   `![…](…)`, and no canon doc embeds docs/images/cad. Want them on the wiki: embed one first.
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

# Stamp the provenance the drawing itself asks for. Without this the script — which is the PRESCRIBED
# way to republish the gallery — guarantees every published sheet carries `UNTRACKED (set CAD_REV=…)`,
# i.e. the one artefact an outsider reads is the one with no revision on it. `--dirty` is not decoration:
# a gallery built from an uncommitted tree must say so rather than name a commit it does not match.
export CAD_REV="${CAD_REV:-$(git rev-parse --short HEAD 2>/dev/null || echo UNTRACKED)$(git diff --quiet 2>/dev/null || echo -dirty)}"

echo "▸ drawings (SVG)…"
for c in ti_coin cathode_flange zone2_sleeve; do
  run draw "cem/$c.json"
  cp "out/$c.drawing.svg" "$GAL/$c.drawing.svg"
done
# mechanical_lock.zone1/.zone3.json and anchor_zone1.<sku>.json carry an UNDERSCORE `name`
# (mechanical_lock_zone1 / anchor_zone1_pine), so the output-artefact stem (out/<name>.*) does not equal
# the manifest filename stem — unlike the loop above.
for c in mechanical_lock.zone1 mechanical_lock.zone3 anchor_zone1.pine; do
  run draw "cem/$c.json"
done
cp out/mechanical_lock_zone1.drawing.svg "$GAL/mechanical_lock_zone1.drawing.svg"
cp out/mechanical_lock_zone3.drawing.svg "$GAL/mechanical_lock_zone3.drawing.svg"
# One species SKU only: the seven anchor sheets differ solely in lattice numbers, and the gallery is a
# published SNAPSHOT, not the deliverable set — the factory gets `draw` run per SKU. `pine` because the
# 3D render and the section reveal below already use it, so the gallery stays one consistent part.
cp out/anchor_zone1_pine.drawing.svg "$GAL/anchor_zone1_pine.drawing.svg"

# ⚠️ The renders are NOT byte-deterministic (a viewer screenshot), so this step churns PNGs even when no
# geometry moved. The drawings above are pure string/entity build and ARE deterministic. If you only
# changed `Drawing.cs` or a CEM's notes, run just the drawings loop and `git checkout` any PNG noise —
# committing a re-render that means nothing costs review attention on the one diff that does mean something.
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
