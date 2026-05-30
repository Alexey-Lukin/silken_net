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
      md = "## 🔐 1. Crypto\nLoRa uses AES-128-ECB (transitional, no MAC) — see 09_06 §03.\n"
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
      expect(described_class.conformance_violations("09_06_Action_Plan_Tracker", bare)).to be_empty
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
        "09_06_Tracker", "RTC DR10+DR12 (звільнило DR11 під слот)\n")).to be_empty
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

  describe ".deprecated_terms" do
    it "flags a retired token and gives the replacement hint" do
      hits = described_class.deprecated_terms("derive via HKDF info silkennet-v1-aes256 here")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("silken-aes-128-lora-key")
    end

    it "is clean when only current tokens are present" do
      expect(described_class.deprecated_terms("HKDF info silken-aes-128-lora-key")).to be_empty
    end

    it "exposes a non-empty registry of retired tokens" do
      expect(described_class::DEPRECATED_TERMS).not_to be_empty
    end
  end

  describe ".link_label_target_mismatch" do
    it "flags a label leading with a different doc-ID than the href resolves to" do
      hits = described_class.link_label_target_mismatch("див. [`09_05 §2/§4`](09_04_GitHub_Projects_and_IaC_Automation)")
      expect(hits.size).to eq(1)
      expect(hits.first).to include("09_05").and include("09_04")
    end

    it "passes when the label leads with the same doc it links to (ref form + full-name form)" do
      expect(described_class.link_label_target_mismatch("[`05_05 §7-8`](05_05_Slashing_and_Risk_Policy)")).to be_empty
      expect(described_class.link_label_target_mismatch("[05_05_Slashing_and_Risk_Policy](05_05_Slashing_and_Risk_Policy)")).to be_empty
    end

    it "ignores a label with no doc-ID token (plain prose link text)" do
      expect(described_class.link_label_target_mismatch("[Insurance Layer mechanics](07_02_Nature_as_a_Service_Contracts)")).to be_empty
    end

    it "keys on the LEAD doc-ID only — a later secondary mention is not flagged" do
      expect(described_class.link_label_target_mismatch("[`03_04 §4.1` (див. також 05_05)](03_04_mruby_Lorenz_Attractor)")).to be_empty
    end

    it "does not match a long number that merely contains an NN_NN substring" do
      expect(described_class.link_label_target_mismatch("[реліз 2026_05 deep-dive](07_01_Vision_Mission_and_Roadmap)")).to be_empty
    end
  end
end
