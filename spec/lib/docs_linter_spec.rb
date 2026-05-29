# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/docs_linter")

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
      md = "## 🔐 1. Crypto\nLoRa uses AES-128-ECB (transitional, no MAC) — see 00_08 §03.\n"
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
      expect(described_class.conformance_violations("00_08_Action_Plan_Tracker", bare)).to be_empty
      expect(described_class.conformance_violations("02_03_appendix_legacy_breadboard", bare)).to be_empty
    end

    it "ignores non-canon filenames (README, etc.)" do
      expect(described_class.conformance_violations("README", "x")).to be_empty
    end
  end
end
