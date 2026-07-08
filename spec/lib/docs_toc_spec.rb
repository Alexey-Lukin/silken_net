# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/docs_toc"

# [SSOT anti-drift] Unit coverage for the auto-ToC engine (rake docs:toc +
# docs:check_refs ToC-sync gate). Pure functions over fixture strings.
RSpec.describe DocsToc do
  describe ".github_anchor" do
    it "reproduces real repo anchors incl. emoji / punctuation / path edge cases" do
      expect(described_class.github_anchor("3.4а HKDF Key Derivation Protocol Design 🤖"))
        .to eq("34а-hkdf-key-derivation-protocol-design-")
      expect(described_class.github_anchor("🗺️ 2. Soldier RTC Backup Register Map (DR0..DR19) — Canonical SSOT [DOC.3]"))
        .to eq("-2-soldier-rtc-backup-register-map-dr0dr19--canonical-ssot-doc3")
    end
  end

  describe ".link_text" do
    it "strips leading/trailing emoji and link-breaking [TAG]s / code spans" do
      expect(described_class.link_text("🌲 1. Soldier — Архітектура")).to eq("1. Soldier — Архітектура")
      expect(described_class.link_text("🧪 10. Тести [DOC.3]")).to eq("10. Тести")
      expect(described_class.link_text("11. Bio-Contract (`firmware/x.rb`)")).to eq("11. Bio-Contract")
      expect(described_class.link_text("13. EMA — FW.21 🤖")).to eq("13. EMA — FW.21")
    end
  end

  describe ".content_headings" do
    it "lists content ## headings, skipping front-matter and fenced examples" do
      md = <<~MD
        # Title
        ## 🎯 Мета
        ## ✅ Статус
        ## 🔗 Cross-references
        ## 📑 Зміст
        ## 🛠️ 1. Tools
        ```
        ## 🛑 Блокери
        ```
        ## 🔐 2. Crypto
      MD
      expect(described_class.content_headings(md)).to eq([ "🛠️ 1. Tools", "🔐 2. Crypto" ])
    end

    it "keeps a content heading that merely CONTAINS a front word (exact-match front-matter)" do
      md = <<~MD
        ## ✅ Статус
        ## 🏭 8. Статус Виробництва та Прототипування
        ## 📈 4. Зв'язок Метаболізму з Атрактором
        ## 📋 Статус Імплементації
      MD
      expect(described_class.content_headings(md)).to eq([
        "🏭 8. Статус Виробництва та Прототипування",
        "📈 4. Зв'язок Метаболізму з Атрактором",
        "📋 Статус Імплементації"
      ])
    end
  end

  describe ".existing_descriptions" do
    it "returns {} when the markdown has no TOC:AUTO markers to match" do
      expect(described_class.existing_descriptions("# Title\nno markers here\n")).to eq({})
    end
  end

  describe ".regen" do
    let(:md) do
      <<~MD
        # Title
        ## 🔗 Cross-references
        x
        ## 📑 Зміст

        #{DocsToc::START_MARK}
        stale
        #{DocsToc::END_MARK}

        ## 🛠️ 1. Tools
        ## 🔐 2. Crypto
      MD
    end

    it "fills the markers with a linked ToC built from current headings" do
      out, changed = described_class.regen(md)
      expect(changed).to be(true)
      expect(out).to include("- [1. Tools](#-1-tools)", "- [2. Crypto](#-2-crypto)")
      expect(out).not_to include("stale")
    end

    it "is idempotent — a second regen makes no change" do
      out, = described_class.regen(md)
      _, changed = described_class.regen(out)
      expect(changed).to be(false)
    end

    it "no-ops when markers are absent" do
      plain = "# Title\n## 🛠️ 1. Tools\n"
      expect(described_class.regen(plain)).to eq([ plain, false ])
    end

    it "preserves a curated `— description` across regeneration (keyed by anchor)" do
      md = <<~MD
        ## 📑 Зміст

        #{DocsToc::START_MARK}
        - [1. Tools](#-1-tools) — keep me
        #{DocsToc::END_MARK}

        ## 🛠️ 1. Tools
        ## 🔐 2. Crypto
      MD
      out, = described_class.regen(md)
      expect(out).to include("- [1. Tools](#-1-tools) — keep me")
      expect(out).to include("- [2. Crypto](#-2-crypto)")
    end
  end
end
