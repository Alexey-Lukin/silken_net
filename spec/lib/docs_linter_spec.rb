# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/docs_linter"

# [SSOT anti-drift] Unit coverage for the structural doc-linter (rake
# docs:check_refs). Pure functions over fixture strings — no DB, no file I/O.
RSpec.describe DocsLinter do
  describe ".trl_matrix_range_violations" do
    it "flags per-module cells that are a range rather than a single 1-9" do
      md = <<~MD
        | Модуль | TRL | Цільовий | Блокер |
        |--------|-----|----------|--------|
        | 01 Materials & EBFC | 4 | 6 | Lab |
        | 05 Web3 Pipeline | 8-9 | 9 | SFC |
        | 06 DevOps | 5-6 | 9 | deploy |
      MD
      expect(described_class.trl_matrix_range_violations(md))
        .to contain_exactly(
          a_string_matching(/05 Web3 Pipeline.*8-9/),
          a_string_matching(/06 DevOps.*5-6/)
        )
    end

    it "ignores NASA-scale stage rows (first cell '**TRL n-m**', not 'NN ...')" do
      expect(described_class.trl_matrix_range_violations("| **TRL 5-6** | Прототипування | Lab |\n"))
        .to be_empty
    end

    it "passes a clean single-value matrix" do
      md = "| 03 Firmware | 6 | 8 | AES |\n| 10 Security | 7 | 9 | keys |\n"
      expect(described_class.trl_matrix_range_violations(md)).to be_empty
    end
  end

  describe ".trl_range_consistency" do
    let(:matrix) do
      <<~MD
        | **TRL 5-6** | Прототипування | Lab |
        | Модуль | TRL | Цільовий | Блокер |
        |--------|-----|----------|--------|
        | 01 Materials & EBFC | 3 | 6 | Ti-coin |
        | 03 Firmware | 6 | 8 | AES |
        | 06 DevOps | 5 | 9 | deploy; 06_01=4, не на критичному шляху |
      MD
    end

    it "passes when every doc member-TRL sits within its module band" do
      trls = { "01_01_Anchor" => 3, "03_01_Firmware" => 6, "06_02_Akash" => 5 }
      expect(described_class.trl_range_consistency(matrix, trls)).to be_empty
    end

    # Звужено 2026-08-22: член НИЖЧЕ рядка лишається легітимним (off-critical-path,
    # успадкований System-lock) — але клітинка блокера мусить НАЗВАТИ його поіменно.
    # Доти нижньої межі не було зовсім, і рядок 4 при члені 3 проходив мовчки, попри
    # те що §1 жирним каже «рядок = МІНІМУМ». Матриця фікстури несе `06_01=4` у
    # клітинці рядка 06 — саме тому цей приклад лишається зеленим.
    it "allows a sub-doc ABOVE its row, and BELOW it WHEN the blocker cell names the gating doc" do
      trls = { "03_05_Crypto" => 6, "06_01_Kamal" => 4, "06_03_Prom" => 6 }
      expect(described_class.trl_range_consistency(matrix, trls)).to be_empty
    end

    it "FLAGS a member below the row when the cell names NO gating doc — the silent gap" do
      silent = matrix.sub("06_01=4, не на критичному шляху", "fallback path")
      hits = described_class.trl_range_consistency(silent, { "06_01_Kamal" => 4, "06_03_Prom" => 6 })
      expect(hits).to include(a_string_matching(/module 06 row 5 is ABOVE its lowest member 4 \(06_01\)/))
    end

    it "flags a doc claiming a member-TRL above its module target (ceiling)" do
      hits = described_class.trl_range_consistency(matrix, { "01_03_EBFC" => 7 })
      expect(hits).to contain_exactly(a_string_matching(/01_03_EBFC.*member-TRL 7 > module 01 target 6/))
    end

    it "flags a matrix row whose current exceeds its target (band inverted)" do
      expect(described_class.trl_range_consistency("| 04 Backend | 9 | 8 | x |\n", {}))
        .to contain_exactly(a_string_matching(/module 04 current TRL 9 > target 8/))
    end

    it "flags a row sitting above EVERY one of its sub-docs (inflated aggregate)" do
      hits = described_class.trl_range_consistency(matrix, { "06_01_Kamal" => 4, "06_06_DR" => 4 })
      expect(hits).to contain_exactly(a_string_matching(/module 06 current TRL 5 > its highest sub-doc member-TRL 4/))
    end

    it "ignores the NASA-stage table rows ('**TRL n-m**', not 'NN ...') and module-less docs" do
      expect(described_class.trl_range_consistency("| **TRL 7-8** | Кваліфікація | Prod |\n", {})).to be_empty
      expect(described_class.trl_range_consistency(matrix, { "99_99_Ghost" => 9 })).to be_empty
    end
  end

  describe ".manifest_trl_parity" do
    let(:matrix) do
      <<~MD
        | Модуль | TRL | Цільовий | Блокер |
        |--------|-----|----------|--------|
        | 01 Materials & EBFC | 3 | 6 | Ti-coin |
        | 02 Hardware & BOM | 4 | 6 | BQ25570 |
        | 03 Firmware | 6 | 8 | AES |
        | 04 Backend Rails | 8 | 9 | RSpec |
        | 05 Web3 Pipeline | 8 | 9 | SFC |
      MD
    end
    # One bullet per registered layer, mirroring the real §5 shapes: a plain claim,
    # a two-member claim whose module reads at the LOWER one, and prose digits that
    # are targets rather than assertions.
    let(:manifest) do
      <<~MD
        - **Backend (Rails 8.1, 12-chain):** TRL 8. External audit is the TRL-9 gate.
        - **Firmware (STM32WLE5JC Soldier):** TRL 6. Running on hardware.
        - **Hardware capsule:** TRL 6 — prototyped. **BQ25570 MPPT power chain and EDLC buffer:** TRL 4 — breadboard.
        - **Tri-zone coaxial anchor and Gen-2.0 EBFC stack:** TRL 3. Next (physical TRL 4): in-vitro.
      MD
    end

    it "passes when every public layer matches its 00_03 §1 module" do
      expect(described_class.manifest_trl_parity(matrix, manifest)).to be_empty
    end

    it "reads a multi-member bullet at the LOWEST claim (00_03 §1 aggregate rule)" do
      # Dropping the TRL-4 power chain leaves the capsule's 6 facing module 02 = 4.
      broken = manifest.sub("**BQ25570 MPPT power chain and EDLC buffer:** TRL 4 — breadboard.", "the power chain.")
      expect(described_class.manifest_trl_parity(matrix, broken))
        .to contain_exactly(a_string_matching(/PUBLIC TRL 6 for "Hardware capsule".*module 02 = 4/))
    end

    it "flags the manifesto drifting above canon" do
      expect(described_class.manifest_trl_parity(matrix, manifest.sub("Soldier):** TRL 6", "Soldier):** TRL 7")))
        .to contain_exactly(a_string_matching(/PUBLIC TRL 7 for "Firmware".*module 03 = 6/))
    end

    it "flags canon moving away from the manifesto (the gate is two-directional)" do
      expect(described_class.manifest_trl_parity(matrix.sub("| 03 Firmware | 6 |", "| 03 Firmware | 8 |"), manifest))
        .to contain_exactly(a_string_matching(/PUBLIC TRL 6 for "Firmware".*module 03 = 8/))
    end

    it "flags a layer whose public claim silently disappears (the registry is a SET pin)" do
      expect(described_class.manifest_trl_parity(matrix, manifest.sub(/^- \*\*Hardware capsule.*\n/, "")))
        .to contain_exactly(a_string_matching(/states no TRL for "Hardware capsule"/))
    end

    it "flags a TRL claim by a layer nobody declared an owner for" do
      expect(described_class.manifest_trl_parity(matrix, "#{manifest}- **Quantum layer:** TRL 5.\n"))
        .to contain_exactly(a_string_matching(/unregistered layer "Quantum layer"/))
    end

    # The load-bearing near-miss: the anchor is the CLAIM FORM, never the digit.
    # A min-over-every-TRL-number rule would go red on each of these while the
    # manifesto is perfectly honest — and they are all real §5 phrasings.
    it "ignores TRL digits that are prose — a target, a norm, a stage left behind" do
      prose = "#{manifest}We are past the TRL 2 stage; per ISO 16290 in-silico = TRL 3, and TRL-9 is the gate.\n"
      expect(described_class.manifest_trl_parity(matrix, prose)).to be_empty
    end

    it "says so instead of passing when the 00_03 band cannot be parsed at all" do
      expect(described_class.manifest_trl_parity("no table here\n", manifest))
        .to contain_exactly(a_string_matching(/band unreadable.*never measured/))
    end
  end

  describe ".canon_blocker_sections" do
    it "flags a '## 🛑 Блокери' section heading" do
      md = "## 🎯 Мета\n## 🛑 Блокери\n### 🟡 BLOCKER-2: AT blocking\n"
      expect(described_class.canon_blocker_sections(md)).to contain_exactly("## 🛑 Блокери")
    end

    it "flags a '## ✅ Архів вирішених блокерів' section heading" do
      expect(described_class.canon_blocker_sections("## ✅ Архів вирішених блокерів\n"))
        .to contain_exactly("## ✅ Архів вирішених блокерів")
    end

    it "flags open ('🛑 Відкриті Блокери') and resolved ('✅ Закриті Блокери') variants" do
      md = "## 🛑 Відкриті Блокери\n## ✅ Закриті Блокери (PR #254)\n"
      expect(described_class.canon_blocker_sections(md))
        .to contain_exactly("## 🛑 Відкриті Блокери", "## ✅ Закриті Блокери (PR #254)")
    end

    it "flags a '## 🚨 Блокери …' heading (🚨 was outside the emoji set — 05_02 slipped through)" do
      expect(described_class.canon_blocker_sections("## 🚨 Блокери та статус\n"))
        .to contain_exactly("## 🚨 Блокери та статус")
    end

    it "does not flag a status-emoji heading lacking a blocker/archive word" do
      md = "## 🛑 Архітектурні правила (фіксоване)\n## ✅ Governance DAO — Реалізовано\n"
      expect(described_class.canon_blocker_sections(md)).to be_empty
    end

    it "does not flag body prose that merely mentions a blocker/constraint" do
      md = "## 🔐 1. Crypto\nLoRa uses AES-128-ECB (transitional, no MAC) — see 00_07 §03.\n"
      expect(described_class.canon_blocker_sections(md)).to be_empty
    end

    it "skips a blocker heading that is only a skeleton example inside a ``` fence" do
      md = "## 🎯 Мета\n```\n## 🛑 Блокери\n```\n## 🔗 Cross-references\n"
      expect(described_class.canon_blocker_sections(md)).to be_empty
    end
  end

  describe ".conformance_violations" do
    let(:h1) { "# 03_05: Crypto\n" }
    let(:ok) { "#{h1}## ✅ Статус\n## 🔗 Cross-references\n## 📑 Зміст\n<!-- TOC:AUTO:START -->\n<!-- TOC:AUTO:END -->\n" }

    it "passes a doc carrying Статус + top Cross-references + auto-ToC markers" do
      expect(described_class.conformance_violations("03_05_Crypto", ok)).to be_empty
    end

    it "flags each missing standard element" do
      expect(described_class.conformance_violations("01_01_Anchor", "# 01_01: Anchor\n## 🎯 Мета\nbody\n"))
        .to contain_exactly("## ✅ Статус", "## 🔗 Cross-references", "📑 auto-ToC markers")
    end

    it "exempts the index, the tracker, and appendix docs" do
      bare = "# Title\n## 🎯 Мета\n"
      expect(described_class.conformance_violations("00_00_SSOT_Index", bare)).to be_empty
      expect(described_class.conformance_violations("00_07_Action_Plan_Tracker", bare)).to be_empty
      # the *_Appendix NAME-branch exempts a legacy-appendix doc:
      expect(described_class.conformance_violations("07_09_Some_Field_Appendix", bare)).to be_empty
    end

    it "ignores non-canon filenames (README, etc.)" do
      expect(described_class.conformance_violations("README", "x")).to be_empty
    end

    # [DOC-T.49] H1 is the one skeleton element NO doc may lack — checked before the
    # skeleton exemptions, which exist only because 00_00/00_07/appendix legitimately
    # carry no ✅ Статус.
    it "flags a missing H1 even in an otherwise-exempt doc" do
      expect(described_class.conformance_violations("00_07_Action_Plan_Tracker", "## 🎯 Мета\n"))
        .to contain_exactly("# H1 heading (first non-blank line)")
    end

    # The real defect: an edit glued the H1 into a preceding paragraph, leaving
    # `#🔴 …` — no space after `#`, so CommonMark reads a paragraph, not a heading.
    it "flags `#x` with no space after the hash (not a heading per CommonMark)" do
      glued = "#🔴 **абзац, що з'їв заголовок.** ## 00_07: Action Plan Tracker\n## 🎯 Мета\n"
      expect(described_class.conformance_violations("00_07_Action_Plan_Tracker", glued))
        .to contain_exactly("# H1 heading (first non-blank line)")
    end

    it "tolerates leading blank lines before the H1" do
      expect(described_class.conformance_violations("00_07_Action_Plan_Tracker", "\n\n# Title\n")).to be_empty
    end

    it "does not accept a deeper heading as the H1" do
      expect(described_class.conformance_violations("00_07_Action_Plan_Tracker", "## Not an H1\n"))
        .to contain_exactly("# H1 heading (first non-blank line)")
    end
  end

  describe ".rtc_register_allocation_drift" do
    it "flags a non-owner doc claiming a register is in reserve/free" do
      hits = described_class.rtc_register_allocation_drift(
        "03_02_Queen", "anti-storm bitmap — DR15 наразі резерв (ARCH.28)\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("DR15")
    end

    it "catches the RTC_BKP_DRn form (leading underscore blocks plain word-boundary)" do
      expect(described_class.rtc_register_allocation_drift(
        "03_03_TinyML", "RTC_BKP_DR15 вільний слот для майбутньої фічі\n").size).to eq(1)
    end

    it "exempts the owner docs (03_01 RTC map + 03_05 FC/nonce SSOT)" do
      claim = "вільний лише DR15\n"
      expect(described_class.rtc_register_allocation_drift("03_01_Firmware_Lifecycle_and_DMA", claim)).to be_empty
      expect(described_class.rtc_register_allocation_drift("03_05_Hardware_Crypto", claim)).to be_empty
    end

    it "ignores a plain reference with no availability word" do
      expect(described_class.rtc_register_allocation_drift(
        "03_02_Queen", "Frame Counter живе у RTC_BKP_DR15 (зайнято FW.2)\n")).to be_empty
    end

    it "does not match 'звільнило' (freed elsewhere) or 'reserved:' bit-fields" do
      expect(described_class.rtc_register_allocation_drift(
        "00_07_Tracker", "RTC DR10+DR12 (звільнило DR11 під слот)\n")).to be_empty
      expect(described_class.rtc_register_allocation_drift(
        "03_03_TinyML", "DR0 = [panic:16 | reserved:8 | acoustic:8]\n")).to be_empty
    end

    it "skips table rows and fenced code" do
      expect(described_class.rtc_register_allocation_drift(
        "04_06_Testing", "| DR15 | резерв | spare |\n")).to be_empty
      expect(described_class.rtc_register_allocation_drift(
        "04_06_Testing", "```\nDR15 вільний\n```\n")).to be_empty
    end
  end

  describe ".rtc_register_out_of_range" do
    it "flags a phantom DR>19 (the chip has only DR0..DR19)" do
      hits = described_class.rtc_register_out_of_range("Q-table state buffer у RTC backup registers DR20-DR31.\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("DR20")
    end

    it "catches the phantom inside a table row (sibling guard skips tables → blind spot)" do
      expect(described_class.rtc_register_out_of_range(
        "| Edge RL | episode memory | RTC backup registers DR20-DR31 буфер |\n").size).to eq(1)
    end

    it "catches the RTC_BKP_DRn form" do
      expect(described_class.rtc_register_out_of_range("HAL_RTCEx_BKUPWrite(&hrtc, RTC_BKP_DR24, z)\n").size).to eq(1)
    end

    it "does not flag a line that marks the registers dead" do
      expect(described_class.rtc_register_out_of_range("⚠️ DEPRECATED — DR20-DR23 не існують\n")).to be_empty
      expect(described_class.rtc_register_out_of_range("специфікація (DR24-DR26) фізично неможлива\n")).to be_empty
      expect(described_class.rtc_register_out_of_range("`RTC_BKP_DR20..DR23` слід читати як Flash-KV\n")).to be_empty
      expect(described_class.rtc_register_out_of_range("RTC budget — DR0..DR19 усі зайняті (новий DR20 нема куди)\n")).to be_empty
    end

    it "skips fenced code (deprecated example blocks live there)" do
      expect(described_class.rtc_register_out_of_range("```\nRTC_BKP_DR20 — CRITICAL_Z_MIN\n```\n")).to be_empty
    end

    it "ignores valid DR0..DR19" do
      expect(described_class.rtc_register_out_of_range("Lorenz state lives in DR16/DR17/DR18, magic DR19\n")).to be_empty
    end
  end

  describe ".lorenz_formula_drift" do
    it "flags the β literal `8.0 / 3.0` re-stated outside the owner" do
      hits = described_class.lorenz_formula_drift("05_01_Multichain", "beta  = 8.0 / 3.0\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("03_04 §1.2")
    end

    it "exempts the owner docs (03_04 Lorenz + 03_01 firmware-lifecycle)" do
      code = "BASE_BETA = 8.0 / 3.0\n"
      expect(described_class.lorenz_formula_drift("03_04_mruby_Lorenz_Attractor", code)).to be_empty
      expect(described_class.lorenz_formula_drift("03_01_Firmware_Lifecycle_and_DMA", code)).to be_empty
    end

    it "skips inline mentions, firmware-file refs and table rows (only β assignments flag)" do
      expect(described_class.lorenz_formula_drift(
        "00_01_Arch", "рахує ідентично firmware mruby (8.0/3.0)\n"
      )).to be_empty
      expect(described_class.lorenz_formula_drift(
        "05_02_Pipeline", "`firmware/bio_contracts/bio_contract.rb` — BASE_BETA = 8.0 / 3.0\n"
      )).to be_empty
      expect(described_class.lorenz_formula_drift(
        "05_06_Governance", "| `BETA = 8.0/3.0` | `Attractor` | Lorenz |\n"
      )).to be_empty
    end
  end

  describe ".bio_potential_as_metric" do
    it "flags the positive claim that routing picks a relay by bio_potential" do
      hits = described_class.bio_potential_as_metric(
        "Маршрутизація обирає реле за `bio_potential` вузла — найздоровіше дерево ретранслює.\n"
      )
      expect(hits.size).to eq(1)
      expect(hits.first).to include("ARCH.11")
    end

    # 🔴 Несучий, не ввічливий: сама відмова МУСИТЬ назвати токен, щоб його
    # заборонити, тож без цього винятку гейт червонів би на ADR, який його й завів.
    it "exempts the rejection itself — the ADR must name the token to forbid it" do
      expect(described_class.bio_potential_as_metric(
        "`bio_potential` як метрику маршрутизації відхилено (observer-effect)\n"
      )).to be_empty
      expect(described_class.bio_potential_as_metric(
        "bio_potential is the measurand and is NEVER a routing resource\n"
      )).to be_empty
    end

    # Owner-less: жоден док не звільнений, бо термін хибний СКРІЗЬ — на відміну
    # від σ/ρ/β, де власник має право називати значення.
    it "has no owner exemption — the same positive claim reds in any doc" do
      expect(described_class.bio_potential_as_metric("relay chosen by bio potential\n").size).to eq(1)
      expect(described_class.bio_potential_as_metric("BIO-POTENTIAL drives the route\n").size).to eq(1)
    end

    it "skips a table row even though its content would otherwise match" do
      expect(described_class.bio_potential_as_metric("| metric | bio_potential | приклад |\n")).to be_empty
    end

    # Гілка «рядок узагалі не містить токена» — найчастіший шлях у проді (кожен
    # рядок кожного доку), і без цього прикладу вона не виконувалась жодного разу.
    it "is silent on prose that does not mention the token at all" do
      expect(described_class.bio_potential_as_metric(
        "Маршрутизація обирає реле за `hop_count` і запасом Vcap.\n"
      )).to be_empty
    end
  end

  describe ".telemetry_log_chain_hash_drift" do
    it "flags the positive false claim that telemetry_logs has a chain_hash column" do
      hits = described_class.telemetry_log_chain_hash_drift(
        "Merkle Tree над `TelemetryLog.chain_hash` значеннями за тиждень\n"
      )
      expect(hits.size).to eq(1)
      expect(hits.first).to include("05_02 §E.60")
    end

    it "exempts negation/explanation lines (the drift-fix must name the wrong token to forbid it)" do
      expect(described_class.telemetry_log_chain_hash_drift(
        "leaf = Z-based, НЕ `TelemetryLog.chain_hash` (такої колонки немає)\n"
      )).to be_empty
    end

    it "does not flag the legit chain_hash homes (audit_logs / ethereum_anchors)" do
      expect(described_class.telemetry_log_chain_hash_drift("AuditLog.chain_hash chains the audit log\n")).to be_empty
      expect(described_class.telemetry_log_chain_hash_drift("ethereum_anchors.chain_hash component of state_root\n")).to be_empty
    end

    it "skips a table row even though its content would otherwise match" do
      expect(described_class.telemetry_log_chain_hash_drift(
        "| leaf | `TelemetryLog.chain_hash` | приклад |\n")).to be_empty
    end
  end

  describe ".growth_points_clamp_drift" do
    it "flags the retired `clamp(reward, 10, 63)` wire range outside the owner" do
      hits = described_class.growth_points_clamp_drift("05_02_Pipeline", "growth_points = clamp(reward, 10, 63)\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("metabolic_health")
    end

    it "flags the retired clamp even inside a table cell (the real manifest:78 drift)" do
      row = "| 2 ≤ Z ≤ 45 | homeostasis | `clamp(50 − |Z − 29|, 10, 63)` |\n"
      expect(described_class.growth_points_clamp_drift("manifest", row)).not_to be_empty
    end

    it "exempts the owner doc (03_04 §4.3, may keep history) + standard/tracker" do
      old = "`(reward / 2).clamp(5, 31)` from `50 - deviation`\n"
      expect(described_class.growth_points_clamp_drift("03_04_mruby_Lorenz_Attractor", old)).to be_empty
      expect(described_class.growth_points_clamp_drift("00_06_SSOT_Documentation_Standard", old)).to be_empty
      expect(described_class.growth_points_clamp_drift("00_07_Action_Plan_Tracker", old)).to be_empty
    end

    it "[E.63] flags retired `(reward / 2)` / `50 - deviation` outside owner (03_01 no longer exempt)" do
      expect(described_class.growth_points_clamp_drift("03_01_Firmware_Lifecycle_and_DMA", "growth_points = (reward / 2).clamp(5, 31)\n")).not_to be_empty
      expect(described_class.growth_points_clamp_drift("05_02_Pipeline", "reward = 50 - deviation.round\n")).not_to be_empty
    end

    it "[E.63] does NOT flag the live metabolic form `5 + m * 26` / metabolic_health" do
      expect(described_class.growth_points_clamp_drift("05_02_Pipeline", "growth_points = (5 + m * 26).round.clamp(5, 31)\n")).to be_empty
      expect(described_class.growth_points_clamp_drift("03_03_TinyML", "m = metabolic_health(delta_t_s)\n")).to be_empty
    end
  end

  describe ".status_byte_layout_drift" do
    it "flags the retired `status << 6` pack (was bits 7..6) in a mirror" do
      hits = described_class.status_byte_layout_drift("05_02_Pipeline", "payload_byte = (status << 6) | growth_points\n")
      expect(hits).not_to be_empty
      expect(hits.first).to include("0x1F")
    end

    it "flags the retired 6-bit growth mask `0x3F` near a StatusByte keyword" do
      expect(described_class.status_byte_layout_drift("04_02_Business_Logic_and_Services", "growth_points = status_byte & 0x3F\n")).not_to be_empty
    end

    it "flags the retired `bits 7..6` status position in prose (no HIST marker)" do
      expect(described_class.status_byte_layout_drift("03_01_Firmware_Lifecycle_and_DMA", "StatusByte: Status:2 (bits 7..6) | GrowthPoints:6\n")).not_to be_empty
    end

    it "flags a retired 6-bit growth width even inside a table cell (NOT table-skipped)" do
      expect(described_class.status_byte_layout_drift("05_02_Pipeline", "| byte 10 | growth_points 6-bit (0..63) |\n")).not_to be_empty
    end

    it "does NOT flag the live layout (`<< 5` / mask `0x1F`)" do
      live = "StatusByte pack (status << 5) | growth_points; unpack (status_byte & 0x1F)\n"
      expect(described_class.status_byte_layout_drift("05_02_Pipeline", live)).to be_empty
    end

    it "exempts a historical migration note (the owner's `6 → 5` / `bits 7..6 → 6..5`)" do
      expect(described_class.status_byte_layout_drift("03_05_Hardware_Symmetric_Crypto_and_Security", "growth зменшено з 6 → 5 бітів (StatusByte)\n")).to be_empty
      expect(described_class.status_byte_layout_drift("03_01_Firmware_Lifecycle_and_DMA", "Status переїхав з bits 7..6 → 6..5 (StatusByte)\n")).to be_empty
    end

    it "does NOT false-positive proxy hex/width tokens near a StatusByte keyword" do
      expect(described_class.status_byte_layout_drift("03_01_Firmware_Lifecycle_and_DMA", "StatusByte diag: hiwater & 0x3FFF; vm_error & 0x7F survives\n")).to be_empty
      expect(described_class.status_byte_layout_drift("03_06_Factory", "PanicFlag context: 96-біт UID трьома словами\n")).to be_empty
    end

    it "exempts meta docs 00_06/00_07 (they name the retired form as an example)" do
      retired = "StatusByte: status << 6, mask 0x3F, bits 7..6\n"
      expect(described_class.status_byte_layout_drift("00_06_SSOT_Documentation_Standard", retired)).to be_empty
      expect(described_class.status_byte_layout_drift("00_07_Action_Plan_Tracker", retired)).to be_empty
    end
  end

# [SLASH-1] Сусід rate-guard, але інший ЗВІР: той стереже СТАВКИ (конвенції, що не
# рухаються без присуду), цей — DAO-мутабельний ПОРІГ, поданий клієнтові як фіксована
# умова. Порожня множина тут МЕТА, тож живість доводить мутація, не популяція.
describe ".customer_facing_threshold_drift" do
  it "flags a bare 0.83 in the customer-facing legal home" do
    hits = described_class.customer_facing_threshold_drift(
      "00_04_Nature", "| Поріг | >20% дерев з `stress_index >= 0.83` | X |\n"
    )
    expect(hits.size).to eq(1)
    expect(hits.first).to include("без маркера DAO-мутабельності")
  end

  it "stays silent once the same line declares the value mutable" do
    hits = described_class.customer_facing_threshold_drift(
      "00_04_Nature", "| Поріг | `stress_index >= 0.83` — DAO-керований дефолт |\n"
    )
    expect(hits).to be_empty
  end

  # Ліхтар на прохід рядків БЕЗ порога: без нього гілка «рядок не матчить» жодного
  # разу не виконується, і скан лишається недоведеним на звичайному вмісті документа.
  it "walks past lines that carry no threshold at all" do
    text = "| Курс | 2000 SCC = 1 tCO₂ |\n| Поріг | `stress_index >= 0.83` — DAO-керований |\n"
    expect(described_class.customer_facing_threshold_drift("00_04_Nature", text)).to be_empty
  end

  # ⛔ Оголошена стеля: периметр — ЛИШЕ 00_04. В інженерних домах поріг цитується як
  # факт, і застереження там було б шумом; без цього прикладу гейт тихо розповз би.
  it "does not police engineering docs that cite the threshold as a fact" do
    hits = described_class.customer_facing_threshold_drift(
      "05_05_Slashing", "| Поріг | >20% дерев з `stress_index >= 0.83` | X |\n"
    )
    expect(hits).to be_empty
  end
end

  describe ".tokenomics_rate_drift" do
    it "flags the mint rate re-stated outside the home" do
      hits = described_class.tokenomics_rate_drift("05_06_Governance", "фіксований курс 10,000 growth_points = 1 SCC.\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("mint rate")
    end

    it "flags the carbon rate re-stated outside the home" do
      hits = described_class.tokenomics_rate_drift("00_01_Vision", "Кожен SCC: 2000 SCC = 1 tCO₂ еквівалент.\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("carbon rate")
    end

    it "exempts the homes, the labelled-mirror calc, the tracker and the manifesto" do
      mint = "курс 10,000 growth_points = 1 SCC\n"
      carbon = "2000 SCC = 1 tCO₂\n"
      expect(described_class.tokenomics_rate_drift("05_03_Tokenomics_SCC_and_SFC", mint)).to be_empty
      expect(described_class.tokenomics_rate_drift("00_04_Nature_as_a_Service_Contracts", mint)).to be_empty
      expect(described_class.tokenomics_rate_drift("00_04_Nature_as_a_Service_Contracts", carbon)).to be_empty
      expect(described_class.tokenomics_rate_drift("00_07_Action_Plan_Tracker", carbon)).to be_empty
      expect(described_class.tokenomics_rate_drift("manifest", mint)).to be_empty
    end

    it "does not flag a line that references the home or is a labelled mirror" do
      expect(described_class.tokenomics_rate_drift(
        "07_02_Unit_Economics", "значення — дзеркало SSOT: 2000 SCC = 1 tCO₂, правити в 05_03\n")).to be_empty
      expect(described_class.tokenomics_rate_drift(
        "05_02_Pipeline", "конвертує growth_points у SCC (курс — [`05_03`](05_03_Tokenomics_SCC_and_SFC))\n")).to be_empty
    end

    it "does not false-positive on the unrelated wei fact (1 SCC = 10^18 wei)" do
      expect(described_class.tokenomics_rate_drift(
        "04_01_Data_Models", "| `amount` | `uint256` | Кількість у wei (1 SCC = 10^18 wei) |\n")).to be_empty
    end
  end

  describe ".tokenomics_rate_anchor" do
    it "flags a rate HOME that no longer matches the guard's own regex (re-price mine, DOC-T.40)" do
      hits = described_class.tokenomics_rate_anchor(
        "00_04_Nature_as_a_Service_Contracts", "Конверсія: 12,000 growth_points = 1 SCC; 2500 SCC = 1 tCO₂\n")
      expect(hits.size).to eq(2)
      expect(hits.join).to include("TOKENOMICS_RATE_RE").and include("CARBON_RATE_RE").and include("manifest.md")
    end

    it "passes homes that still carry the pinned values; 05_03 is not required to carry carbon" do
      expect(described_class.tokenomics_rate_anchor(
        "00_04_Nature_as_a_Service_Contracts", "10,000 growth_points = 1 SCC; 2000 SCC = 1 tCO₂\n")).to be_empty
      expect(described_class.tokenomics_rate_anchor(
        "05_03_Tokenomics_SCC_and_SFC", "10,000 growth_points = 1 SCC\n")).to be_empty
    end

    it "ignores non-home docs entirely" do
      expect(described_class.tokenomics_rate_anchor("00_01_Vision", "no rates here at all\n")).to be_empty
    end
  end

  describe ".solc_pragma_version_drift" do
    it "flags a solc version re-stated outside the 05_03 owner" do
      hits = described_class.solc_pragma_version_drift("00_05_GitHub_Projects", "Slither: solc 0.8.35, fail-on high\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("solc/pragma version")
    end

    it "flags a pragma literal even inside a table cell (the 05_04 drift)" do
      row = "| `StateRootAnchor.sol` | ✅ Pragma locked `0.8.35` |\n"
      expect(described_class.solc_pragma_version_drift("05_04_Ethereum_L1_State_Anchor", row)).not_to be_empty
    end

    it "exempts the owner 05_03, the standard 00_06 and the tracker 00_07" do
      line = "pragma solidity 0.8.35 (locked)\n"
      expect(described_class.solc_pragma_version_drift("05_03_Tokenomics_SCC_and_SFC", line)).to be_empty
      expect(described_class.solc_pragma_version_drift("00_06_SSOT_Documentation_Standard", line)).to be_empty
      expect(described_class.solc_pragma_version_drift("00_07_Action_Plan_Tracker", line)).to be_empty
    end

    it "does not flag a line that references the home or is a labelled mirror" do
      expect(described_class.solc_pragma_version_drift(
        "05_02_Pipeline", "solc 0.8.35 — дзеркало, правити в [`05_03`](05_03_Tokenomics_SCC_and_SFC)\n")).to be_empty
    end

    it "does not false-positive on a bare 0.8.x without a solc/pragma keyword, nor a larger version" do
      expect(described_class.solc_pragma_version_drift(
        "02_01_Hardware", "похибка 0.8.35 мВ на каналі\n")).to be_empty
      expect(described_class.solc_pragma_version_drift(
        "06_01_Deployment", "solc toolchain at 10.8.35\n")).to be_empty
    end
  end

  describe ".ai_vendor_name_drift" do
    it "flags an AI-vendor name re-stated outside the 00_06 roster owner" do
      hits = described_class.ai_vendor_name_drift("00_03_TRL_Matrix_HIL_and_Beyond", "Handoff: Gemini (Shaping) → Cursor (Implementation)\n")
      expect(hits.size).to eq(1) # one violation per line (first vendor reported)
      expect(hits.first).to include("AI-vendor name `Gemini`")
    end

    it "flags a vendor even inside a table cell" do
      row = "| AI-pipeline | Copilot пише SDF-обгортки |\n"
      expect(described_class.ai_vendor_name_drift("01_02_Ti", row)).not_to be_empty
    end

    # [DOC-T.68 фаза 3] Owner переїхав: ростер жив у власному доку модуля 00, який
    # розчинено, і тепер стоїть у 00_06 §5.1 — разом із гейтом, що його стереже.
    # Негативна половина тут НЕСУЧА: звичайний док мусить червоніти, інакше
    # exempt-множина тихо стала б універсальною і гейт перестав би щось значити.
    it "exempts the roster owner 00_06 and the tracker 00_07, but not an ordinary doc" do
      line = "frontier-LLM: Gemini · coding-agent: Cursor / Copilot\n"
      expect(described_class.ai_vendor_name_drift("00_06_SSOT_Documentation_Standard", line)).to be_empty
      expect(described_class.ai_vendor_name_drift("00_07_Action_Plan_Tracker", line)).to be_empty
      expect(described_class.ai_vendor_name_drift("00_03_TRL_Matrix", line)).not_to be_empty
    end

    it "does not flag a labelled mirror or a line referencing the roster home" do
      expect(described_class.ai_vendor_name_drift(
        "01_02_Ti", "ростер — дзеркало, правити в 00_06 §5.1 (Cursor/Copilot)\n")).to be_empty
    end

    it "skips fenced code and does not false-positive on lowercase cursor/grok or excluded tokens" do
      expect(described_class.ai_vendor_name_drift("03_01_Firmware", "```\nGemini api call\n```\n")).to be_empty
      expect(described_class.ai_vendor_name_drift("04_02_Business", "move the cursor; agents grok the spec\n")).to be_empty
      expect(described_class.ai_vendor_name_drift("00_00_SSOT_Index", "The Codex SSOT-guard; Claude/Opus/Sonnet/Fable\n")).to be_empty
    end
  end

  describe ".anchor_dimension_drift" do
    it "flags a superseded flange/radome Ø range next to the part keyword" do
      hits = described_class.anchor_dimension_drift("07_02", "радом-купол ∅20–30 мм, термолиття\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("Ø = 25 mm")
    end

    it "flags a superseded Zone 2 length range" do
      expect(described_class.anchor_dimension_drift(
        "02_01", "Zone 2 (PEEK-терморозрив 40–60 мм)\n").size).to eq(1)
    end

    it "flags inside the 01_01 owner too (owner states the new value, never the old range)" do
      expect(described_class.anchor_dimension_drift("01_01", "фланець ∅20-30 мм\n")).not_to be_empty
    end

    it "passes the frozen single values" do
      expect(described_class.anchor_dimension_drift("07_02", "радом-купол ∅25 мм\n")).to be_empty
      expect(described_class.anchor_dimension_drift("02_01", "Zone 2 (PEEK-терморозрив 50 мм)\n")).to be_empty
    end

    it "ignores a range with no part keyword (a bare number elsewhere)" do
      expect(described_class.anchor_dimension_drift("02_05", "робоча температура 20–30 °C\n")).to be_empty
      expect(described_class.anchor_dimension_drift("07_02", "діапазон 40–60 Гц\n")).to be_empty
    end

    it "exempts a line marking the value historical" do
      expect(described_class.anchor_dimension_drift(
        "01_01", "фланець був ∅20–30 мм (superseded → 25)\n")).to be_empty
    end

    it "skips fenced code" do
      expect(described_class.anchor_dimension_drift("02_01", "```\nрадом ∅20–30 мм\n```\n")).to be_empty
    end
  end

  describe ".thermal_stress_drift" do
    it "flags a superseded SF 9.9× near a thermal keyword" do
      hits = described_class.thermal_stress_drift("01_01", "Lamé worst-case SF 9.9× vs PEEK yield\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("SF = 5.6×")
    end

    it "flags a superseded press-fit P_c value" do
      expect(described_class.thermal_stress_drift(
        "01_01", "контактний тиск P_c релаксує 34.7→22.6 MPa\n").size).to be >= 1
    end

    it "flags the superseded SF 3.4× generation (2nd gen, pre unified-Lamé re-run)" do
      expect(described_class.thermal_stress_drift(
        "01_01", "Lamé combined SF 3.4× vs PEEK yield\n").size).to eq(1)
    end

    it "exempts a Correction-C line citing the old 3.4× artefact" do
      expect(described_class.thermal_stress_drift(
        "01_01", "Колишній «SF 3.4×» — артефакт завищеного (k²−1)-знаменника, виправлено\n")).to be_empty
    end

    it "exempts the English historical markers the report's chronology uses (DOC-T.42 ②)" do
      expect(described_class.thermal_stress_drift(
        "PIPELINE_STATUS", "thermal σ_t SF 14.6× (was SF 3.4× — overstated (k²−1) denominator, fixed)\n")).to be_empty
      expect(described_class.thermal_stress_drift(
        "SUMMARY", "the former \"SF 3.4×\" headline was an artifact of a legacy denominator\n")).to be_empty
    end

    it "exempts the report itself as co-owner (frozen pre-Correction §1 quotes carry no marker)" do
      expect(described_class.thermal_stress_drift(
        "THERMAL_STRESS_REPORT", "> σ_t @ -30°C: 10.1 → 29.7 MPa, SF 9.9× → 3.4×.\n")).to be_empty
    end

    it "passes the current frozen values (5.6× combined)" do
      expect(described_class.thermal_stress_drift(
        "01_01", "SF 5.6× (frozen Ø11/2мм); P_c 0.32-2.16 MPa press-fit\n")).to be_empty
    end

    it "ignores a bare number with no thermal context" do
      expect(described_class.thermal_stress_drift("06_01", "version 9.9 released; backup 34.7 GB\n")).to be_empty
    end

    it "exempts a line marking the value historical (Correction B)" do
      expect(described_class.thermal_stress_drift(
        "fea", "the old buggy press-fit P_c 34.7→22.6 MPa (baseline) → 0.32-2.16\n")).to be_empty
    end

    it "skips fenced code" do
      expect(described_class.thermal_stress_drift("01_01", "```\nSF 9.9× press-fit\n```\n")).to be_empty
    end
  end

  # [SSOT anti-drift] Канон не сміє лінкувати `memory/` — вона поза репозиторієм.
  # Клас куплений повтором: чотири входження у двох комітах за чотири дні, усі в
  # `00_07`, тобто саме там, де `DEPRECATED_EXEMPT` звільняє від сусідньої
  # перевірки — тому окрема функція БЕЗ винятків, а не ще один термін у мапі.
  describe ".memory_wikilink_violations" do
    it "ловить memory-лінк і називає лік" do
      hits = described_class.memory_wikilink_violations("клас описано в [[feedback_silent_default]] докладно")

      expect(hits.size).to eq(1)
      expect(hits.first).to include("[[feedback_silent_default]]", "поза репозиторієм")
    end

    it "не має винятку для 00_06/00_07 — саме там клас і виникав" do
      # Сигнатура навмисно без `basename`: виняток тут був би дірою у формі дефекту.
      expect(described_class.method(:memory_wikilink_violations).arity).to eq(1)
    end

    it "дедуплікує повтор того самого лінка" do
      expect(described_class.memory_wikilink_violations("[[a_b]] і ще раз [[a_b]]").size).to eq(1)
    end

    # ⚠️ Док, що ілюструє цей самий антипатерн літеральним прикладом, — природна
    # річ; без пропуску фенсів гейт червонів би на інертному прикладі, а не на
    # живому посиланні (`guard-craft` #29 — цитата стає твердженням).
    it "пропускає fenced-блок, але не сусідній живий лінк" do
      doc = "жива згадка [[live_one]]\n\n```md\nприклад: [[in_fence]]\n```\n\nхвіст\n"

      hits = described_class.memory_wikilink_violations(doc)

      expect(hits.size).to eq(1)
      expect(hits.first).to include("[[live_one]]")
      # Ліхтар: без нього приклад був би зелений і на гейті, що не бачить нічого.
      expect(hits.first).not_to include("in_fence")
    end

    # ⊥ Межі: markdown-лінк, посилання на канон і подвійна дужка в коді — не хіти.
    it "не чіпає звичайних посилань і сусідніх форм" do
      %w[
        [текст](04_04_Phlex_UI_and_Tailwind)
        `04_04\ §8.1а`
      ].each { |sample| expect(described_class.memory_wikilink_violations(sample)).to be_empty }

      expect(described_class.memory_wikilink_violations("масив[[0]] і [[Klass]]")).to be_empty
    end
  end

  describe ".deprecated_terms" do
    it "flags a retired token and gives the replacement hint" do
      hits = described_class.deprecated_terms("03_05", "derive via HKDF info silkennet-v1-aes256 here")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("silken-aes-128-lora-key")
    end

    it "flags a retired part number (ZP-3/ZP-5) in active canon" do
      expect(described_class.deprecated_terms("02_01", "use ZP-3 disc")).not_to be_empty
      expect(described_class.deprecated_terms("07_02", "ZP-5 piezo")).not_to be_empty
    end

    it "flags the retired «Gaia 2.0» project codename (BIZ.16) in active canon" do
      expect(described_class.deprecated_terms("05_01", "архітектура Gaia 2.0 pipeline")).not_to be_empty
      expect(described_class.deprecated_terms("00_00", "# Gaia 2.0 SSOT")).not_to be_empty
    end

    it "does NOT flag «Gen 2.0» (separate, live EBFC biochem generation axis)" do
      expect(described_class.deprecated_terms("07_02", "EBFC Gen 2.0 baseline dgrFAD-GDH")).to be_empty
      expect(described_class.deprecated_terms("01_03", "Gen 2.0 anode/cathode chemistry")).to be_empty
    end

    it "exempts the meta docs (they may name retired things)" do
      expect(described_class.deprecated_terms("00_06", "example token ZP-3")).to be_empty
      expect(described_class.deprecated_terms("00_07", "migrate-from ZP-3 baseline")).to be_empty
    end

    it "does NOT flag a token that is still alive (LTC3108 survives as a DNP fallback)" do
      expect(described_class.deprecated_terms("02_03", "LTC3108 DNP cold-start fallback")).to be_empty
    end

    it "flags the FPU myth tokens (WLE5 has no FPU — ARM builds are soft-float)" do
      expect(described_class.deprecated_terms("03_03", "Ядро ARM Cortex-M4 з FPU")).not_to be_empty
      expect(described_class.deprecated_terms("03_01", "toolchain Cortex-M4F pinned")).not_to be_empty
      expect(described_class.deprecated_terms("03_01", "flags -mfpu=fpv4-sp-d16 -mfloat-abi=hard")).not_to be_empty
    end

    it "does NOT flag the corrected no-FPU wording" do
      expect(described_class.deprecated_terms("03_03", "ARM Cortex-M4 без FPU, -mfloat-abi=soft")).to be_empty
    end

    it "is clean when only current tokens are present" do
      expect(described_class.deprecated_terms("03_05", "HKDF info silken-aes-128-lora-key")).to be_empty
    end

    it "exposes a non-empty registry of retired tokens" do
      expect(described_class::DEPRECATED_TERMS).not_to be_empty
    end
  end

  describe ".superseded_term_in_frontmatter" do
    let(:doc) do
      ->(se) { "# 03_05: Crypto\n## 🎯 Мета\nKey mgmt via #{se} Secure Element for LoRa.\n## ✅ Статус\nTRL 6\n## 🔗 Cross-references\nbody...\n" }
    end

    it "flags a superseded term inside the 🎯/Статус front-matter" do
      hits = described_class.superseded_term_in_frontmatter("03_05", doc.call("ATECC608B"))
      expect(hits).not_to be_empty
      expect(hits.first).to include("SE050")
    end

    it "ignores the term in the BODY (legacy pattern is allowed there)" do
      text = "## 🎯 Мета\nSE = SE050.\n## 🔗 Cross-references\n## 3.2 Legacy\nATECC608B provisioning pattern lives here."
      expect(described_class.superseded_term_in_frontmatter("03_05", text)).to be_empty
    end

    it "exempts the standard (00_06) and the tracker (00_07)" do
      expect(described_class.superseded_term_in_frontmatter("00_07", doc.call("ATECC608B"))).to be_empty
      expect(described_class.superseded_term_in_frontmatter("00_06", doc.call("ATECC608B"))).to be_empty
    end

    it "is clean when the front-matter names the current SE" do
      expect(described_class.superseded_term_in_frontmatter("03_05", doc.call("SE050"))).to be_empty
    end

    it "returns empty when the doc has no 🎯...🔗 front-matter block at all (index/appendix-shaped docs)" do
      expect(described_class.superseded_term_in_frontmatter(
        "00_00_SSOT_Index", "just prose mentioning ATECC608B, no ## headings here\n")).to be_empty
    end
  end

  describe ".link_label_target_mismatch" do
    it "flags a label leading with a different doc-ID than the href resolves to" do
      hits = described_class.link_label_target_mismatch("див. [`00_06 §2/§4`](00_05_GitHub_Automation_and_IaC)")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("00_06").and include("00_05")
    end

    it "passes when the label leads with the same doc it links to (ref form + full-name form)" do
      expect(described_class.link_label_target_mismatch("[`05_05 §7-8`](05_05_Slashing_and_Risk_Policy)")).to be_empty
      expect(described_class.link_label_target_mismatch("[05_05_Slashing_and_Risk_Policy](05_05_Slashing_and_Risk_Policy)")).to be_empty
    end

    it "ignores a label with no doc-ID token (plain prose link text)" do
      expect(described_class.link_label_target_mismatch("[Insurance Layer mechanics](00_04_Nature_as_a_Service_Contracts)")).to be_empty
    end

    # 🔴 The RELATIVE href is the dialect a file one directory down can only write —
    # and it is exactly the tree this guard's corpus was widened to (.github/**,
    # root *.md). Live proof at the time of the fix: pull_request_template.md
    # labelled `00_06 §3` over an href to 06_07. Green since the widening.
    it "flags the mismatch through a ../-relative href (the .github/ dialect)" do
      hits = described_class.link_label_target_mismatch(
        "(see [`00_06 §3`](../docs/06_07_CICD_and_Runbook_Index.md))")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("00_06").and include("06_07")
    end

    it "flags it through a deeper ../../ href too" do
      expect(described_class.link_label_target_mismatch(
        "[`00_06 §3`](../../06_07_CICD_and_Runbook_Index.md)").size).to eq(1)
    end

    # The label is recovered by bracket-BALANCE, and both directions matter: a real
    # label carrying nested brackets must be SEEN, and a bold prose marker wrapping
    # a link must not have its outer text mistaken for the label.
    it "sees a legitimate label that carries nested brackets" do
      expect(described_class.link_label_target_mismatch(
        "[`05_02 §Усі Шляхи [DOC.7]`](05_02_Proof_of_Growth_Pipeline)")).to be_empty
      expect(described_class.link_label_target_mismatch(
        "[`05_02 §Усі Шляхи [DOC.7]`](00_04_Nature_as_a_Service_Contracts)").size).to eq(1)
    end

    it "does not accuse a link wrapped in a bold prose marker (the [^\\]]* false positive)" do
      expect(described_class.link_label_target_mismatch(
        "**[`00_07`-прямий + [`00_02 §4.3`](../../00_02_Academic_Integration_and_IP.md)]** UNI.15")).to be_empty
    end

    # An unbalanced bracket must make the link INVISIBLE, never mis-attributed —
    # the safe direction for a guard that accuses. Two ways the walk-back can fail,
    # and both must end in silence rather than in a label borrowed from above.
    it "stays silent when the walk-back crosses a newline (a label never spans lines)" do
      expect(described_class.link_label_target_mismatch(
        "[`00_06 §3` без закриття\n](06_07_CICD_and_Runbook_Index)")).to be_empty
    end

    it "stays silent when there is no opening bracket at all" do
      expect(described_class.link_label_target_mismatch(
        "](06_07_CICD_and_Runbook_Index) — осиротілий хвіст лінка")).to be_empty
    end

    # The PATH href form is how root files and .github/ link canon, and it is where a
    # re-point campaign leaves the lie unread — the in-docs loop never opens them
    # [DOC-T.68 закривна: GOVERNANCE.md carried `docs/00_02` → docs/00_03_… unseen].
    it "flags the same mismatch written in the docs/…​.md PATH form" do
      hits = described_class.link_label_target_mismatch("[`docs/00_02`](docs/00_03_TRL_Matrix_HIL_and_Beyond.md)")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("00_02").and include("00_03")
    end

    it "passes the PATH form when label and href agree" do
      expect(described_class.link_label_target_mismatch("[`docs/00_07`](docs/00_07_Action_Plan_Tracker.md)")).to be_empty
    end

    it "keys on the LEAD doc-ID only — a later secondary mention is not flagged" do
      expect(described_class.link_label_target_mismatch("[`03_04 §4.1` (див. також 05_05)](03_04_mruby_Lorenz_Attractor)")).to be_empty
    end

    it "does not match a long number that merely contains an NN_NN substring" do
      expect(described_class.link_label_target_mismatch("[реліз 2026_05 deep-dive](00_01_Vision_Mission_and_Roadmap)")).to be_empty
    end
  end

  describe ".section_label_drift" do
    let(:headings) do
      { "08_02_Academic_Institutions_Registry" => "## 1. чну\n### 1a. наукові школи\n### 1b. фотіус\n## 2. чдту" }
    end

    it "flags a §-label whose section is absent from the target headings" do
      md = "координація — [`08_02 §1.3`](08_02_Academic_Institutions_Registry)"
      expect(described_class.section_label_drift(md, headings))
        .to contain_exactly(a_string_matching(/§1\.3.*no heading contains '1\.3'/))
    end

    it "passes a numbered §-label that matches a heading (§1A → '1a')" do
      expect(described_class.section_label_drift(
        "[`08_02 §1A`](08_02_Academic_Institutions_Registry)", headings)).to be_empty
    end

    it "skips a bare single-char ref and a label citing no section" do
      expect(described_class.section_label_drift(
        "[`08_02 §2`](08_02_Academic_Institutions_Registry)", headings)).to be_empty
      expect(described_class.section_label_drift(
        "[Реєстр ВНЗ](08_02_Academic_Institutions_Registry)", headings)).to be_empty
    end

    it "stays STRICT: a descriptive §-word label is flagged (normalize the ref, not the guard)" do
      h = { "04_02_Business_Logic_and_Services" => "## 5. верифікація та ідентичність" }
      expect(described_class.section_label_drift(
        "[`04_02 §Web3CircuitBreaker`](04_02_Business_Logic_and_Services)", h))
        .to contain_exactly(a_string_matching(/Web3CircuitBreaker/))
    end

    it "leaves an absent target doc to the dangling guard (not flagged here)" do
      expect(described_class.section_label_drift(
        "[`99_99 §1.3`](99_99_Missing_Doc)", headings)).to be_empty
    end
  end

  describe ".bare_section_ref" do
    it "flags a bare code-span `NN_NN §X` ref that is not wrapped in a link" do
      hits = described_class.bare_section_ref(
        "02_01_Hardware", "Баланс позитивний у Сценарії C (`02_03 §9.6`).\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("02_03 §9.6")
    end

    it "passes a properly-linked ref (label preceded by '[')" do
      expect(described_class.bare_section_ref(
        "02_01_Hardware", "див. [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power)\n")).to be_empty
    end

    it "skips meta-syntactic placeholders (§NN / §X.Y / §x), flags real alphanumeric refs (§1A)" do
      ph = "форма `03_04 §X.Y`; `00_07 §NN` placeholder; приклад `02_01 §x`\n"
      expect(described_class.bare_section_ref("00_03_TRL", ph)).to be_empty
      hits = described_class.bare_section_ref("00_02_Acad", "ЧНУ Hard-Science — `00_02 §1A`\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("00_02 §1A")
    end

    it "skips fenced code but does NOT skip table rows (cells carry real refs)" do
      expect(described_class.bare_section_ref(
        "02_01_Hardware", "```\nсм `02_03 §9.6`\n```\n")).to be_empty
      expect(described_class.bare_section_ref(
        "02_01_Hardware", "| 9 | Buffer | НЕ 6.3V (`02_03 §6.1` derating) | $0.18 |\n").size).to eq(1)
    end

    it "flags every bare ref on a line (multiple per line)" do
      expect(described_class.bare_section_ref(
        "05_05_Slashing", "інваріант `02_01 §3.4` + сестра `02_03 §12.4.2`\n").size).to eq(2)
    end

    it "exempts the index, the standard-owner, the tracker, and appendix docs" do
      expect(described_class.bare_section_ref("00_00_SSOT_Index", "`05_05 §3`\n")).to be_empty
      expect(described_class.bare_section_ref("00_06_SSOT_Documentation_Standard", "| AES | `03_05 §3.7` |\n")).to be_empty
      expect(described_class.bare_section_ref("00_07_Action_Plan_Tracker", "- **P0** · → `05_05 §3`\n")).to be_empty
      expect(described_class.bare_section_ref("07_09_Some_Field_Appendix", "`02_03 §9`\n")).to be_empty
    end
  end

  describe ".bare_doc_ref" do
    let(:ids) { %w[02_03 05_05 06_07 07_02].to_set }

    it "flags a bare code-span doc-id not wrapped in a link" do
      hits = described_class.bare_doc_ref("02_01_Hardware", "деталі — `06_07`.\n", ids)
      expect(hits.size).to eq(1)
      expect(hits.first).to include("06_07")
    end

    it "flags docs/-prefixed and full-filename code-spans" do
      expect(described_class.bare_doc_ref("02_01_Hardware", "(`docs/06_07`)\n", ids).size).to eq(1)
      expect(described_class.bare_doc_ref("02_01_Hardware", "(`07_02_Unit_Economics_and_BOM`)\n", ids).size).to eq(1)
    end

    it "passes a linked ref and a §-ref (bare_section_ref's domain, has no match here)" do
      expect(described_class.bare_doc_ref(
        "02_01_Hardware", "див. [`06_07`](06_07_CICD_and_Runbook_Index)\n", ids)).to be_empty
      expect(described_class.bare_doc_ref("02_01_Hardware", "див. `02_03 §9.6`\n", ids)).to be_empty
    end

    it "does NOT flag a retired/unknown doc-id (not in valid_ids → stays prose)" do
      expect(described_class.bare_doc_ref(
        "08_03_Stakeholders", "колишнього `04_07` при реструктуризації\n", ids)).to be_empty
    end

    it "skips fenced code" do
      expect(described_class.bare_doc_ref("02_01_Hardware", "```\nсм `06_07`\n```\n", ids)).to be_empty
    end

    it "exempts index / standard-owner / tracker / appendix / manifesto" do
      %w[00_00_SSOT_Index 00_06_SSOT_Documentation_Standard 00_07_Action_Plan_Tracker
         07_09_Some_Field_Appendix manifest].each do |b|
        expect(described_class.bare_doc_ref(b, "`06_07`\n", ids)).to be_empty
      end
    end
  end

  describe ".magic_marker_hex_drift" do
    it "passes little-endian (RITE=0x45544952) and big-endian (LZST=0x4C5A5354) markers" do
      md = %(magic "RITE" = 0x45544952\nRTC magic `LZST` = 0x4C5A5354 (FW.6)\n)
      expect(described_class.magic_marker_hex_drift(md)).to be_empty
    end

    it "flags a typo'd marker hex (neither BE nor LE of the named marker)" do
      hits = described_class.magic_marker_hex_drift(%(RTC magic "LZST" = 0x4C5A5355 (stale)\n))
      expect(hits.size).to eq(1)
      expect(hits.first).to include("LZST")
    end

    it "ignores Flash addresses (0x0803… is out of the ASCII range) next to a valid def" do
      expect(described_class.magic_marker_hex_drift(
        %(magic `KEYL` = 0x4B45594C (sector 0x0803E000)\n))).to be_empty
    end

    it "does NOT flag a value-referenced hex with no adjacent name, beside another def" do
      # the real 03_01 line: DR19 compared to the LZST value, while LSED is *defined*
      md = %(cold-start if DR19 ≠ `0x4C5A5354`; seed magic `"LSED"` = `0x4C534544`\n)
      expect(described_class.magic_marker_hex_drift(md)).to be_empty
    end

    it "passes a multi-marker definition line (each name validates its own hex)" do
      expect(described_class.magic_marker_hex_drift(
        %(magic "KEYL" = 0x4B45594C, "KEYC" = 0x4B455943\n))).to be_empty
    end

    it "skips magic lines lacking a quoted 4-letter marker or a magic-range hex" do
      expect(described_class.magic_marker_hex_drift("magic marker check at boot\n")).to be_empty
      expect(described_class.magic_marker_hex_drift(%(the "LZST" state is restored at boot\n))).to be_empty
      expect(described_class.magic_marker_hex_drift("magic float value 0x4188EE90 here\n")).to be_empty
    end
  end

  # [cross-ref single-form, 2026-06-01] One sanctioned dialect: every doc-id link
  # label must lead with a code-span `NN_NN` (+ optional §X, + optional — Title).
  describe ".crossref_label_form" do
    it "accepts the three canonical code-span forms" do
      ok = <<~MD
        whole-doc [`05_05`](05_05_Slashing_and_Risk_Policy)
        section   [`05_05 §3`](05_05_Slashing_and_Risk_Policy)
        directory [`05_05` — Slashing and Risk Policy](05_05_Slashing_and_Risk_Policy)
      MD
      expect(described_class.crossref_label_form(ok)).to be_empty
    end

    it "flags plain, escaped and full-name-in-codespan dialects" do
      bad = <<~MD
        plain     [05_05 §3](05_05_Slashing_and_Risk_Policy)
        escaped   [05\\_05\\_Slashing\\_and\\_Risk\\_Policy](05_05_Slashing_and_Risk_Policy)
        fullname  [`05_05_Slashing_and_Risk_Policy`](05_05_Slashing_and_Risk_Policy)
      MD
      expect(described_class.crossref_label_form(bad).size).to eq(3)
    end

    it "leaves a pure prose-phrase label (no doc-id) alone" do
      expect(described_class.crossref_label_form(
        "повна політика [живе тут](05_05_Slashing_and_Risk_Policy)\n")).to be_empty
    end

    it "skips fenced code blocks" do
      expect(described_class.crossref_label_form(
        "```\n[05_05 §3](05_05_Slashing_and_Risk_Policy)\n```\n")).to be_empty
    end
  end

  describe ".section_ref_after_doclink" do
    it "flags a bare §X dangling after a whole-doc link" do
      hits = described_class.section_ref_after_doclink(
        "01_01_Coaxial", "див. [`01_04`](01_04_CODIT_and_Xylemointegration) §4 деталі\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("01_04_CODIT_and_Xylemointegration")
    end

    it "flags the directory-form label too (`[`NN_NN` — Title](Doc) §X`)" do
      expect(described_class.section_ref_after_doclink(
        "00_04_NaaS",
        "Детально: [`08_02` — Academic Institutions Registry](08_02_Academic_Institutions_Registry) §5.\n").size).to eq(1)
    end

    it "flags a relative-path href (docs/protocols/ refs canon by ../)" do
      expect(described_class.section_ref_after_doclink(
        "SUMMARY", "база [`01_03`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell) §3.2\n").size).to eq(1)
    end

    # 🔴 The case above passed for two months while the guard reached ZERO of the
    # tree it was widened for — because its fixture writes a dialect the corpus
    # never uses. Every real `docs/protocols/**` href carries the `.md` extension,
    # and without `(?:\.md)?` the group never closed: 16 live violations sat green.
    # A fixture is a claim about the corpus's OUTPUT vocabulary; write it in the
    # dialect the tree actually writes, or the branch is proved against nothing.
    it "flags the relative href AS THE SUBTREE ACTUALLY WRITES IT (with .md)" do
      expect(described_class.section_ref_after_doclink(
        "rfq_registry",
        "дім [`01_04`](../../01_04_CODIT_and_Xylemointegration.md) §3.1\n").size).to eq(1)
    end

    it "still passes the folded form in that same .md dialect" do
      expect(described_class.section_ref_after_doclink(
        "rfq_registry",
        "дім [`01_04 §3.1`](../../01_04_CODIT_and_Xylemointegration.md)\n")).to be_empty
    end

    it "passes the canonical folded form (§ inside the label)" do
      expect(described_class.section_ref_after_doclink(
        "01_01_Coaxial", "див. [`01_04 §4`](01_04_CODIT_and_Xylemointegration)\n")).to be_empty
    end

    it "ignores filename-label links (not an NN_NN canon ref — protocols/ convention)" do
      expect(described_class.section_ref_after_doclink(
        "01_03_EBFC", "катод [`SUMMARY.md`](protocols/ebfc/in_silico/SUMMARY.md) §Cathode\n")).to be_empty
    end

    it "skips meta placeholders (`§X`) and fenced code" do
      expect(described_class.section_ref_after_doclink(
        "00_03_TRL", "форма [`03_04`](03_04_mruby_Lorenz_Attractor) §X\n")).to be_empty
      expect(described_class.section_ref_after_doclink(
        "01_01_Coaxial", "```\n[`01_04`](01_04_CODIT_and_Xylemointegration) §4\n```\n")).to be_empty
    end

    it "exempts the index, standard-owner, tracker, and appendix docs" do
      txt = "[`01_04`](01_04_CODIT_and_Xylemointegration) §4\n"
      %w[00_00_SSOT_Index 00_06_SSOT_Documentation_Standard
         00_07_Action_Plan_Tracker 07_09_Some_Field_Appendix].each do |b|
        expect(described_class.section_ref_after_doclink(b, txt)).to be_empty
      end
    end
  end

  describe ".external_doc_path_drift" do
    let(:existing) { %w[00_05_GitHub_Automation_and_IaC 08_03_External_Stakeholders_Registry] }

    it "flags a docs/NN_NN path whose basename is not a current doc" do
      txt = "# Ref: docs/00_07_GitHub_Projects_and_IaC_Automation.md §2.6\n"
      expect(described_class.external_doc_path_drift(".github/labeler.yml", txt, existing))
        .to contain_exactly(a_string_matching(%r{stale doc path `docs/00_07_GitHub_Projects_and_IaC_Automation`}))
    end

    it "passes a path that resolves to a current doc (with or without .md)" do
      txt = "see docs/00_05_GitHub_Automation_and_IaC.md and docs/08_03_External_Stakeholders_Registry\n"
      expect(described_class.external_doc_path_drift("README.md", txt, existing)).to be_empty
    end

    it "skips non-NN_NN subpaths (docs/protocols/…) and bare module refs (docs/00_07)" do
      txt = "docs/protocols/ebfc/in_silico/SUMMARY.md plus a bare docs/00_07 mention\n"
      expect(described_class.external_doc_path_drift("x.md", txt, existing)).to be_empty
    end
  end

  describe ".external_doc_anchor_drift" do
    # [OPS.32] Три піни, і кожен закриває свою половину: RED на мертвому слагу,
    # GREEN на живому, і near-miss — мертвий сам ДОКУМЕНТ, який судить сусідня
    # вісь (`external_doc_path_drift`). Без третього гейт видавав би два вироки
    # на один дефект, і другий називав би не ту причину.
    let(:anchors) do
      { "00_04" => Set.new(%w[-7-параметричне-страхування-insurance-layer]),
        "04_02" => Set.new(%w[blockchainmintingservice]) }
    end

    it "flags a fragment that matches no heading slug in the target" do
      txt = %(          runbook_url: "docs/00_04_Nature_as_a_Service_Contracts.md#reserve-gate"\n)
      expect(described_class.external_doc_anchor_drift("deploy/grafana/alerts/x.yaml", txt, anchors))
        .to contain_exactly(a_string_matching(/dead anchor `00_04 #reserve-gate`/))
    end

    it "flags a fragment whose case differs — a GitHub heading slug is always lowercase" do
      txt = %(runbook_url: "docs/04_02_Business_Logic_and_Services.md#BlockchainMintingService"\n)
      expect(described_class.external_doc_anchor_drift("deploy/x.yaml", txt, anchors))
        .to contain_exactly(a_string_matching(/dead anchor `04_02 #BlockchainMintingService`/))
    end

    it "passes a fragment that resolves to a real heading slug" do
      txt = %(runbook_url: "docs/04_02_Business_Logic_and_Services.md#blockchainmintingservice"\n)
      expect(described_class.external_doc_anchor_drift("deploy/x.yaml", txt, anchors)).to be_empty
    end

    it "stays silent when the DOC itself is unknown — that axis belongs to external_doc_path_drift" do
      txt = %(runbook_url: "docs/09_99_Renamed_Away.md#whatever"\n)
      expect(described_class.external_doc_anchor_drift("deploy/x.yaml", txt, anchors)).to be_empty
    end

    it "ignores a path with no #fragment at all (16 of our 20 runbook_urls are this form)" do
      txt = %(runbook_url: "docs/00_04_Nature_as_a_Service_Contracts.md"\n)
      expect(described_class.external_doc_anchor_drift("deploy/x.yaml", txt, anchors)).to be_empty
    end
  end

  describe ".cited_spec_path_drift" do
    # Обидві половини навмисно: пін лише з RED вважав би дефектом кожну цитату,
    # а пін лише з GREEN не червонів би НІКОЛИ — і саме друге DOC-T.84 виміряв
    # як реальний стан справ до цього гейта.
    let(:exists) { ->(p) { p == "spec/quality/live_spec.rb" } }

    it "flags a cited spec path that no file answers to" do
      txt = "гейт `spec/quality/renamed_away_spec.rb` стереже цю вісь\n"
      expect(described_class.cited_spec_path_drift("04_02_Business_Logic", txt, exists))
        .to contain_exactly(a_string_matching(%r{cited spec `spec/quality/renamed_away_spec\.rb` does not exist}))
    end

    it "passes a cited spec that exists" do
      txt = "носій — `spec/quality/live_spec.rb`, і він біжить у смузі\n"
      expect(described_class.cited_spec_path_drift("00_06_Standard", txt, exists)).to be_empty
    end

    it "ignores spec paths outside a code-span (prose glob, wildcard roster)" do
      txt = "усі spec/quality/*.rb та `spec/quality/**/*.rb` — це периметр, не цитата\n"
      expect(described_class.cited_spec_path_drift("00_06_Standard", txt, exists)).to be_empty
    end
  end

  describe ".source_line_ref_drift" do
    it "flags bare, path-qualified and ranged *.c/*.h line-refs" do
      txt = "| `K` | `1` | main.c:39 | x |\n// firmware/queen/main.c:87-97\nsee silken_sha256.h:12\n"
      hits = described_class.source_line_ref_drift("03_02", txt)
      expect(hits.size).to eq(3)
      expect(hits).to include(a_string_matching(/`main\.c:39`/),
                              a_string_matching(%r{`firmware/queen/main\.c:87-97`}),
                              a_string_matching(/`silken_sha256\.h:12`/))
    end

    it "matches a wildcard path ref and carries the file prefix" do
      hits = described_class.source_line_ref_drift(".github/copilot-instructions.md", "HW-AES-KEY firmware/*/main.c:65-66\n")
      expect(hits).to contain_exactly(a_string_matching(%r{\.github/copilot-instructions\.md: .*`firmware/\*/main\.c:65-66`}))
    end

    it "flags Ruby `*.rb`/`*.rake` line-refs (path-qualified and ranged) [DOC-T.17]" do
      txt = "see `app/services/blockchain_minting_service.rb:107`\n" \
            "`config/initializers/master_key_strength_check.rb:33-37` crashes\n" \
            "lib/tasks/docs.rake:42 builds\n"
      hits = described_class.source_line_ref_drift("06_02", txt)
      expect(hits.size).to eq(3)
      expect(hits).to include(a_string_matching(%r{`app/services/blockchain_minting_service\.rb:107`}),
                              a_string_matching(%r{`config/initializers/master_key_strength_check\.rb:33-37`}),
                              a_string_matching(%r{`lib/tasks/docs\.rake:42`}))
    end

    it "does NOT flag a de-line-reffed symbol ref, a .md line-ref, a decimal, or a bare .rb path" do
      txt = "main.c (struct EdgeCache)\nsee 03_02_Queen.md:114 row\nratio 1.5:30 here\n" \
            "`htim2` метроном (коментар)\n`app/models/ai_insight.rb` (the enum)\n"
      expect(described_class.source_line_ref_drift("03_02", txt)).to be_empty
    end

    # 4th dialect (stan_audit dig 2026-07-12): `NN_NN:line` — a line-ref INTO a canon
    # doc (the live `03_02:9` in the tracker). §-anchors are the stable form; the
    # tracker is NOT exempt (that's where the ref lived), a `§`-ref / prose colon stay clean.
    it "flags a doc-id `NN_NN:line` ref (incl. in 00_07), passes §-refs and a colon+space" do
      expect(described_class.source_line_ref_drift("00_07", "packet-loss (`03_02:9`)\n"))
        .to contain_exactly(a_string_matching(/`03_02:9`/))
      expect(described_class.source_line_ref_drift("03_05", "див. `03_02 §9`; у 02_04: 12 голок\n"))
        .to be_empty
    end

    it "flags `ClassName:NNN` Ruby-symbol line-refs but not wire-field notation [DOC-T.29]" do
      txt = "`BlockchainMintingService:107` (MINTER_ROLE)\n" \
            "`Ethereum::StateAnchorService:147` weekly anchor\n" \
            "the packet `[Payload:16]` is one AES block\n"
      hits = described_class.source_line_ref_drift("06_02", txt)
      expect(hits.size).to eq(2)
      expect(hits).to include(a_string_matching(/`BlockchainMintingService:107`/),
                              a_string_matching(/`Ethereum::StateAnchorService:147`/))
      expect(hits).not_to include(a_string_matching(/Payload:16/))
    end

    it "flags `(р.N)`/`(рядок N)` Ukrainian-prose line-refs [DOC-T.29]" do
      txt = "`application.rb` (рядок 31) registers it\n`web3.rb` (р.76,80,84,88) counters\n"
      hits = described_class.source_line_ref_drift("06_03", txt)
      expect(hits.size).to eq(2)
      expect(hits).to include(a_string_matching(/\(рядок 31\)/), a_string_matching(/\(р\.76,80,84,88\)/))
    end

    # Narrowed 2026-08-22: the illustration exemption is SECTION-scoped, not
    # file-scoped. It used to bless two whole files — the standard and the
    # tracker — and that blanket hid a LIVE volatile ref on the hot path.
    it "exempts a ClassName:NNN ref only INSIDE the illustration section of 00_06/00_07" do
      inside_std = "## 🛡️ 3. Drift-prevention tooling\nexample of the bad form: `BlockchainMintingService:107`\n"
      inside_trk = "## 🗄️ Архів закритих пунктів\n| X | was `BlockchainMintingService:107` |\n"
      expect(described_class.source_line_ref_drift("00_06_SSOT_Documentation_Standard", inside_std)).to be_empty
      expect(described_class.source_line_ref_drift("00_07_Action_Plan_Tracker", inside_trk)).to be_empty
    end

    it "FLAGS the same ref in a live section of those files — the blanket used to hide it" do
      live_std = "## 🏠 2. Canonical-home registry\nчитач стоїть на `BlockchainMintingService:107`\n"
      live_trk = "## §04 · Backend\n- **Стан:** гейт у `TelemetryUnpackerService:946`\n"
      expect(described_class.source_line_ref_drift("00_06_SSOT_Documentation_Standard", live_std))
        .to include(a_string_matching(/BlockchainMintingService:107/))
      expect(described_class.source_line_ref_drift("00_07_Action_Plan_Tracker", live_trk))
        .to include(a_string_matching(/TelemetryUnpackerService:946/))
    end
  end

  describe ".canonical_block_sha / .canonical_block_drift" do
    let(:src) do
      "  BASE_RHO   = 28.0\n  BASE_SIGMA = 10.0\n  BASE_BETA  = 8.0 / 3.0  # bit-identical to backend\n"
    end
    let(:names) { %w[BASE_RHO BASE_SIGMA BASE_BETA] }

    it "extracts the consts, stable to inner whitespace + trailing comments" do
      sha, missing = described_class.canonical_block_sha(src, names)
      expect(missing).to be_empty
      cosmetic = "BASE_RHO=28.0\nBASE_SIGMA  =  10.0\nBASE_BETA = 8.0 / 3.0  # x\n"
      expect(described_class.canonical_block_sha(cosmetic, names).first).to eq(sha)
    end

    it "returns no drift when the live hash matches the pin" do
      sha, = described_class.canonical_block_sha(src, names)
      expect(described_class.canonical_block_drift("lorenz", "bio.rb", src, names, sha)).to be_empty
    end

    it "flags drift when a pinned value changes" do
      sha, = described_class.canonical_block_sha(src, names)
      hits = described_class.canonical_block_drift("lorenz", "bio.rb", src.sub("28.0", "28.1"), names, sha)
      expect(hits.first).to include("canonical block in bio.rb changed")
    end

    it "reports a renamed/absent const separately from a hash mismatch" do
      sha, = described_class.canonical_block_sha(src, names)
      hits = described_class.canonical_block_drift("lorenz", "bio.rb", "BASE_RHO = 28.0\n", names, sha)
      expect(hits.first).to match(/pinned const\(s\) absent.*BASE_SIGMA, BASE_BETA/)
    end

    it "reports '(unpinned)' when expected_sha is blank (first-time pin, nothing recorded yet)" do
      hits = described_class.canonical_block_drift("lorenz", "bio.rb", src, names, "")
      expect(hits.first).to include("(unpinned)")
    end
  end

  describe ".unbalanced_code_fences" do
    let(:fence) { "```" }

    it "flags an odd fence count (one opened, never closed) with the opening line" do
      md = "intro\n#{fence}ruby\ncode\nmore prose\n" # single opening fence @ line 2, no close
      hits = described_class.unbalanced_code_fences(md)
      expect(hits.size).to eq(1)
      expect(hits.first).to include('line 2').and(include('unclosed'))
    end

    it "passes a balanced open+close fence block" do
      md = "intro\n#{fence}ruby\ncode\n#{fence}\ntrailing\n"
      expect(described_class.unbalanced_code_fences(md)).to be_empty
    end

    it "passes several balanced fence blocks" do
      md = "#{fence}\na\n#{fence}\ntext\n#{fence}sh\nb\n#{fence}\n"
      expect(described_class.unbalanced_code_fences(md)).to be_empty
    end

    it "reports the LAST still-open fence when balanced blocks precede it" do
      md = "#{fence}\na\n#{fence}\ntext\n#{fence}sh\nb\nEOF no close\n" # 3rd marker opens @ line 5
      expect(described_class.unbalanced_code_fences(md).first).to include('line 5')
    end

    it "counts info-string + 4-backtick fences (start_with three backticks), mirroring the guards" do
      md = "`#{fence}mermaid\ndiagram\n`#{fence}\n" # 4-backtick open+close → balanced
      expect(described_class.unbalanced_code_fences(md)).to be_empty
    end

    it "ignores ~~~ tilde fences and inline/indented backticks (the guards ignore them too)" do
      md = "~~~\ncode\n~~~\nuse #{fence}inline#{fence} here\n    #{fence}not-a-fence\n"
      expect(described_class.unbalanced_code_fences(md)).to be_empty
    end

    it "passes a file with no fences at all" do
      expect(described_class.unbalanced_code_fences("plain\nprose\nno fences\n")).to be_empty
    end
  end

  # [DOC-T.68 фаза 0] Owner/exempt constants grant immunity by NUMBER PREFIX, and a
  # number can be freed and re-populated — so a stale entry hands the previous
  # occupant's immunity to whatever lands there next (§Guard-craft #50, third face).
  # The caller checks each collected number against the live doc set; these pin the
  # COLLECTOR, whose whole job is to see every shape a constant can take.
  describe ".number_keyed_exemptions" do
    subject(:map) { described_class.number_keyed_exemptions }

    it "collects from a Regexp constant (the dominant owner-doc shape)" do
      expect(map["03_04"]).to include("LORENZ_OWNER_DOC")
    end

    it "collects from an Array constant" do
      expect(map["00_06"]).to include("DEPRECATED_EXEMPT")
    end

    it "collects from a Hash constant, reading its KEYS" do
      expect(map["00_04"]).to include("RATE_ANCHOR_HOMES")
    end

    it "attributes one number to EVERY constant that grants it" do
      expect(map["00_07"].size).to be > 1
    end

    # The load-bearing negative: a constant matching prose or a report basename names
    # no NN_NN, so the sweep must stay silent about it rather than invent a number —
    # otherwise widening the family would start reporting phantom subjects.
    it "ignores constants that name no doc number" do
      expect(map.values.flatten).not_to include("TL_CHAIN_HASH_EXEMPT", "THERMAL_STRESS_OWNER_DOC")
    end

    it "returns only NN_NN-shaped keys" do
      expect(map.keys).to all(match(/\A\d\d_\d\d\z/))
    end
  end
end
