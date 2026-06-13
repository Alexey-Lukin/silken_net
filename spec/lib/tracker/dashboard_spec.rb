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

  # [whole-file §-ref guard, 2026-06-09] catches bare code-span §-refs in 📌/🗄️ cells +
  # prose that section_dangling_refs (#### meta-refs only) misses. Uses the real docs.
  describe ".file_section_dangling_refs (whole-file §-ref resolution)" do
    it "flags a bare code-span §-ref (backlog/archive cell) to an absent section" do
      expect(described_class.file_section_dangling_refs("| E.99 | x | `08_02` §1.3 (Ярмілко) | y |"))
        .to include(a_string_matching(%r{08_02 §1\.3}))
    end

    it "does not flag a valid bare §-ref" do
      expect(described_class.file_section_dangling_refs("| E.99 | x | `08_02` §1B | y |")).to be_empty
    end

    it "is boundary-aware: §1.3 does NOT resolve against a 2.1.3 heading" do
      # 08_01 has §2.1.3 but no §1.3 — the retired substring `include?` would false-pass.
      expect(described_class.file_section_dangling_refs("ref `08_01 §1.3` here"))
        .to include(a_string_matching(%r{08_01 §1\.3}))
    end

    it "resolves a parent-group ref whose children exist (§4а ⇐ 4а.1..4а.5)" do
      expect(described_class.file_section_dangling_refs("[`05_02 §4а`](05_02_Proof_of_Growth_Pipeline)")).to be_empty
    end

    it "skips a lowercase '.x' wildcard placeholder, resolves a real section" do
      expect(described_class.file_section_dangling_refs("`03_03 §10.x` + `03_03 §3.4`")).to be_empty
    end
  end

  describe ".heading_anchors" do
    it "extracts leading heading numbers, skipping letter-led (Стаття N) headings" do
      expect(described_class.heading_anchors("## 🎓 1B. ФОТІУС\n### 2.1.3. Foo\n### Стаття 1: Bar\n## 🎯 Мета"))
        .to contain_exactly("1b", "2.1.3")
    end
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

    it "extracts a first-cell ID behind a leading ✅/emoji status prefix" do
      md = "## 🔀 Cross-cutting\n| ✅ OPS.5 | done | — | ✅ |\n| 🌿 E.59 | finding | — | 🌿 |\n"
      expect(described_class.table_row_ids(md)).to contain_exactly("OPS.5", "E.59")
    end
  end

  # [dup-guard scope widened, 2026-06-03] An ID reused by a 📌 Backlog / 🗄️ Архів row
  # (skipped by the registry-only tally) escaped silently — the `OPS.5` §07-heading ↔
  # 📌-backlog-row collision. duplicate_ids spans the whole file via all_item_ids.
  describe ".duplicate_ids" do
    it "catches an active #### heading ↔ 📌 Backlog table-row ID reuse (the OPS.5 class)" do
      md = <<~MD
        ## §07 · Юридичні / Бізнес
        #### OPS.5 — active procurement item
        - **P1** · 👤 · → `07_02 §8.1.1`
        ## 📌 Backlog · Додаткові знахідки
        | ✅ OPS.5 | a different, done item reusing the ID | note |
      MD
      expect(described_class.duplicate_ids(md)).to eq("OPS.5" => 2)
    end

    it "passes when every ID is unique across registry + backlog + archive" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.1 — item
        - **P0** · 🤖 · → `03_05`
        ## 📌 Backlog
        | ✅ E.58 | done finding | note |
        ## 🗄️ Архів
        | OPS.5 | archived item keeping its origin ID | `00_05 §1.1` |
      MD
      expect(described_class.duplicate_ids(md)).to be_empty
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

  # [prose ID-ref guard, 2026-06-03] Status lines cite IDs in prose after a 00_07 link
  # (`→ 00_07 (S4.3, INF.4, S6.1)`); a wrong/missing id (S6.1 Redis vs S5.6 GCS; OBS.1
  # before it had a row) was invisible to the em-dash gate. Wildcards/slash-families handled.
  describe ".inbound_prose_ref_violations + .expand_prose_ids" do
    it "expands slash-digit families, splits full-ID slashes, skips X.* wildcards" do
      expect(described_class.expand_prose_ids("S4.3, INF.3/4/6, UNI.*"))
        .to contain_exactly("S4.3", "INF.3", "INF.4", "INF.6")
      expect(described_class.expand_prose_ids("HW.14/15/18, S2.2/S2.3"))
        .to contain_exactly("HW.14", "HW.15", "HW.18", "S2.2", "S2.3")
    end

    it "flags a wrong/missing prose ID after a 00_07 link, passes real ones" do
      require "tmpdir"
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "00_07_Action_Plan_Tracker.md"),
                   "## §06 · Ops\n#### S5.6 — real item\n- **P0** · 👤 · → `06_02`\n")
        File.write(File.join(dir, "06_99_Sample.md"),
                   "ok → [`00_07`](00_07_Action_Plan_Tracker) (S5.6); bad → " \
                   "[`00_07`](00_07_Action_Plan_Tracker) (S6.1, OBS.1)\n")
        expect(described_class.inbound_prose_ref_violations(dir))
          .to contain_exactly(a_string_matching(/S6\.1/), a_string_matching(/OBS\.1/))
      end
    end
  end

  # CHEM.N in-silico note refs: the HW.5.IS chemistry backlog is a bulleted list whose notes
  # carry CHEM.N IDs (standardized from ad-hoc `note N`). chem_note_ids collects the def set
  # (the leading ID-cluster before the em-dash → compound `+` & slash, checkbox optional);
  # chem_note_ref_violations flags a CHEM.N in any doc/script that doesn't resolve. A CHEM ref
  # in a DESCRIPTION (after the em-dash) is NOT mistaken for a def.
  describe ".chem_note_ids + .chem_note_ref_violations" do
    it "collects simple, compound (+), slash-pair and checkbox-less defs; ignores a description ref" do
      md = <<~MD
        - [ ] CHEM.6 — simple open note
        - [x] CHEM.22 + CHEM.5 — compound (two ids in one bullet)
        - [ ] CHEM.20/26 — slash-merged duplicate pair
        - CHEM.28 — corrected-out, no checkbox
        - [ ] CHEM.15 — subsumed by CHEM.29 (a ref in the DESCRIPTION, not a def)
      MD
      expect(described_class.chem_note_ids(md))
        .to contain_exactly("CHEM.6", "CHEM.22", "CHEM.5", "CHEM.20", "CHEM.26", "CHEM.28", "CHEM.15")
    end

    it "expands a slash-family into each member" do
      expect(described_class.expand_chem("CHEM.20/26")).to eq(%w[CHEM.20 CHEM.26])
      expect(described_class.expand_chem("CHEM.6")).to eq(%w[CHEM.6])
    end

    it "flags a doc CHEM ref with no matching note, passes defined ones (skips 00_07 itself)" do
      require "tmpdir"
      require "fileutils"
      Dir.mktmpdir do |root|
        docs = File.join(root, "docs")
        FileUtils.mkdir_p(docs)
        File.write(File.join(docs, "00_07_Action_Plan_Tracker.md"),
                   "- [ ] CHEM.6 — defined\n- [ ] CHEM.20/26 — slash pair\n")
        File.write(File.join(docs, "01_99_Sample.md"),
                   "ok (CHEM.6) and (CHEM.26); bad (CHEM.99)\n")
        expect(described_class.chem_note_ref_violations(docs))
          .to contain_exactly(a_string_matching(/01_99_Sample.*CHEM\.99/))
      end
    end

  # A bare CHEM.N in a no-em-dash checkbox bullet is ambiguous (a whole-line dup-scan reads it
  # as a phantom 2nd def); status bullets must reword. Em-dash defs/refs are unambiguous → skip.
  describe ".chem_ambiguous_token_lines" do
    it "flags a bare CHEM token in a no-em-dash checkbox bullet; ignores em-dash defs and CHEM-free bullets" do
      md = <<~MD
        - [x] ✅ Re-run DONE: 24b FO-DFT (CHEM.14) → 25 → done
        - [x] CHEM.14 — FO-DFT t_ij rigor (real def, em-dash)
        - [ ] CHEM.8 + CHEM.2 — compound def (em-dash)
        - [ ] Capstones: protein QM-cluster (no CHEM token)
      MD
      expect(described_class.chem_ambiguous_token_lines(md))
        .to contain_exactly(a_string_matching(/CHEM\.14.*no-em-dash/))
    end
  end
  end

  # [emoji-prefix blind spot, 2026-06-01] `#### 🌿 UNI.13a — …` was silently dropped
  # by the `[A-Z]`-anchored match, hiding UNI.13a / BIZ.12 from every tracker check.
  it "parses a #### item behind a leading emoji prefix" do
    md = <<~MD
      ## §08 · Академічна інтеграція
      #### 🌿 UNI.13a — emoji-prefixed item
      - **P1** · 👤 · → `08_01 §1B`
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
      expect(rendered).to include('жодного відкритого P0/P1; 1 × P2/P3')
    end

    it "renders a bare empty-state when a role has no items at all" do
      sparse = described_class.render(described_class.parse(<<~MD))
        ## §03 · Firmware
        #### FW.1 — lone machine P0
        - **P0** · 🤖 · → `03_05`
      MD
      # owner + blocked roles have zero items → empty-state without a P2/P3 tail
      expect(sparse).to include('(жодного відкритого P0/P1)_')
    end
  end

  describe "guard branches (absent / malformed canon)" do
    it ".dangling_refs skips an item whose canon has no NN_NN prefix" do
      items = [ described_class::Item.new(id: "X.1", canon: "not-a-doc-id") ]
      expect(described_class.dangling_refs(items)).to be_empty
    end

    it ".section_dangling_refs skips a canon-less item and one with an unknown doc-id" do
      items = [
        described_class::Item.new(id: "X.2", canon: nil),
        described_class::Item.new(id: "X.3", canon: "99_99 §3")
      ]
      expect(described_class.section_dangling_refs(items)).to be_empty
    end

    it ".section_home_violations skips items without canon or without a module prefix" do
      items = [
        described_class::Item.new(id: "X.4", canon: nil, section_modules: [ "05" ]),
        described_class::Item.new(id: "X.5", canon: "no-module", section_modules: [ "05" ])
      ]
      expect(described_class.section_home_violations(items)).to be_empty
    end

    it ".inbound_ref_violations returns [] when the tracker file is absent" do
      expect(described_class.inbound_ref_violations("/no/such/tracker/dir")).to eq([])
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
