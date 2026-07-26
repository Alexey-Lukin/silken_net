#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# scripts/fix_stale_anchors.rb — surgical fixer for stale #anchor fragments in
# cross-doc links, surfaced by `rake docs:graph` (DOC.13 round-3). Each entry is
# an EXACT href-anchor string → its corrected form (verified against the target's
# real GitHub-slug heading). Idempotent + self-reporting: replaces the exact
# substring, prints per-file hit count. Dry-run by default; APPLY=1 writes.
#
#   ruby scripts/fix_stale_anchors.rb         # dry-run (report only)
#   APPLY=1 ruby scripts/fix_stale_anchors.rb # apply

APPLY = ENV["APPLY"] == "1"
ROOT  = File.expand_path("..", __dir__)

# file (basename) => [[stale_substring, fixed_substring], ...]. Trailing ')' anchors
# the end of the href so a fix can't match a prefix of a longer anchor.
FIXES = {
  # #1 self-link: "### 1.2. Gap #2 …" → slug starts "12-" (no leading hyphen; no emoji)
  "00_08_Beyond_TRL9_Planetary_Roadmap.md" => [
    [ "#-12-gap-2--self-evolving-behaviour-on-device-edge-ai)",
      "#12-gap-2--self-evolving-behaviour-on-device-edge-ai)" ]
  ],
  # #2: heading "### 4.5а Downlink Opcode Map — Canonical SSOT [DOC.4]" → no leading
  # hyphen, full suffix.
  "03_02_Queen_Gateway_Firmware.md" => [
    [ "#-45а-downlink-opcode-map)",
      "#45а-downlink-opcode-map--canonical-ssot-doc4)" ]
  ],
  # #3: 02_03 has no English "sensitivity-analysis"; the sensitivity scenarios live
  # under §9 "Розрахунок Енергетичного Балансу" (⚡ → leading hyphen).
  "03_03_TinyML_Acoustic_Inference.md" => [
    [ "#9-sensitivity-analysis)",
      "#-9-розрахунок-енергетичного-балансу-з-урахуванням-ккд)" ]
  ],
  # #5: heading "### `SilkenNet::SeedDerivation` 🔐 [SEC.11]" → slug gained "--sec11".
  "05_02_Proof_of_Growth_Pipeline.md" => [
    [ "#silkennetseedderivation-)",
      "#silkennetseedderivation--sec11)" ]
  ],
  # #6: 03_05 PQC H2 is "## 🛡️ 10. PQC Migration Roadmap …" (anchor "-10-…"); the link
  # said "-11-" (the 11.x children misled it). NB sep. anomaly: H2 "10." vs 11.x kids.
  # #7 (×2, lines 129+407): label already reads "08_02 §2" (= ЧДТУ) but the href anchor
  # still points at the §8 synergy section dissolved in Taxonomy-P4 → repoint to real §2.
  "08_01_Joint_Publications_and_IP_Strategy.md" => [
    [ "#-11-pqc-migration-roadmap-trl-stratified-post-quantum-layering)",
      "#-10-pqc-migration-roadmap-trl-stratified-post-quantum-layering)" ],
    [ "#8-міжуніверситетська-синергія-чдту--чну-фотіус)",
      "#-2-чдту--черкаський-державний-технологічний-університет)" ]
  ]
}.freeze

total = 0
FIXES.each do |base, pairs|
  path = File.join(ROOT, "docs", base)
  text = File.read(path)
  orig = text.dup
  pairs.each do |stale, fixed|
    n = text.scan(stale).size
    total += n
    puts "#{base}: '#{stale}' ×#{n}" + (n.zero? ? "  ⚠️ NOT FOUND" : " → '#{fixed}'")
    text = text.gsub(stale, fixed)
  end
  if APPLY && text != orig
    File.write(path, text)
    puts "  ✍️  written"
  end
end
puts APPLY ? "APPLIED (#{total} hits)" : "DRY-RUN (#{total} hits) — re-run with APPLY=1"
