# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/offering_lexicon_check"

# [BIZ.22] Unit coverage for the offering-lexicon gate. Pure functions + fixture-tree
# audits (no Rails/DB) — the same no-Rails, fixture-driven style as the other
# standalone script-guards. The false-positive cases carry as much weight as the
# positives here: this guard scans a repository whose most common noun (gyroid)
# contains "ROI" and whose language keyword is `yield`.
RSpec.describe OfferingLexicon do
  # Build a throwaway repo tree; yields the fake root.
  def with_tree(files)
    Dir.mktmpdir do |root|
      files.each do |rel, body|
        path = File.join(root, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      yield root
    end
  end

  describe ".locale_value" do
    it "returns the rendered value, not the key" do
      expect(described_class.locale_value("      total_invested: Total Invested\n"))
        .to eq("Total Invested")
    end

    it "ignores an investment-flavoured KEY whose value is service wording" do
      # The whole point of scanning values only: `investment:` is a YAML identifier no
      # user sees; renaming it would move every t() call-site for zero legal effect.
      expect(described_class.locale_value("        investment: Service Fee\n")).to eq("Service Fee")
    end

    it "returns nil for a parent key, a block scalar and a blank" do
      expect(described_class.locale_value("    metrics:\n")).to be_nil
      expect(described_class.locale_value("    body: |\n")).to be_nil
      expect(described_class.locale_value("\n")).to be_nil
    end
  end

  describe ".exempt?" do
    it "exempts the documents whose job is to analyse the risk" do
      %w[docs/00_07_Action_Plan_Tracker.md docs/protocols/legal/securities_review.md
         docs/00_06_SSOT_Documentation_Standard.md .claude/skills/legal-business/SKILL.md
         CHANGELOG.md].each do |rel|
        expect(described_class.exempt?(rel)).to be(true), "expected #{rel} exempt"
      end
    end

    it "does NOT exempt the storefront" do
      %w[docs/manifest.md README.md config/locales/reports/uk.yml].each do |rel|
        expect(described_class.exempt?(rel)).to be(false), "expected #{rel} guarded"
      end
    end
  end

  describe "HARD tier — the storefront" do
    it "fails on offering lexicon returning to a rendered locale value" do
      with_tree("config/locales/reports/uk.yml" => "  reports:\n    subtitle: Звітність для інвесторів\n") do |root|
        expect(described_class.audit(root)[:hard].size).to eq(1)
      end
    end

    it "fails on a homonym returning to a rendered locale value" do
      with_tree("config/locales/reports/en.yml" => "  hero:\n    sub: SCC Invested\n") do |root|
        expect(described_class.audit(root)[:hard]).not_to be_empty
      end
    end

    it "passes on the service wording the sweep established" do
      with_tree("config/locales/reports/en.yml" => <<~YML) do |root|
        en:
          reports:
            metrics:
              total_invested: Total Contracted
            hero:
              capital_injected: Contracted Amount
              capital_injected_sub: SCC Contracted
            subtitle: Consolidated reporting for clients.
      YML
        expect(described_class.audit(root)[:hard]).to be_empty
      end
    end

    it "flags investor framing in the public manifesto and README" do
      with_tree("docs/manifest.md" => "Returns for investors are indexed to growth.\n",
                "README.md" => "Платформа для інвесторів.\n") do |root|
        expect(described_class.audit(root)[:hard].size).to eq(2)
      end
    end
  end

  # These are the cases that decide whether the guard survives contact with the repo.
  describe "false positives it must NOT report" do
    it "does not read ROI inside `gyroid`" do
      # g-y-r-o-i-d. An unbounded case-insensitive scan called the manifesto three
      # violations, every one of them this word.
      with_tree("docs/manifest.md" => <<~MD) do |root|
        Macroporous titanium gyroids print on commercial DMLS platforms.
        The gyroid admits sap; gyroid porosity is ~65%.
      MD
        expect(described_class.audit(root)[:hard]).to be_empty
      end
    end

    it "does not read `yield` as Ruby's block keyword or an Enumerator::Yielder" do
      with_tree("app/controllers/api/v1/x_controller.rb" => <<~RB) do |root|
        def each_row
          yield "a"
          yielder << CSV.generate_line([ "Clusters" ])
        end
      RB
        expect(described_class.audit(root)[:advisory]).to be_empty
      end
    end

    it "still reports a compound financial yield identifier in a response" do
      with_tree("app/controllers/api/v1/x_controller.rb" =>
        "render json: { yield_forecast: 1, real_yield: 2 }\n") do |root|
        expect(described_class.audit(root)[:advisory]).not_to be_empty
      end
    end

    it "does not flag a publication or R&D portfolio in prose" do
      # README says «портфель UNI.19» about Q1 papers; 00_03 says «R&D portfolio».
      with_tree("README.md" => "8 живих Q1-статей (портфель UNI.19) та R&D portfolio.\n") do |root|
        expect(described_class.audit(root)[:hard]).to be_empty
      end
    end

    it "does not flag our own unit-economics payback wording" do
      # 02_06 §7 exists to state OUR payback; only the customer's return is the problem,
      # and no regex tells them apart — so ROI/payback are locale-value-only.
      with_tree("README.md" => "юніт-економіка та ROI кластера; payback ~58 місяців\n") do |root|
        expect(described_class.audit(root)[:hard]).to be_empty
      end
    end

    it "does not flag APR, whose hardware meaning here is undocumented" do
      with_tree("config/locales/maintenance/lv.yml" => "  hw: APR\n") do |root|
        expect(described_class.audit(root)[:hard]).to be_empty
      end
    end

    it "skips Ruby comments — internal notes are not what a customer receives" do
      with_tree("app/controllers/api/v1/x_controller.rb" =>
        "# Фінансовий звіт для інвесторів Series C\nrender json: { ok: 1 }\n") do |root|
        expect(described_class.audit(root)[:advisory]).to be_empty
      end
    end
  end

  describe "ADVISORY tier — never fatal, but visible" do
    it "reports response keys without touching the HARD verdict" do
      with_tree("app/controllers/api/v1/contracts_controller.rb" => <<~RB) do |root|
        render json: { total_invested: 1, portfolio_health: 2, market_value_usd: 3 }
      RB
        r = described_class.audit(root)
        expect(r[:advisory].size).to eq(1) # first matching term per line
        expect(r[:hard]).to be_empty
      end
    end

    it "reports a literal report header printed into a downloadable file" do
      with_tree("app/controllers/api/v1/reports_controller.rb" =>
        %(CSV.generate_line([ "Total Invested", v ])\n)) do |root|
        expect(described_class.audit(root)[:advisory]).not_to be_empty
      end
    end

    it "keeps a homonym in a response key ADVISORY even though its scope is also HARD for OFFERING" do
      with_tree("app/blueprints/ai_insight_blueprint.rb" => "field :yield_impact\n") do |root|
        r = described_class.audit(root)
        expect(r[:advisory]).not_to be_empty
        expect(r[:hard]).to be_empty
      end
    end
  end

  # ⚖️ 2026-09-22 (00_07 BIZ.22): OFFERING went HARD in the code layer with a site-keyed
  # allowlist. These cases exist because the allowlist is the only thing that can make
  # this tier lie — and it lies in two directions, so both are pinned.
  describe "HARD tier — the code layer (OFFERING)" do
    it "fails on offering lexicon anywhere in the guarded code scope" do
      with_tree("app/blueprints/tree_blueprint.rb" => %(DIVIDEND_RATE = 1\n)) do |root|
        expect(described_class.audit(root)[:hard].size).to eq(1)
      end
    end

    it "does NOT fail on the two ratified ⛔ sites" do
      with_tree(
        "app/views/components/contracts/show.rb" => %(t(".legal.early_exit_fee")\n),
        "db/seeds.rb" => %(cancellation_terms: { "early_exit_fee_percent" => 15 }\n)
      ) do |root|
        expect(described_class.audit(root)[:hard]).to be_empty
      end
    end

    it "still fails when the SAME wording appears at a THIRD site — the exemption is keyed to the PATH" do
      with_tree("app/blueprints/tree_blueprint.rb" => %(EARLY_EXIT_FEE = 15\n)) do |root|
        expect(described_class.audit(root)[:hard].size).to eq(1)
      end
    end

    it "does NOT amnesty a different offering term at a ratified site" do
      with_tree("db/seeds.rb" => %(investor_id: 1\n)) do |root|
        expect(described_class.audit(root)[:hard].size).to eq(1)
      end
    end
  end

  describe ".dead_exemptions" do
    it "names an exemption that matched nothing, so it cannot outlive its verdict" do
      expect(described_class.dead_exemptions([]))
        .to include(a_string_including("db/seeds.rb", "early-exit fee framing"))
    end

    it "stays silent once every declared exemption has a live hit" do
      live = described_class::RATIFIED_CODE_SITES.flat_map do |path, labels|
        labels.map { |l| "#{path}:1 — #{l}: whatever" }
      end
      expect(described_class.dead_exemptions(live)).to be_empty
    end
  end
end
