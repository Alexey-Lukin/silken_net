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
  # ——— DOC-T.24 priority re-assess (rubric: TRL-horizon + STAGE + body's stated blocking-impact) ———
  # P1 -> P2 demotions (un-flatten the 73-item P1 bucket):
  "HW.4"        => { p: "P2" }, # self-healing: 20yr longevity claim, TRL6 (not near-term gate)
  "HW.11"       => { p: "P2" }, # conformal coating: decided (Parylene C), only choose+verify left
  "HW.14"       => { p: "P2" }, # winter energy: Queen Phase 3 (Starlink Mini) future, not 2.5
  "HW.16"       => { p: "P2" }, # thermal IP67: budget+backend done, minor hw charge-protect left
  "HW.26"       => { p: "P2" }, # PEEK creep lock: 20yr reliability, TRL7->8
  "FW.8"        => { p: "P2" }, # per-species Z OTA: production-dispatch deferred (all trees default)
  "FW.42"       => { p: "P2" }, # fauna Vcap guard: fauna pathway post-TRL7/Mongabay, gated
  "ARCH.40"     => { p: "P2" }, # fauna session: same fauna-future gating
  "E.60"        => { p: "P2" }, # Merkle CID: leaf done, per-tree follow-on founder-deferred
  "E.64"        => { p: "P2" }, # bio->economy audit done; real-signal activation ground-truth-gated
  "S2.4"        => { p: "P2" }, # observability hardening canonized; only SLO/error-budget left
  "PUMA-IPV6-1" => { p: "P2" }, # post-deploy IPv6 bind verification (minor verify task)
  "ARCH.35"     => { p: "P2" }, # Queen flash ring: scale-tier (100 Soldiers), gated on board-freeze
  "UNI.13a"     => { p: "P2" }, # 🌿 far-horizon (Mongabay pivot) — 🌿 should not sit at P1
  # P2 -> P1 promotion:
  "S6.20"       => { p: "P1" }  # real reliability bug: dead entropy alerts + stuck insurance payouts
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
