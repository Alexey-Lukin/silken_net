# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/tracker/dashboard")

# [00_08 DRY tooling] Unit coverage for the tracker linter (rake tracker:check):
# parses the §-registry meta-line format, flags #3 conformance gaps + dangling
# canon refs. Pure functions over a fixture string — no DB, no file I/O except
# the dangling-ref doc-existence glob (uses a non-existent 99_99 prefix).
RSpec.describe Tracker::Dashboard do
  let(:markdown) do
    <<~MD
      ## 🎯 Мета
      ignored preamble
      ## §03 · Firmware
      #### FW.99 — well-formed item
      - **P1** · 🤖+👤 · → `03_05 §3.2`
      - детальний контекст
      #### FW.98 — malformed (no meta-line)
      - просто текст без пріоритету/виконавця/канону
      #### HW.99 — dangling canon ref
      - **P2** · 👤 · → `99_99 §1`
      ## 🗄️ Архів закритих пунктів
      #### FW.97 — archived, must be skipped
      - **P0** · 🤖 · → `03_05`
    MD
  end

  let(:items) { described_class.parse(markdown) }

  it "parses #### items from §/🔀 registry sections only (skips Мета + Архів)" do
    expect(items.map(&:id)).to contain_exactly("FW.99", "FW.98", "HW.99")
  end

  it "reads priority, executor(s) and canon-ref from the meta-line" do
    fw99 = items.find { |it| it.id == "FW.99" }
    expect(fw99.priority).to eq("P1")
    expect(fw99.executors).to contain_exactly(:machine, :owner)
    expect(fw99.canon).to eq("03_05 §3.2")
  end

  it "flags a malformed item missing priority/executor/canon (#3 conformance)" do
    expect(described_class.issues(items))
      .to include(a_string_matching(/FW\.98: missing priority, executor, canon-ref/))
  end

  it "passes conformance for a well-formed item" do
    expect(described_class.issues(items)).not_to include(a_string_matching(/FW\.99/))
  end

  it "flags a canon ref with no matching docs/NN_NN_*.md (#2 resolution)" do
    expect(described_class.dangling_refs(items))
      .to contain_exactly(a_string_matching(/HW\.99: canon `99_99/))
  end

  it "does not flag a canon ref that resolves to a real doc" do
    expect(described_class.dangling_refs(items)).not_to include(a_string_matching(/FW\.99/))
  end

  it "flags a canon §-ref whose section is absent in the (real) target doc (#2b)" do
    md = <<~MD
      ## §03 · Firmware
      #### FW.96 — stale section ref
      - **P0** · 🤖 · → `03_05 §9.9`
      #### FW.95 — valid section ref
      - **P0** · 🤖 · → `03_05 §3.2`
    MD
    res = described_class.section_dangling_refs(described_class.parse(md))
    expect(res).to include(a_string_matching(/FW\.96.*§9\.9 absent in 03_05/))
    expect(res).not_to include(a_string_matching(/FW\.95/))
  end
end
