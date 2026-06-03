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

  # [dup-guard blind-spot fix, 2026-06-01] An ID used as BOTH a registry table row
  # AND a #### heading (the DOC.12 ↔ DOC.13 collision) escaped the heading-only
  # tally. table_row_ids surfaces first-cell IDs so the caller can merge them.
  describe ".table_row_ids" do
    let(:md) do
      <<~MD
        ## 🔀 Cross-cutting · Doc-drift (DOC)
        | ID | Невідповідність | Дія | Статус |
        |----|-----------------|-----|--------|
        | DOC.12 | Taxonomy P4 | — | ✅ Done |
        | DOC.10 | deferred decision | — | 🟡 |
        #### DOC.12 — round item that collides with the table row above
        - **P2** · 🤖 · → `00_06 §3`
        ## 🗄️ Архів закритих пунктів
        | ARCH.1 | non-registry section — must be skipped | — | ✅ |
      MD
    end

    it "extracts first-cell IDs from registry table rows (skips header/separator + Архів)" do
      expect(described_class.table_row_ids(md)).to contain_exactly("DOC.12", "DOC.10")
    end

    it "lets the dup tally catch a table-row ↔ #### heading ID collision" do
      ids = described_class.parse(md).map(&:id) + described_class.table_row_ids(md)
      expect(ids.tally.select { |_, v| v > 1 }).to eq("DOC.12" => 2)
    end
  end

  # [inbound 00_07 item-ref resolution, 2026-06-03] Other docs reference a tracker
  # item as `[`00_07` — <ID>](00_07_…)`; nothing validated <ID> existed, so
  # `06_02 → 00_07 DOC.5` rotted silently. all_item_ids spans ALL sections (incl.
  # 📌/🗄️, unlike parse/table_row_ids); the ref-ID requires a `.`/`-` so a
  # directory-title link is not a false positive.
  describe ".all_item_ids + .inbound_ref_violations" do
    it "collects #### + table-row IDs across ALL sections (incl. 🗄️ Архів, unlike parse)" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.1 — item
        - **P0** · 🤖 · → `03_05`
        ## 📌 Backlog
        | E.60 | backlog finding | note |
        ## 🗄️ Архів
        #### DOC-T.13 — archived item
        - **P0** · 🤖 · → `00_06`
      MD
      expect(described_class.all_item_ids(md)).to include("FW.1", "E.60", "DOC-T.13")
    end

    it "captures an em-dash ID ref but NOT a directory-title link (FP guard)" do
      expect("див. [`00_07` — DOC.5](00_07_Action_Plan_Tracker)".scan(described_class::INBOUND_REF_RE).flatten)
        .to eq([ "DOC.5" ])
      expect("[`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker)".scan(described_class::INBOUND_REF_RE).flatten)
        .to be_empty
    end

    it "flags an inbound ref to a non-existent 00_07 item, passes a real one" do
      require "tmpdir"
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "00_07_Action_Plan_Tracker.md"),
                   "## §03 · Firmware\n#### FW.1 — real item\n- **P0** · 🤖 · → `03_05`\n")
        File.write(File.join(dir, "06_99_Sample.md"),
                   "ok [`00_07` — FW.1](00_07_Action_Plan_Tracker); bad [`00_07` — DOC.5](00_07_Action_Plan_Tracker)\n")
        expect(described_class.inbound_ref_violations(dir))
          .to contain_exactly(a_string_matching(/06_99_Sample → `00_07 — DOC\.5`/))
      end
    end
  end

  # [emoji-prefix blind spot, 2026-06-01] `#### 🌿 UNI.13a — …` was silently dropped
  # by the `[A-Z]`-anchored match, hiding UNI.13a / BIZ.12 from every tracker check.
  it "parses a #### item behind a leading emoji prefix" do
    md = <<~MD
      ## §08 · Академічна інтеграція
      #### 🌿 UNI.13a — emoji-prefixed item
      - **P1** · 👤 · → `08_01 §1.3`
    MD
    expect(described_class.parse(md).map(&:id)).to contain_exactly("UNI.13a")
  end

  # [section↔canon-home guard, 2026-06-01] One-Home for the tracker: a #### under
  # `## §NN` must canon-ref module NN (a `§03/§05` header declares a multi-module set).
  describe ".section_home_violations" do
    let(:md) do
      <<~MD
        ## §06 · Deploy / Observability / Secrets / Ops
        #### S1.1 — секрети (module 06 — OK)
        - **P0** · 👤 · → `06_04`
        #### MISPLACED.1 — backend item wrongly bucketed under §06
        - **P1** · 🤖 · → `04_02 §3`
        ## §03/§05 · Безпека (Edge crypto + Web3)
        #### SEC.1 — web3 admin (module 05 — OK under multi-module §03/§05)
        - **P0** · 👤 · → `05_03`
        ## 🔀 Cross-cutting · Doc-drift (DOC)
        #### DOC.9 — cross-cutting (module-agnostic — exempt)
        - **P2** · 🤖 · → `04_02`
      MD
    end

    let(:violations) { described_class.section_home_violations(described_class.parse(md)) }

    it "flags an item whose canon module ≠ its §NN section module" do
      expect(violations).to contain_exactly(a_string_matching(/MISPLACED\.1.*module 04.*§06/))
    end

    it "passes a multi-module header (§05 item under §03/§05) and exempts 🔀 cross-cutting" do
      expect(violations).not_to include(a_string_matching(/SEC\.1|S1\.1|DOC\.9/))
    end
  end

  # [#1 auto-dashboard] render groups open items by executor, lists only P0/P1
  # focus and folds P2/P3 into a tail count. Also exercises the checkbox-bullet
  # executor pickup (`- [ ]  🤖`) that the meta-line path doesn't reach.
  describe ".render" do
    let(:md) do
      <<~MD
        ## §03 · Firmware
        #### FW.1 — full machine item
        - **P0** · 🤖 · → `03_05`
        #### FW.2 — checkbox-only executor, no priority or canon
        - [ ] 🤖 виконати без пріоритету та канону
        #### FW.3 — machine low-priority tail
        - **P2** · 🤖 · → `03_05`
        #### OWN.1 — owner focus item
        - **P1** · 👤 · → `06_04`
        #### BLK.1 — blocked low-priority only
        - **P2** · 🔗 · → `04_02`
      MD
    end
    let(:rendered) { described_class.render(described_class.parse(md)) }

    it "lists a P0/P1 focus item with priority and canon under its role heading" do
      expect(rendered).to include("🤖 Machine-doable")
      expect(rendered).to include("`FW.1` **P0** — full machine item → `03_05`")
    end

    it "renders a checkbox-only executor item with neither priority nor canon" do
      # FW.2's executor is picked up solely from the `- [ ]  🤖` checkbox bullet.
      expect(rendered).to include("`FW.2` — checkbox-only executor, no priority or canon")
    end

    it "folds P2/P3 items into a tail count instead of listing them" do
      expect(rendered).to include("+ 1 × P2/P3")
      expect(rendered).not_to include("FW.3")
    end

    it "renders an empty-state with a P2/P3 note for a role with no focus item" do
      expect(rendered).to match(%r{жодного відкритого P0/P1; 1 × P2/P3})
    end

    it "renders a bare empty-state when a role has no items at all" do
      sparse = described_class.render(described_class.parse(<<~MD))
        ## §03 · Firmware
        #### FW.1 — lone machine P0
        - **P0** · 🤖 · → `03_05`
      MD
      # owner + blocked roles have zero items → empty-state without a P2/P3 tail
      expect(sparse).to match(%r{\(жодного відкритого P0/P1\)_})
    end
  end

  describe ".regenerate" do
    it "rewrites the AUTO block in place from the registry" do
      require "tempfile"
      md = <<~MD
        ## §03 · Firmware
        #### FW.1 — machine P0
        - **P0** · 🤖 · → `03_05`

        #{described_class::START_MARK}
        stale dashboard content
        #{described_class::END_MARK}
      MD
      Tempfile.create([ "tracker", ".md" ]) do |f|
        f.write(md)
        f.flush
        described_class.regenerate(f.path)
        result = File.read(f.path)
        expect(result).to include("`FW.1` **P0** — machine P0")
        expect(result).not_to include("stale dashboard content")
        expect(result).to include(described_class::START_MARK).and include(described_class::END_MARK)
      end
    end

    it "raises when the AUTO markers are absent" do
      require "tempfile"
      Tempfile.create([ "tracker", ".md" ]) do |f|
        f.write("## §03 · Firmware\n#### FW.1 — x\n- **P0** · 🤖 · → `03_05`\n")
        f.flush
        expect { described_class.regenerate(f.path) }.to raise_error(/AUTO markers not found/)
      end
    end
  end

  describe ".check" do
    it "reports drift=false and the open count when the AUTO block is in sync" do
      require "tempfile"
      md = <<~MD
        ## §03 · Firmware
        #### FW.1 — machine P0
        - **P0** · 🤖 · → `03_05`

        #{described_class::START_MARK}
        #{described_class::END_MARK}
      MD
      Tempfile.create([ "tracker", ".md" ]) do |f|
        f.write(md)
        f.flush
        described_class.regenerate(f.path) # bring the AUTO block in sync first
        result = described_class.check(f.path)
        expect(result[:drift]).to be(false)
        expect(result[:open]).to eq(1)
      end
    end

    it "reports drift=true when the doc has no AUTO block at all" do
      require "tempfile"
      Tempfile.create([ "tracker", ".md" ]) do |f|
        f.write("## §03 · Firmware\n#### FW.1 — machine P0\n- **P0** · 🤖 · → `03_05`\n")
        f.flush
        expect(described_class.check(f.path)[:drift]).to be(true)
      end
    end
  end
end
