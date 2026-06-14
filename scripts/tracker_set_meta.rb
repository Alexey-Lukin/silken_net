#!/usr/bin/env ruby
# frozen_string_literal: true

#
# scripts/tracker_set_meta.rb — set the P (priority) / WHO (виконавець) field on
# `docs/00_07_Action_Plan_Tracker.md` `#### ` item meta-lines, addressed BY ID.
#
# Why a tool: meta-lines repeat ("- **P1** · 👤 · ⚪ · → `01_02`" is non-unique),
# so string-Edit is fragile. This targets the item by its `#### ID —` heading,
# then rewrites ONLY the P and/or WHO field of that item's meta-line — STAGE,
# canon-ref and everything else are byte-preserved (zero-loss by construction;
# `git diff` shows nothing but the targeted meta-lines).
#
# Usage: edit OVERRIDES, run `ruby scripts/tracker_set_meta.rb`, review `git diff`.
# Idempotent: re-running with the same map is a no-op.
#
# Read-only except the one file. Mirrors the per-ID-override pattern of stage_migrate.rb.

FILE = File.expand_path("../docs/00_07_Action_Plan_Tracker.md", __dir__)

# ID => { p: "P2", who: "🤖+👤" }   — set only the field(s) you want changed.
OVERRIDES = {
  # ——— DOC-T.23 WHO re-audit (open-work semantic, 00_07 intro §WHO) ———
  "HW.3"   => { who: "🤖+👤" }, # open 🤖 in-silico MD-permeation residual
  "HW.18"  => { who: "🤖+👤" }, # open 🤖 "update 03_02 with decision" residual
  "HW.19"  => { who: "🤖+👤" }, # open 🤖 concept-validate + backend-VOC residuals
  "UNI.9"  => { who: "🤖+👤" }, # open 🤖 SLA R-cluster residual
  "HW.32"  => { who: "👤" },    # 🤖 built BME280; only 👤 bench remains open
  "INF.6"  => { who: "👤" },    # 🤖 coap_smoke shipped; only 👤 repo-vars+smoke open
  "UNI.15" => { who: "👤" }    # 🤖 prior-art landscape done; only 👤 TISC/trademark open
}

# - **P1** · 🤖+👤 · 🟢 · → `ref`
META_RE = /\A(- \*\*)(P[0-3])(\*\* · )([^·]+?)( · )([⚪🟡🟢🔗🌿])( · .*)\z/u
ITEM_RE = /\A####\s+(?:🌿\s+)?([A-Za-z0-9.\-]+)\s+—/

lines = File.readlines(FILE)
changed = []
seen = []

i = 0
while i < lines.size
  m = lines[i].match(ITEM_RE)
  if m && OVERRIDES.key?(m[1])
    id = m[1]
    seen << id
    ov = OVERRIDES[id]
    j = i + 1
    j += 1 while j < lines.size && !lines[j].start_with?("- **P") &&
                 !lines[j].start_with?("#### ") && !lines[j].start_with?("## ")
    if (mm = lines[j].chomp.match(META_RE))
      newp = ov[:p] || mm[2]
      newwho = ov[:who] || mm[4]
      newline = "#{mm[1]}#{newp}#{mm[3]}#{newwho}#{mm[5]}#{mm[6]}#{mm[7]}\n"
      if newline != lines[j]
        changed << "  #{id}: #{mm[2]}/#{mm[4]} -> #{newp}/#{newwho}"
        lines[j] = newline
      end
    else
      warn "!! #{id}: meta-line not matched at L#{j + 1}: #{lines[j].inspect}"
    end
  end
  i += 1
end

File.write(FILE, lines.join)
puts "Changed #{changed.size} meta-line(s):"
puts changed
missing = OVERRIDES.keys - seen
warn "!! IDs not found in tracker: #{missing.inspect}" unless missing.empty?
