# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/mem_find"

# Coverage for the bilingual-corpus search tool. Every example below is a REAL
# false negative that plain `grep -F` produced on this corpus — the tool exists
# because a rule ("check both languages") failed five times on its own author,
# so the cases worth pinning are the ones that actually bit.
RSpec.describe MemFind do
  describe ".normalize" do
    it "sees through markdown emphasis splitting a phrase" do
      # `grep -F "пінили 201"` returned 0 against `пінили **201**`
      expect(described_class.normalize("пінили **201** на чужій цілі"))
        .to include("пінили 201")
    end

    it "folds Cyrillic case, where grep -i is unreliable" do
      expect(described_class.normalize("Гейт-ПАРА"))
        .to eq(described_class.normalize("гейт-пара"))
    end

    it "unifies apostrophe and dash variants" do
      expect(described_class.normalize("пʼять")).to eq(described_class.normalize("п'ять"))
      expect(described_class.normalize("§9–§15")).to eq(described_class.normalize("§9-§15"))
    end

    it "collapses whitespace so a line break cannot hide a phrase" do
      expect(described_class.normalize("тричі падала\n  ПІДСТАВА"))
        .to eq("тричі падала підстава")
    end
  end

  describe ".stem" do
    it "trims Slavic inflection only when the word is long enough to stay specific" do
      expect(described_class.stem("квазікристалічний")).to eq("квазікристалічн")
      expect(described_class.stem("греп")).to eq("греп")
    end
  end

  describe ".scan" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def write(name, body)
      File.write(File.join(dir, name), body).then { File.join(dir, name) }
    end

    it "finds a phrase broken by a hard wrap, reporting no line number" do
      path = write("wrapped.md", "урок: тричі падала\nПІДСТАВА, а не висновок\n")
      hits = described_class.scan([ path ], described_class.normalize("падала ПІДСТАВА"))
      expect(hits.size).to eq(1)
      expect(hits.first[1]).to be_nil # spans the break — no single line contains it
    end

    it "reports the line number when the match fits one line" do
      path = write("plain.md", "а\nдевʼять прикладів пінили **201** на чужій цілі\n")
      hits = described_class.scan([ path ], described_class.normalize("пінили 201"))
      expect(hits.map { |h| h[1] }).to eq([ 2 ])
    end

    it "returns nothing for an absent fact — the honest negative" do
      path = write("plain.md", "нічого спільного\n")
      expect(described_class.scan([ path ], described_class.normalize("квазікристал"))).to be_empty
    end
  end
end
