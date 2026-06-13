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
        | 06 DevOps | 5 | 9 | deploy |
      MD
    end

    it "passes when every doc member-TRL sits within its module band" do
      trls = { "01_01_Anchor" => 3, "03_01_Firmware" => 6, "06_02_Akash" => 5 }
      expect(described_class.trl_range_consistency(matrix, trls)).to be_empty
    end

    it "allows a sub-doc ABOVE its row (row = min) and BELOW it (off-critical-path) — no lower bound" do
      trls = { "03_05_Crypto" => 6, "06_01_Kamal" => 4, "06_03_Prom" => 6 }
      expect(described_class.trl_range_consistency(matrix, trls)).to be_empty
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
    let(:ok) { "## ✅ Статус\n## 🔗 Cross-references\n## 📑 Зміст\n<!-- TOC:AUTO:START -->\n<!-- TOC:AUTO:END -->\n" }

    it "passes a doc carrying Статус + top Cross-references + auto-ToC markers" do
      expect(described_class.conformance_violations("03_05_Crypto", ok)).to be_empty
    end

    it "flags each missing standard element" do
      expect(described_class.conformance_violations("01_01_Anchor", "## 🎯 Мета\nbody\n"))
        .to contain_exactly("## ✅ Статус", "## 🔗 Cross-references", "📑 auto-ToC markers")
    end

    it "exempts the index, the tracker, and appendix docs" do
      bare = "## 🎯 Мета\n"
      expect(described_class.conformance_violations("00_00_SSOT_Index", bare)).to be_empty
      expect(described_class.conformance_violations("00_07_Action_Plan_Tracker", bare)).to be_empty
      expect(described_class.conformance_violations("02_06_Legacy_Breadboard_Appendix", bare)).to be_empty
    end

    it "ignores non-canon filenames (README, etc.)" do
      expect(described_class.conformance_violations("README", "x")).to be_empty
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
      expect(hits.first).to include("03_04 §4.1")
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
      expect(described_class.tokenomics_rate_drift("07_01_Nature_as_a_Service_Contracts", mint)).to be_empty
      expect(described_class.tokenomics_rate_drift("07_02_Unit_Economics_and_BOM", carbon)).to be_empty
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
    it "flags an AI-vendor name re-stated outside the 00_02 roster owner" do
      hits = described_class.ai_vendor_name_drift("00_04_Shape_Up", "Handoff: Gemini (Shaping) → Cursor (Implementation)\n")
      expect(hits.size).to eq(1) # one violation per line (first vendor reported)
      expect(hits.first).to include("AI-vendor name `Gemini`")
    end

    it "flags a vendor even inside a table cell" do
      row = "| AI-pipeline | Copilot пише SDF-обгортки |\n"
      expect(described_class.ai_vendor_name_drift("01_02_Ti", row)).not_to be_empty
    end

    it "exempts the owner 00_02, the standard 00_06, the tracker 00_07 and legacy 02_06" do
      line = "frontier-LLM: Gemini · coding-agent: Cursor / Copilot\n"
      expect(described_class.ai_vendor_name_drift("00_02_AI_Native", line)).to be_empty
      expect(described_class.ai_vendor_name_drift("00_06_SSOT_Documentation_Standard", line)).to be_empty
      expect(described_class.ai_vendor_name_drift("00_07_Action_Plan_Tracker", line)).to be_empty
      expect(described_class.ai_vendor_name_drift("02_06_Legacy_Breadboard", line)).to be_empty
    end

    it "does not flag a labelled mirror or a line referencing the 00_02 home" do
      expect(described_class.ai_vendor_name_drift(
        "01_02_Ti", "ростер — дзеркало, правити в 00_02 (Cursor/Copilot)\n")).to be_empty
    end

    it "skips fenced code and does not false-positive on lowercase cursor/grok or excluded tokens" do
      expect(described_class.ai_vendor_name_drift("03_01_Firmware", "```\nGemini api call\n```\n")).to be_empty
      expect(described_class.ai_vendor_name_drift("04_02_Business", "move the cursor; agents grok the spec\n")).to be_empty
      expect(described_class.ai_vendor_name_drift("04_05_Codex", "The Codex narrative; Claude/Opus/Sonnet/Fable\n")).to be_empty
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

    it "exempts the legacy-appendix + meta docs (they may name retired things)" do
      expect(described_class.deprecated_terms("02_06", "legacy ZP-3 + silkennet-v1-aes256")).to be_empty
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
  end

  describe ".link_label_target_mismatch" do
    it "flags a label leading with a different doc-ID than the href resolves to" do
      hits = described_class.link_label_target_mismatch("див. [`00_06 §2/§4`](00_05_GitHub_Projects_and_IaC_Automation)")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("00_06").and include("00_05")
    end

    it "passes when the label leads with the same doc it links to (ref form + full-name form)" do
      expect(described_class.link_label_target_mismatch("[`05_05 §7-8`](05_05_Slashing_and_Risk_Policy)")).to be_empty
      expect(described_class.link_label_target_mismatch("[05_05_Slashing_and_Risk_Policy](05_05_Slashing_and_Risk_Policy)")).to be_empty
    end

    it "ignores a label with no doc-ID token (plain prose link text)" do
      expect(described_class.link_label_target_mismatch("[Insurance Layer mechanics](07_01_Nature_as_a_Service_Contracts)")).to be_empty
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
      hits = described_class.bare_section_ref("08_01_Pubs", "ЧНУ Hard-Science — `08_02 §1A`\n")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("08_02 §1A")
    end

    it "skips fenced code but does NOT skip table rows (cells carry real refs)" do
      expect(described_class.bare_section_ref(
        "02_01_Hardware", "```\nсм `02_03 §9.6`\n```\n")).to be_empty
      expect(described_class.bare_section_ref(
        "02_01_Hardware", "| 9 | Buffer | НЕ 6.3V (`02_03 §6.1` derating) | $0.18 |\n").size).to eq(1)
    end

    it "flags every bare ref on a line (multiple per line)" do
      expect(described_class.bare_section_ref(
        "05_05_Slashing", "інваріант `02_01 §3.4` + сестра `02_04 §4.2`\n").size).to eq(2)
    end

    it "exempts the index, the standard-owner, the tracker, and appendix docs" do
      expect(described_class.bare_section_ref("00_00_SSOT_Index", "`05_05 §3`\n")).to be_empty
      expect(described_class.bare_section_ref("00_06_SSOT_Documentation_Standard", "| AES | `03_05 §3.7` |\n")).to be_empty
      expect(described_class.bare_section_ref("00_07_Action_Plan_Tracker", "- **P0** · → `05_05 §3`\n")).to be_empty
      expect(described_class.bare_section_ref("02_06_Legacy_Breadboard_Appendix", "`02_03 §9`\n")).to be_empty
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
         02_06_Legacy_Breadboard_Appendix manifest].each do |b|
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

  describe ".external_doc_path_drift" do
    let(:existing) { %w[00_05_GitHub_Projects_and_IaC_Automation 08_03_External_Stakeholders_Registry] }

    it "flags a docs/NN_NN path whose basename is not a current doc" do
      txt = "# Ref: docs/00_07_GitHub_Projects_and_IaC_Automation.md §2.6\n"
      expect(described_class.external_doc_path_drift(".github/labeler.yml", txt, existing))
        .to contain_exactly(a_string_matching(%r{stale doc path `docs/00_07_GitHub_Projects_and_IaC_Automation`}))
    end

    it "passes a path that resolves to a current doc (with or without .md)" do
      txt = "see docs/00_05_GitHub_Projects_and_IaC_Automation.md and docs/08_03_External_Stakeholders_Registry\n"
      expect(described_class.external_doc_path_drift("README.md", txt, existing)).to be_empty
    end

    it "skips non-NN_NN subpaths (docs/protocols/…) and bare module refs (docs/00_07)" do
      txt = "docs/protocols/ebfc/in_silico/SUMMARY.md plus a bare docs/00_07 mention\n"
      expect(described_class.external_doc_path_drift("x.md", txt, existing)).to be_empty
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

    it "does NOT flag a de-line-reffed symbol ref, a .md line-ref, or a decimal" do
      txt = "main.c (struct EdgeCache)\nsee 03_02_Queen.md:114 row\nratio 1.5:30 here\n`htim2` метроном (коментар)\n"
      expect(described_class.source_line_ref_drift("03_02", txt)).to be_empty
    end
  end
end
