# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/wiki_link_normalizer")

# [OPS] Unit coverage for the wiki link normalizer (rake wiki:sync engine).
# Pure functions over fixture strings — filesystem existence is injected.
RSpec.describe WikiLinkNormalizer do
  # Repo-relative paths the fake `exists` probe will treat as present.
  let(:present) do
    %w[
      docs/protocols/ebfc/in_silico/SUMMARY.md
      docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md
      tools/in_silico/README.md
      .github/labels.yml
      docs/images/marchuk_trees.png
    ].to_set
  end

  let(:normalizer) do
    described_class.new(
      canon_slugs: %w[00_08_Action_Plan_Tracker 05_02_Proof_of_Growth_Pipeline 04_06_Testing_Guide_and_Coverage],
      repo: "Alexey-Lukin/silken_net",
      exists: ->(rel) { present.include?(rel) }
    )
  end

  def body_of(md) = normalizer.call(md).body

  describe "external + anchor links (untouched)" do
    it "leaves http(s) and mailto links alone" do
      md = "See [x](https://example.com/a.md) and [m](mailto:a@b.io)."
      expect(body_of(md)).to eq(md)
    end

    it "leaves pure in-page anchors alone" do
      md = "Jump to [top](#overview)."
      expect(body_of(md)).to eq(md)
    end
  end

  describe "canonical doc links → bare wiki links" do
    it "is idempotent on an already-bare wiki link" do
      expect(body_of("[a](00_08_Action_Plan_Tracker)")).to eq("[a](00_08_Action_Plan_Tracker)")
    end

    it "strips a .md suffix and a ../ prefix" do
      expect(body_of("[a](../00_08_Action_Plan_Tracker.md)")).to eq("[a](00_08_Action_Plan_Tracker)")
    end

    it "strips a docs/ prefix and preserves the #anchor" do
      expect(body_of("[a](../docs/05_02_Proof_of_Growth_Pipeline#guard)"))
        .to eq("[a](05_02_Proof_of_Growth_Pipeline#guard)")
    end

    it "handles a plain NN_NN_Name.md link" do
      expect(body_of("[t](04_06_Testing_Guide_and_Coverage.md)")).to eq("[t](04_06_Testing_Guide_and_Coverage)")
    end
  end

  describe "non-canonical repo files → absolute blob URLs" do
    it "rewrites a docs-relative path" do
      expect(body_of("[s](protocols/ebfc/in_silico/SUMMARY.md)"))
        .to eq("[s](https://github.com/Alexey-Lukin/silken_net/blob/main/docs/protocols/ebfc/in_silico/SUMMARY.md)")
    end

    it "rewrites a ../ path that lives at the repo root" do
      expect(body_of("[r](../tools/in_silico/README.md)"))
        .to eq("[r](https://github.com/Alexey-Lukin/silken_net/blob/main/tools/in_silico/README.md)")
    end

    it "rewrites an inconsistent ../protocols path that actually lives under docs/" do
      expect(body_of("[p](../protocols/ebfc/in_silico/PIPELINE_STATUS.md)"))
        .to eq("[p](https://github.com/Alexey-Lukin/silken_net/blob/main/docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md)")
    end

    it "keeps an #anchor on the blob URL" do
      expect(body_of("[l](../.github/labels.yml#x)"))
        .to eq("[l](https://github.com/Alexey-Lukin/silken_net/blob/main/.github/labels.yml#x)")
    end
  end

  describe "images" do
    it "rewrites to images/<basename> and records the source for carry-over" do
      res = normalizer.call("![Marchuk](images/marchuk_trees.png)")
      expect(res.body).to eq("![Marchuk](images/marchuk_trees.png)")
      expect(res.images).to eq(%w[docs/images/marchuk_trees.png])
    end

    it "leaves an image untouched and warns when the file is missing" do
      res = normalizer.call("![ghost](images/missing.png)")
      expect(res.body).to eq("![ghost](images/missing.png)")
      expect(res.images).to be_empty
      expect(res.unresolved).to eq(%w[images/missing.png])
    end
  end

  describe "unresolved links" do
    it "leaves a link to a missing repo file untouched and records it" do
      res = normalizer.call("[d](../DEPLOYMENT.md)")
      expect(res.body).to eq("[d](../DEPLOYMENT.md)")
      expect(res.unresolved).to eq(%w[../DEPLOYMENT.md])
    end
  end

  describe "fenced code blocks are left untouched" do
    it "rewrites prose links but not links inside a ``` fence" do
      md = <<~MD
        Prose [a](04_06_Testing_Guide_and_Coverage.md).

        ```ruby
        # example: [b](04_06_Testing_Guide_and_Coverage.md)
        ```

        After [c](04_06_Testing_Guide_and_Coverage.md).
      MD
      out = body_of(md)
      expect(out).to include("[a](04_06_Testing_Guide_and_Coverage)")
      expect(out).to include("[c](04_06_Testing_Guide_and_Coverage)")
      expect(out).to include("[b](04_06_Testing_Guide_and_Coverage.md)") # inside fence: unchanged
    end
  end

  describe "de-duplication" do
    it "reports each carried image and unresolved link once" do
      md = "![x](images/marchuk_trees.png) ![x](images/marchuk_trees.png) [d](../DEPLOYMENT.md) [d](../DEPLOYMENT.md)"
      res = normalizer.call(md)
      expect(res.images).to eq(%w[docs/images/marchuk_trees.png])
      expect(res.unresolved).to eq(%w[../DEPLOYMENT.md])
    end
  end
end
