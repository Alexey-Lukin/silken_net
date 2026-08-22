# SPDX-License-Identifier: AGPL-3.0-or-later
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
      - **P1** · 🤖+👤 · 🟡 · → `03_05 §3.2`
      - детальний контекст
      #### FW.98 — malformed (no meta-line)
      - просто текст без пріоритету/виконавця/канону
      #### HW.99 — dangling canon ref
      - **P2** · 👤 · 🔗 · → `99_99 §1`
      ## 🗄️ Архів закритих пунктів
      #### FW.97 — archived, must be skipped
      - **P0** · 🤖 · 🟢 · → `03_05`
    MD
  end

  let(:items) { described_class.parse(markdown) }

  it "parses #### items from §/🔀 registry sections only (skips Мета + Архів)" do
    expect(items.map(&:id)).to contain_exactly("FW.99", "FW.98", "HW.99")
  end

  it "reads priority, WHO (executor), STAGE and canon-ref from the meta-line [DOC-T.18]" do
    fw99 = items.find { |it| it.id == "FW.99" }
    expect(fw99.priority).to eq("P1")
    expect(fw99.executors).to contain_exactly(:machine, :owner)  # WHO axis (🤖+👤)
    expect(fw99.stage).to eq(:in_progress)                       # STAGE axis (🟡), separate
    expect(fw99.canon).to eq("03_05 §3.2")
  end

  # [DOC-T.34 ②] ⚫ = vacuous STAGE («нема-що-завершувати») — the parser must
  # distinguish a vacuous item from an active one AND from a malformed meta-line.
  it "reads ⚫ as the :vacuous stage and passes conformance + meta-form" do
    md = <<~MD
      ## §03 · Firmware
      #### E.90 — premise refuted, nothing to complete
      - **P3** · 🤖 · ⚫ · → `03_01`
      - **Стан:** vacuous (premise dead).
      - [ ] 🌿 переоцінити лише при wire-rev3
    MD
    item = described_class.parse(md).first
    expect(item.stage).to eq(:vacuous)
    expect(described_class.issues([ item ])).to be_empty
    expect(described_class.meta_form_violations(md)).to be_empty
  end

  # [DOC-T.33] ⚖️ is a first-class executor (:decider) — an item whose only open
  # work is a verdict must not trip the "missing executor" conformance gap.
  it "reads a solo ⚖️ meta-line WHO as the :decider executor" do
    md = <<~MD
      ## §03 · Firmware
      #### FW.94 — decision-only item
      - **P3** · ⚖️ · ⚪ · → `03_01`
      - **Стан:** verdict pending.
      - [ ] ⚖️ доля осі
    MD
    item = described_class.parse(md).first
    expect(item.executors).to contain_exactly(:decider)
    expect(described_class.issues([ item ])).to be_empty
  end

  # [HW light-touch items] `.parse` also picks up executors from unchecked
  # checkbox bullets (`- [ ] 🤖 …`), not just the `**P?**` meta-line.
  describe ".parse — checkbox-bullet executor pickup" do
    it "picks up an executor emoji from an unchecked checkbox bullet" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.50 — light-touch item
        - **P2** · 👤 · 🟡 · → `03_01`
        - [ ] 🤖 also needs a machine pass
      MD
      item = described_class.parse(md).first
      expect(item.executors).to contain_exactly(:owner, :machine)
    end

    it "ignores a checkbox bullet that carries no recognized executor emoji" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.51 — light-touch item
        - **P2** · 👤 · 🟡 · → `03_01`
        - [ ] plain follow-up, no executor marker
      MD
      item = described_class.parse(md).first
      expect(item.executors).to contain_exactly(:owner)
    end
  end

  it "flags a malformed item missing priority/executor/stage/canon (#3 conformance)" do
    expect(described_class.issues(items))
      .to include(a_string_matching(/FW\.98: missing priority, executor, stage, canon-ref/))
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
      expect(described_class.file_section_dangling_refs("| E.99 | x | `05_05` §9.9 (партнер) | y |"))
        .to include(a_string_matching(%r{05_05 §9\.9}))
    end

    it "does not flag a valid bare §-ref" do
      expect(described_class.file_section_dangling_refs("| E.99 | x | `07_03` §1.1 | y |")).to be_empty
    end

    it "is boundary-aware: §3.1 does NOT resolve against a 1.3.1 heading" do
      # 03_01 has §1.3.1 but no §3.1 — the retired substring `include?` would false-pass.
      expect(described_class.file_section_dangling_refs("ref `03_01 §3.1` here"))
        .to include(a_string_matching(%r{03_01 §3\.1}))
    end

    it "resolves a parent-group ref whose children exist (§4а ⇐ 4а.1..4а.5)" do
      expect(described_class.file_section_dangling_refs("[`05_02 §4а`](05_02_Proof_of_Growth_Pipeline)")).to be_empty
    end

    it "skips a lowercase '.x' wildcard placeholder, resolves a real section" do
      expect(described_class.file_section_dangling_refs("`03_03 §10.x` + `03_03 §3.4`")).to be_empty
    end

    it "resolves EVERY member of a comma/backtick-joined §-list under one doc-id" do
      # The run used to stop at the comma / closing backtick → the trailing ref went
      # unchecked (a multi-member list under ONE doc-id). All four below are real sections.
      expect(described_class.file_section_dangling_refs("see `03_05 §3.6`, §3.7 and 06_07 §1, §3")).to be_empty
    end

    it "flags a STALE trailing ref in a comma-joined list (not just the first)" do
      expect(described_class.file_section_dangling_refs("06_07 §1, §9 here"))
        .to include(a_string_matching(%r{06_07 §9}))
    end

    it "does NOT sweep a §X separated from the doc-id by intervening prose" do
      # only separator chars join consecutive § tokens; a word ("плюс") ends the run,
      # so the stale §9 is never (mis)attributed to 06_07 and falsely flagged.
      expect(described_class.file_section_dangling_refs("06_07 §1 плюс §9")).to be_empty
    end

    # [DOC-T.68 фаза 0] This example used to assert the OPPOSITE — a §-ref to a doc-id with
    # no file was skipped, "because resolving existence is `dangling_refs`'s job". That
    # division of labour was honest while this resolver ran over 00_07 alone: `dangling_refs`
    # reads `it.canon` — a tracker item's META line — and never prose, code or `.claude`.
    # Handing the resolver to four consumers retired the premise without retiring the clause,
    # and for a bare `NN_NN §X` in a code comment NOTHING else answers existence
    # (`external_doc_path` matches `docs/NN_NN_Name` PATHS only). So a dissolved doc took its
    # §-refs out of supervision in silence — which is the one thing a restructure must be
    # able to measure.
    it "flags a §-ref whose doc-id has no file at all" do
      expect(described_class.file_section_dangling_refs("ref `99_99 §1` here"))
        .to contain_exactly(a_string_matching(%r{99_99 §1.*no docs/}))
    end

    it "flags EVERY member of a comma-run under a dead doc-id, not just the first" do
      expect(described_class.file_section_dangling_refs("`08_02 §1.1`, §1.8"))
        .to contain_exactly(a_string_matching(/§1\.1/), a_string_matching(/§1\.8/))
    end

    # [DOC-T.60] letter-LABEL sections. The resolver used to be digit-led, which exempted
    # every letter-led doc wholesale — 04_06 is entirely `§A.x`/`§B.x`, so the whole testing
    # canon was unchecked in code and in `.claude/**` (planted `04_06 §A.999` → EXIT 0).
    it "flags a DEAD letter-label §-ref (the DOC-T.60 blind spot)" do
      expect(described_class.file_section_dangling_refs("skill says `04_06 §A.999`"))
        .to include(a_string_matching(%r{04_06 §A\.999}))
    end

    # ⚠️ This one is VACUOUS against the pre-DOC-T.60 code by construction (the old regex saw
    # nothing, so `be_empty` held for the wrong reason) — it guards the OTHER direction from
    # here on: narrowing the token, or widening `heading_anchors` wrongly, turns it red. The
    # flip itself is proved by the DEAD-ref example above.
    it "resolves LIVE letter-label §-refs (04_06 §A.x/§B.x, 05_02 §E.60)" do
      expect(described_class.file_section_dangling_refs("`04_06 §A.2` + `04_06 §B.1.4` + `05_02 §E.60`")).to be_empty
    end

    # The discriminator is the LABEL SHAPE (one letter + `.` + digit), NOT the `NN_NN`
    # prefix: these all carry the prefix and must stay OUT of scope — prose-shorthand named
    # refs and placeholders live on the weaker `section_label_drift` ADVISORY (00_06 §3).
    it "still ignores NAMED / placeholder / non-section §-refs that DO carry a doc-id" do
      named = "`05_02 §Модель` `05_04 §Merkle` `03_04 §X.Y` `00_07 §NN` `07_01 §B-02` `03_05 §FW.2`"
      expect(described_class.file_section_dangling_refs(named)).to be_empty
    end
  end

  describe ".heading_anchors" do
    it "extracts leading heading numbers, skipping letter-led (Стаття N) headings" do
      expect(described_class.heading_anchors("## 🎓 1B. ФОТІУС\n### 2.1.3. Foo\n### Стаття 1: Bar\n## 🎯 Мета"))
        .to contain_exactly("1b", "2.1.3")
    end

    it "emits parent-qualified anchors for single-letter subsections (Latin + Cyrillic)" do
      # "### A." under "## 5." → "5.a"; "### Б." (Cyrillic) → "5.б" — a precise
      # `§5.A` / `§4.А` ref resolves to the real subsection (03_06 §5.A-D, 02_03 §4.А-Д).
      expect(described_class.heading_anchors("## 5. Ops\n### A. Access\n### Б. Бета"))
        .to contain_exactly("5", "5.a", "5.б")
    end

    it "parents a letter-subsection to the NEAREST numbered ancestor (deeper nesting)" do
      expect(described_class.heading_anchors("## 4. Lock\n### 4.3. Sub\n#### A. Barb"))
        .to contain_exactly("4", "4.3", "4.3.a")
    end

    it "ignores a single-letter subsection that has no numbered parent" do
      expect(described_class.heading_anchors("## Мета\n### A. Orphan")).to be_empty
    end

    # [DOC-T.60] the REF side alone was not enough: 04_06's headings are letter-led too
    # ("## A.4 Assertions"), so without this every real `04_06 §A.2` would read as dangling.
    it "extracts leading single-letter LABEL anchors (A.4 / B.1.1 / E.60)" do
      expect(described_class.heading_anchors("## A.4 Assertions\n### B.1.1 Firmware\n### 🔬 E.60 — Merkle"))
        .to contain_exactly("a.4", "b.1.1", "e.60")
    end

    it "still skips a WORD-led heading (no digit after the letter)" do
      expect(described_class.heading_anchors("## Модель довіри\n## Стаття 1: Bar")).to be_empty
    end
  end

  # [dup-guard blind-spot fix, 2026-06-01] An ID used as BOTH a table row AND a ####
  # heading (the DOC.12 ↔ DOC.13 collision) escaped the heading-only tally. The class
  # is now carried by `all_item_ids`, which merges both shapes across EVERY section —
  # the section-filtered `table_row_ids` went with the 🔀 registry section it served
  # (2026-08-09), so these pin the surviving carrier, not the retired one.
  describe "table-row ↔ #### heading ID collision" do
    let(:md) do
      <<~MD
        ## §00 · Process
        #### DOC.12 — item that collides with the archive row below
        - **P2** · 🤖 · ⚪ · → `00_06 §3`
        ## 🗄️ Архів закритих пунктів
        | ID | Пункт | Канон |
        |----|-------|-------|
        | DOC.12 | archived under an ID still used by a live heading | `00_06 §3` |
        | DOC.10 | ordinary archived row | `00_06 §3` |
      MD
    end

    it "catches an ID reused across a heading and a table row" do
      expect(described_class.duplicate_ids(md)).to eq("DOC.12" => 2)
    end

    it "collects table-row IDs from NON-registry sections too (archive is where rows live now)" do
      expect(described_class.all_item_ids(md)).to include("DOC.10")
    end

    it "reads a first-cell ID behind a leading ✅/emoji status prefix" do
      md = "## 🗄️ Архів\n| ✅ OPS.5 | done | — |\n| 🌿 E.59 | finding | — |\n"
      expect(described_class.all_item_ids(md)).to contain_exactly("OPS.5", "E.59")
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
        - **P1** · 👤 · → `02_06 §8.1.1`
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

    it "captures the no-dash dialect too (DOC-T.42 ③ — the form nothing covered)" do
      expect("[`00_07` DOC.5](00_07_Action_Plan_Tracker)".scan(described_class::INBOUND_REF_RE).flatten)
        .to eq([ "DOC.5" ])
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

  describe ".item_body_text" do
    it "keeps #### item bodies but drops table-rows outside them (the necrology trap, DOC-T.42 ①)" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.1 — live item
        - **Стан:** declared facet FW.1-S2 lives here.

        ## 🗄️ Архів
        | ID | Пункт |
        | DOC-T.9 | retired the FW.9-DEAD sub-ID (obituary) |
      MD
      body = described_class.item_body_text(md)
      expect(body).to include("FW.1-S2")
      expect(body).not_to include("FW.9-DEAD")
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

    it "skips a line that isn't a CHEM-bearing bullet at all (blank line, plain prose)" do
      md = <<~MD

        just prose, no bullet or CHEM token here
        - [ ] CHEM.30 — a real def, so the skip above isn't vacuous
      MD
      expect(described_class.chem_note_ids(md)).to eq(%w[CHEM.30])
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

    it "skips a non-checkbox line entirely (heading, prose) even if it mentions CHEM" do
      md = <<~MD
        ## §01 · In-silico (mentions CHEM.9 in a heading, not a checkbox bullet)
        prose line about CHEM.9, still not a checkbox
        - [x] CHEM.9 — the real, unambiguous em-dash def
      MD
      expect(described_class.chem_ambiguous_token_lines(md)).to be_empty
    end
  end
  end

  # [emoji-prefix blind spot, 2026-06-01] `#### 🌿 UNI.13a — …` was silently dropped
  # by the `[A-Z]`-anchored match, hiding UNI.13a / BIZ.12 from every tracker check.
  it "parses a #### item behind a leading emoji prefix" do
    md = <<~MD
      ## §07a · Академічна інтеграція
      #### 🌿 UNI.13a — emoji-prefixed item
      - **P1** · 👤 · → `07_03 §2.2`
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

  # [DOC-T.49] pre-section orphan guard — an item outside every registry section is
  # invisible to `parse`, so EVERY other tracker gate iterates a set that silently
  # lacks it and stays green on a corrupted file.
  describe ".orphan_item_violations" do
    let(:md) do
      <<~MD
        # 00_07: Action Plan Tracker

        ## §06 · Deploy
        #### S1.1 — visible, inside a registry section
        - **P0** · 👤 · ⚪ · → `06_04`
        ## §04 · Backend
        #### DOC.9 — visible, a second §-section is a registry section too
        - **P2** · 🤖 · ⚪ · → `04_02`
      MD
    end

    it "passes when every #### item sits inside a registry section" do
      expect(described_class.orphan_item_violations(md)).to be_empty
    end

    # The real defect: a glued H1 left DOC-T.48 stranded above the first section —
    # 225 of 226 items parsed and every gate reported green.
    it "flags an item stranded ABOVE the first section" do
      stranded = md.sub("## §06 · Deploy\n", "#### DOC-T.48 — orphan above every section\n- **P3** · 🤖 · ⚪ · → `00_06 §3`\n## §06 · Deploy\n")
      expect(described_class.orphan_item_violations(stranded))
        .to contain_exactly(a_string_matching(/DOC-T\.48.*invisible/))
    end

    it "flags an item buried under a SKIP section (🎯/🚦/📌/🗄️)" do
      buried = "#{md}## 🗄️ Архів\n#### GHOST.1 — under a skipped section\n- **P3** · 🤖 · ⚪ · → `00_06 §3`\n"
      expect(described_class.orphan_item_violations(buried))
        .to contain_exactly(a_string_matching(/GHOST\.1.*invisible/))
    end

    it "ignores a #### heading inside a fenced code block" do
      fenced = "#{md}## §06 · Deploy\n```\n#### FAKE.1 — example inside a fence\n```\n"
      expect(described_class.orphan_item_violations(fenced)).to be_empty
    end

    it "holds the live tracker at zero" do
      expect(described_class.orphan_item_violations).to be_empty
    end
  end

  # [inline residual run-on guard, founder 2026-06-14] residuals must be a VERTICAL list;
  # ≥2 inline `· [ ]` on one body line is flagged (00_07 intro standard). Skips intro
  # blockquote examples, fenced code, and table rows.
  describe ".inline_residual_runon" do
    it "flags a body line packing ≥2 inline checkboxes, passes a vertical list" do
      md = <<~MD
        ## §06 · Ops
        #### S9.1 — run-on residuals
        - **P1** · 👤 · 🟡 · → `06_04`
        - ✅ done. · [ ] 👤 first · [ ] 🤖 second
        #### S9.2 — clean vertical
        - **P1** · 👤 · 🟡 · → `06_04`
        - **Стан:** done.
        - [ ] 👤 first
        - [ ] 🤖 second
      MD
      res = described_class.inline_residual_runon(md)
      expect(res).to include(a_string_matching(/S9\.1/))
      expect(res).not_to include(a_string_matching(/S9\.2/))
    end

    it "skips a blockquote example line and a fenced code block (no false positive)" do
      md = <<~MD
        ## §06 · Ops
        #### S9.3 — blockquote + fenced examples then a lone residual
        - **P1** · 👤 · 🟡 · → `06_04`
        > приклад у цитаті: `[ ]` done · `[ ]` again
        ```
        [ ] x · [ ] y
        ```
        - [ ] 👤 lone residual
      MD
      expect(described_class.inline_residual_runon(md)).to be_empty
    end
  end

  describe ".verdict_lead_violations" do
    it "flags a non-Стан lead (✅/prose), passes a `- **Стан:**` lead" do
      md = <<~MD
        ## §06 · Ops
        #### S9.4 — checkmark lead
        - **P1** · 👤 · 🟡 · → `06_04`
        - ✅ done thing. · [ ] 👤 residual
        #### S9.5 — Стан lead
        - **P1** · 👤 · 🟡 · → `06_04`
        - **Стан:** done thing.
        - [ ] 👤 residual
      MD
      res = described_class.verdict_lead_violations(md)
      expect(res).to include("S9.4")
      expect(res).not_to include("S9.5")
    end

    it "skips a line before the **P?** meta-line is even reached (not yet seen_meta)" do
      md = <<~MD
        ## §06 · Ops
        #### S9.11 — intervening line before the meta-line
        some stray line that is not the **P?** meta-line yet
        - **P1** · 👤 · 🟡 · → `06_04`
        - **Стан:** verdict leads correctly after the real meta-line.
      MD
      expect(described_class.verdict_lead_violations(md)).to be_empty
    end

    it "checks ONLY the first body line (a later non-Стан line passes)" do
      md = <<~MD
        ## §06 · Ops
        #### S9.6 — Стан lead then prose
        - **P1** · 👤 · 🟡 · → `06_04`
        - **Стан:** verdict here.
        - some follow-up prose, not a Стан line
        - [ ] 👤 residual
      MD
      expect(described_class.verdict_lead_violations(md)).to be_empty
    end

    it "skips non-registry sections (📌 Backlog / 🗄️ Архів)" do
      md = <<~MD
        ## 📌 Backlog · Findings
        #### B9.1 — backlog item without Стан lead
        - **P3** · 🤖 · ⚪ · → `06_04`
        - prose lead, no Стан
      MD
      expect(described_class.verdict_lead_violations(md)).to be_empty
    end
  end

  # [DOC-T.63] The Стан-lead opens with the SUBSTANCE, never with the division of labour.
  # Founder banned the mantra 2026-07-05; it returned the same day and seven more times
  # (three English, five Ukrainian) — a prose rule with no carrier. Both branches of the
  # discriminator are pinned positively: a mid-sentence «machine-half» must stay legal.
  describe ".labour_split_lead" do
    def item(lead)
      <<~MD
        ## §05 · Web3
        #### X9.1 — sample
        - **P1** · 🤖 · 🟢 · → `05_02`
        - **Стан:** #{lead}
      MD
    end

    it "flags the mantra in BOTH languages and in every inflection that shipped" do
      [ "Machine-half ✅ SHIPPED — суть далі.",
       "machine half закрито — суть далі.",
       "Машинна половина ЗАКРИТА — суть далі.",
       "Машинну частину зацементовано — суть далі.",
       "Вичерпано — суть далі." ].each do |lead|
        expect(described_class.labour_split_lead(item(lead)).size).to eq(1), "missed: #{lead}"
      end
    end

    it "sees through a decorative prefix (the ornament is not an escape hatch)" do
      expect(described_class.labour_split_lead(item("✅ **Machine-half SHIPPED** — суть."))).not_to be_empty
    end

    it "passes a lead that opens with the SUBSTANCE and merely mentions machine-half later" do
      expect(described_class.labour_split_lead(item("Mint-volume circuit-breaker ✅ SHIPPED; machine-half тут згадана легітимно."))).to be_empty
    end

    it "passes a subject that merely starts with «Машина» (no половина/частина follows)" do
      expect(described_class.labour_split_lead(item("Машина стану AASM переведена на after_update_commit."))).to be_empty
    end

    it "checks ONLY the lead — the mantra on a later body line is prose, not a lead" do
      md = <<~MD
        ## §05 · Web3
        #### X9.2 — sample
        - **P1** · 🤖 · 🟢 · → `05_02`
        - **Стан:** Reserve-gate ✅ SHIPPED — суть.
        - Machine-half ✅ — а це вже не лід.
      MD
      expect(described_class.labour_split_lead(md)).to be_empty
    end

    it "skips non-registry sections, like every other lead rule" do
      md = <<~MD
        ## 🗄️ Архів
        #### Z9.1 — archived
        - **P3** · 🤖 · 🟢 · → `05_02`
        - **Стан:** Machine-half ✅ SHIPPED.
      MD
      expect(described_class.labour_split_lead(md)).to be_empty
    end

    it "the LIVE tracker is at zero — the sweep and the gate shipped together" do
      expect(described_class.labour_split_lead).to be_empty
    end
  end

  # [DOC-T.34 ①] `[bench:slug]` tags ⇆ RUNBOOK §6 session registry, two-way.
  # The registry row is anchored by the tag itself (`| [bench:slug] | … | IDs |`)
  # so the RUNBOOK's other tables (tool names in code-spans) can't false-match.
  describe ".bench_tag_violations" do
    let(:runbook) do
      <<~MD
        | Інструмент | Для чого | Нотатка |
        |---|---|---|
        | `pyocd` (`pip install pyocd`) | SWD-оркестрація | not a session row |

        | Сеанс | Секції RUNBOOK | 00_07-items |
        |---|---|---|
        | [bench:flash-kv] | §6 | FW.2 · FW.8 |
        | [bench:coap] | §5 | FW.3 |
      MD
    end

    let(:tracker_md) do
      <<~MD
        ## §03 · Firmware
        #### FW.2 — item in session
        - **P0** · 👤 · 🟢 · → `03_05`
        - **Стан:** x.
        - [ ] 👤 bench: CCM + Flash-KV [bench:flash-kv]
        #### FW.8 — listed but NOT tagged
        - **P2** · 👤 · 🟢 · → `03_01`
        - **Стан:** x.
        - [ ] 👤 bench: фліп парсера
        #### FW.3 — tagged into the wrong session
        - **P1** · 👤 · 🟢 · → `03_02`
        - **Стан:** x.
        - [ ] 👤 bench: таймінги [bench:flash-kv]
        #### FW.9 — tag with an unregistered slug
        - **P2** · 👤 · 🟢 · → `03_01`
        - **Стан:** x.
        - [ ] 👤 bench: щось [bench:phantom-day]
      MD
    end

    it "flags both asymmetry directions + an unknown slug; the tool table never matches" do
      res = described_class.bench_tag_violations(tracker_md, runbook)
      expect(res).to contain_exactly(
        a_string_matching(/FW\.3: \[bench:flash-kv\] — item not in that session/),
        a_string_matching(/FW\.9: \[bench:phantom-day\] — no such session/),
        a_string_matching(/RUNBOOK §6 \[bench:flash-kv\]: FW\.8 carries no tag/),
        a_string_matching(/RUNBOOK §6 \[bench:coap\]: FW\.3 carries no tag/)
      )
      expect(described_class.bench_sessions(runbook).keys).to contain_exactly("flash-kv", "coap")
    end

    it "does not leak a tag mentioned AFTER a ## header onto the previous item" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.2 — real item
        - **P0** · 👤 · 🟢 · → `03_05`
        - [ ] 👤 bench: x [bench:flash-kv]
        ## 🔀 Cross-cutting
        | DOC-T.99 | опис задачі згадує [bench:flash-kv] як приклад | `00_06 §3` |
      MD
      rb = "| [bench:flash-kv] | §6 | FW.2 |\n"
      expect(described_class.bench_tag_violations(md, rb)).to be_empty
    end

    it "reads tags ONLY from checkbox rows — a fenced grep-example or prose mention must not satisfy the registry leg" do
      # the review-proven false-green: item listed in the registry, checkbox
      # untagged, but a fenced/prose [bench:…] in the body used to count as tagged
      md = <<~MD
        ## §03 · Firmware
        #### FW.2 — untagged checkbox with a fenced example
        - **P0** · 👤 · 🟢 · → `03_05`
        - **Стан:** приклад у прозі [bench:flash-kv] не рахується.
        ```
        grep '[bench:flash-kv]' docs/00_07_*
        ```
        - [ ] 👤 bench: чекбокс БЕЗ тега
      MD
      rb = "| [bench:flash-kv] | §6 | FW.2 |\n"
      expect(described_class.bench_tag_violations(md, rb))
        .to contain_exactly(a_string_matching(/FW\.2 carries no tag/))
    end

    it "expands a slash-family in a registry row into each member" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.8 — tagged member one
        - **P2** · 👤 · 🟢 · → `03_01`
        - [ ] 👤 bench: x [bench:flash-kv]
        #### FW.20 — member two, NOT tagged
        - **P2** · 👤 · 🟢 · → `03_02`
        - [ ] 👤 bench: y
      MD
      rb = "| [bench:flash-kv] | §6 | FW.8/20 |\n"
      expect(described_class.bench_tag_violations(md, rb))
        .to contain_exactly(a_string_matching(/FW\.20 carries no tag/))
    end

    it "reports one honest violation when the RUNBOOK registry is missing but tags exist" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.2 — tagged item
        - **P0** · 👤 · 🟢 · → `03_05`
        - [ ] 👤 bench: x [bench:flash-kv]
      MD
      expect(described_class.bench_tag_violations(md, nil))
        .to contain_exactly(a_string_matching(/registry not found/))
      expect(described_class.bench_tag_violations("## §03 · Firmware\n", nil)).to be_empty
    end

    it "passes a fully symmetric registry ⇆ tag set (incl. a two-session item)" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.2 — item in session
        - **P0** · 👤 · 🟢 · → `03_05`
        - **Стан:** x.
        - [ ] 👤 bench: CCM + Flash-KV [bench:flash-kv]
        #### FW.8 — two sessions, two tags
        - **P2** · 👤 · 🟢 · → `03_01`
        - **Стан:** x.
        - [ ] 👤 bench: фліп [bench:flash-kv]
        - [ ] 👤 bench: інший день [bench:coap]
      MD
      rb = <<~MD
        | [bench:flash-kv] | §6 | FW.2 · FW.8 |
        | [bench:coap] | §5 | FW.8 |
      MD
      expect(described_class.bench_tag_violations(md, rb)).to be_empty
    end
  end

  # [DOC-T.34 ③] `[кластер:slug:дім|важіль]` on item headings — one greppable form
  # for координатор ⊃ важелі. Symmetry: exactly ONE дім + ≥1 важіль per slug.
  describe ".cluster_marker_violations" do
    it "passes a symmetric cluster (one дім, two важелі) and ignores [поглинув …]" do
      md = <<~MD
        ## §03 · Firmware
        #### ARCH.80 — coordinator [кластер:tx-test:дім]
        - **P3** · 🤖 · 🌿 · → `03_01`
        #### E.80 — lever one [кластер:tx-test:важіль]
        - **P3** · 👤 · 🌿 · → `03_01`
        #### E.81 — lever two [кластер:tx-test:важіль] [поглинув E.82 2026-07-01]
        - **P3** · 👤 · 🌿 · → `03_01`
      MD
      expect(described_class.cluster_marker_violations(md)).to be_empty
    end

    it "flags a дім without важелі, a second дім, and a важіль-only slug" do
      md = <<~MD
        ## §03 · Firmware
        #### ARCH.80 — lonely coordinator [кластер:solo:дім]
        - **P3** · 🤖 · 🌿 · → `03_01`
        #### ARCH.81 — first дім [кластер:twin:дім]
        - **P3** · 🤖 · 🌿 · → `03_01`
        #### ARCH.82 — second дім [кластер:twin:дім]
        - **P3** · 🤖 · 🌿 · → `03_01`
        #### E.83 — twin lever [кластер:twin:важіль]
        - **P3** · 👤 · 🌿 · → `03_01`
        #### E.84 — orphan lever [кластер:orphan:важіль]
        - **P3** · 👤 · 🌿 · → `03_01`
      MD
      res = described_class.cluster_marker_violations(md)
      expect(res).to contain_exactly(
        a_string_matching(/кластер:solo: no важіль/),
        a_string_matching(/кластер:twin: 2 дім-markers/),
        a_string_matching(/кластер:orphan: 0 дім-markers/)
      )
    end

    it "flags a malformed [кластер:…] tail (bad role word) on a heading" do
      md = <<~MD
        ## §03 · Firmware
        #### ARCH.85 — bad role [кластер:x:coordinator]
        - **P3** · 🤖 · 🌿 · → `03_01`
      MD
      expect(described_class.cluster_marker_violations(md))
        .to contain_exactly(a_string_matching(/ARCH\.85: malformed/))
    end
  end

  describe ".meta_form_violations" do
    it "flags a non-canonical WHO combo, passes 🤖+👤 / 🤖 / 👤" do
      md = <<~MD
        ## §06 · Ops
        #### S9.7 — bad WHO order
        - **P1** · 👤+🤖 · 🟡 · → `06_04`
        - **Стан:** x.
        #### S9.8 — canonical combo
        - **P1** · 🤖+👤 · 🟡 · → `06_04`
        - **Стан:** x.
      MD
      res = described_class.meta_form_violations(md)
      expect(res).to include(a_string_matching(/S9\.7/))
      expect(res).not_to include(a_string_matching(/S9\.8/))
    end

    # [DOC-T.33 phase 2] ⚖️ (decision-residual, 👤-subtype) is a legal meta-line WHO —
    # solo or TRAILING in a combo; a decider never leads (⚖️+👤 stays non-canonical).
    it "passes ⚖️ solo and trailing combos (🤖+⚖️ / 👤+⚖️), flags a leading ⚖️+👤" do
      md = <<~MD
        ## §03 · Firmware
        #### FW.90 — pure decision residual
        - **P3** · ⚖️ · ⚪ · → `03_01`
        - **Стан:** x.
        #### FW.91 — machine work gated on a verdict
        - **P3** · 🤖+⚖️ · ⚪ · → `03_01`
        - **Стан:** x.
        #### FW.92 — hands + verdict
        - **P3** · 👤+⚖️ · ⚪ · → `03_01`
        - **Стан:** x.
        #### FW.93 — decider must not lead
        - **P3** · ⚖️+👤 · ⚪ · → `03_01`
        - **Стан:** x.
      MD
      res = described_class.meta_form_violations(md)
      expect(res).to contain_exactly(a_string_matching(/FW\.93/))
    end

    it "flags a tail after the canon-ref, passes a clean multi-ref (comma, not ·)" do
      md = <<~MD
        ## §06 · Ops
        #### S9.9 — meta tail
        - **P1** · 👤 · ⚪ · → `06_04` · ✅ done extra
        - **Стан:** x.
        #### S9.10 — clean multi-ref
        - **P1** · 👤 · 🟢 · → `02_01 §3.4`, `02_06 §1.3`
        - **Стан:** x.
      MD
      res = described_class.meta_form_violations(md)
      expect(res).to include(a_string_matching(/S9\.9/))
      expect(res).not_to include(a_string_matching(/S9\.10/))
    end

    it "skips non-registry sections (📌 Backlog / 🗄️ Архів)" do
      md = <<~MD
        ## 📌 Backlog · Findings
        #### B9.2 — backlog with odd WHO
        - **P3** · 👤/🤖 · ⚪ · → `06_04`
      MD
      expect(described_class.meta_form_violations(md)).to be_empty
    end

    it "skips a line before the **P?** meta-line is reached (not yet seen_meta)" do
      md = <<~MD
        ## §06 · Ops
        #### S9.12 — intervening line before the meta-line
        a stray non-meta line first
        - **P1** · 👤 · 🟡 · → `06_04`
      MD
      expect(described_class.meta_form_violations(md)).to be_empty
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

    it ".inbound_prose_ref_violations returns [] when the tracker file is absent" do
      expect(described_class.inbound_prose_ref_violations("/no/such/tracker/dir")).to eq([])
    end

    it ".chem_note_ref_violations returns [] when the tracker file is absent" do
      expect(described_class.chem_note_ref_violations("/no/such/tracker/dir")).to eq([])
    end
  end

  # Parsing state-machine edges of the verdict-lead / meta-form guards that the
  # happy-path fixtures don't reach — each is a real drift shape the linter must survive.
  describe "guard parser edges" do
    it ".verdict_lead_violations tolerates a blank line after the meta and a later fenced block" do
      md = <<~MD
        ## §05 Ledger
        #### E.1 — item
        - **P1** · 🤖 · 🟡 · → 05_01

        - **Стан:** verdict leads correctly
        ```ruby
        example
        ```
      MD
      # Blank-after-meta exercises the empty-skip; the fence toggles in-fence AFTER current is
      # cleared. Стан leads → clean.
      expect(described_class.verdict_lead_violations(md)).to be_empty
    end

    it ".meta_form_violations flags a meta-line that does not match the canonical form" do
      md = <<~MD
        ## §05 Ledger
        #### E.2 — item
        - **P0** malformed meta without the dot-separated canon shape
      MD
      expect(described_class.meta_form_violations(md)).to include(a_string_matching(/E\.2: malformed meta-line/))
    end
  end

  describe ".stale_who" do
    # meta-line WHO = UNION of OPEN residuals (00_07 intro), so a shipped half must drop
    # its glyph. meta_form_violations checks only the token's SHAPE — this guard checks it
    # still MATCHES the checkboxes. [DOC-T.52; widened to all three glyphs + the empty set
    # by DOC-T.55, which is why every glyph below gets its own positive example: a check
    # covering ONE member of an enum reads, from its green run, exactly like one covering
    # all of them.]
    let(:md) do
      <<~MD
        ## §07 · Бізнес
        #### BIZ.1 — machine half shipped, meta still advertises 🤖
        - **P1** · 🤖+👤 · 🟡 · → `07_01 §8`
        - **Стан:** артефакт написано, лишився юрист.
        - [ ] 👤 юр-review
        #### BIZ.2 — meta 🤖 backed by a live 🤖 residual
        - **P1** · 🤖+👤 · 🟡 · → `07_01 §8`
        - **Стан:** x.
        - [ ] 👤 зустріч
        - [ ] 🤖 написати скрипт
        #### BIZ.3 — 🔗-led residual: delegated, eventual WHO lives elsewhere
        - **P2** · 🤖 · 🔗 · → `07_01 §8`
        - **Стан:** x.
        - [ ] 🔗 gated на SEC.1 — Vote-Escrow
        #### BIZ.4 — residual with NO explicit WHO (🌿-led): WHO undeclared, not "done"
        - **P3** · 🤖+👤 · 🌿 · → `07_01 §8`
        - **Стан:** x.
        - [ ] 🌿 far-horizon rewrite (post-TRL 8)
        #### BIZ.5 — no 🤖 in meta at all
        - **P3** · 👤 · ⚪ · → `07_01 §8`
        - **Стан:** x.
        - [ ] 👤 зустріч
      MD
    end
    # --- the other two glyphs [DOC-T.55] -------------------------------------------
    # The first cut read `include?("🤖")`, so a meta advertising a ⚖️ verdict nobody awaits
    # — the costliest executor to summon — passed green forever. One positive example per
    # glyph, because the corpus population for any single one can (and does) shrink to zero.
    let(:glyphs) do
      <<~MD
        ## §04 · Backend
        #### ARCH.80 — meta ⚖️ over a body with no open ⚖️ residual
        - **P3** · 🤖+⚖️ · ⚪ · → `04_01 §10`
        - **Стан:** присуд ратифіковано, лишилась машинна нога.
        - [ ] 🤖 дописати каскад
        #### ARCH.81 — meta 👤 over a body with no open 👤 residual
        - **P3** · 🤖+👤 · 🟡 · → `04_01 §10`
        - **Стан:** руки відпрацювали, лишився скрипт.
        - [ ] 🤖 дописати скрипт
      MD
    end

    def ids(result) = result.map { |v| v.split(":").first }


    it "flags ONLY the item whose meta 🤖 no open residual backs" do
      expect(ids(described_class.stale_who(md))).to eq([ "BIZ.1" ])
    end

    it "names the glyph the meta-line overstates" do
      expect(described_class.stale_who(md).first).to include("claims 🤖")
    end

    it "exempts a 🔗-led residual — its eventual WHO lives in the item it is gated on" do
      expect(ids(described_class.stale_who(md))).not_to include("BIZ.3")
    end

    it "exempts a residual with no WHO glyph — undeclared ≠ that half is done" do
      expect(ids(described_class.stale_who(md))).not_to include("BIZ.4")
    end

    it "ignores an item with a closed 🤖 residual only, since [x] is not open work" do
      done_only = <<~MD
        ## §07 · Бізнес
        #### BIZ.9 — 🤖 residual already checked off
        - **P1** · 🤖+👤 · 🟡 · → `07_01 §8`
        - **Стан:** x.
        - [x] 🤖 скрипт написано
        - [ ] 👤 юр-review
      MD
      expect(ids(described_class.stale_who(done_only))).to eq([ "BIZ.9" ])
    end

    it "never reads the intro blockquote's example lines as real items" do
      intro = <<~MD
        > **Форма пункту:** `- [ ] 🤖 …` — приклад у преамбулі, не справжній residual.

        ## §07 · Бізнес
        #### BIZ.7 — real item
        - **P1** · 🤖+👤 · 🟡 · → `07_01 §8`
        - **Стан:** x.
        - [ ] 👤 юр-review
      MD
      expect(ids(described_class.stale_who(intro))).to eq([ "BIZ.7" ])
    end


    it "flags a meta ⚖️ that no open ⚖️ residual backs — the decider axis, not just 🤖" do
      expect(described_class.stale_who(glyphs)).to include(a_string_matching(/ARCH\.80.*claims ⚖/))
    end

    it "flags a meta 👤 that no open 👤 residual backs" do
      expect(described_class.stale_who(glyphs)).to include(a_string_matching(/ARCH\.81.*claims 👤/))
    end

    it "treats an open ⚖️ residual as backing a meta 👤, since ⚖️ ⊂ 👤" do
      subset = <<~MD
        ## §04 · Backend
        #### ARCH.82 — meta 👤 over an open ⚖️ residual
        - **P2** · 👤 · ⚪ · → `04_01 §10`
        - **Стан:** x.
        - [ ] ⚖️ присуд
      MD
      expect(described_class.stale_who(subset)).to be_empty
    end

    it "does NOT treat an open 👤 residual as backing a meta ⚖️ — the subset runs one way" do
      inverted = <<~MD
        ## §04 · Backend
        #### ARCH.83 — meta ⚖️ over an open 👤 residual
        - **P2** · ⚖️ · ⚪ · → `04_01 §10`
        - **Стан:** x.
        - [ ] 👤 зустріч із юристом
      MD
      expect(described_class.stale_who(inverted)).to include(a_string_matching(/ARCH\.83.*claims ⚖/))
    end

    # --- the EMPTY SET [DOC-T.55] --------------------------------------------------
    # The first cut exited on `open.empty?`, so a finished item kept a full WHO axis over
    # nothing at all — the "a gate over an empty set is green forever" shape. The example
    # that used to sit here («stays silent on an item with no open residuals») pinned that
    # hole AS the intended behaviour, i.e. it cemented the bug rather than covering it.
    it "flags a non-empty meta WHO over ZERO open residuals — the union is empty" do
      none = <<~MD
        ## §07 · Бізнес
        #### BIZ.8 — nothing open, WHO axis still full
        - **P1** · 🤖+👤 · 🟢 · → `07_01 §8`
        - **Стан:** все закрито.
      MD
      expect(described_class.stale_who(none)).to include(a_string_matching(/BIZ\.8.*ZERO open residuals/))
    end

    it "exempts a 🌿 far-horizon item with nothing open — its WHO names a FUTURE executor" do
      far = <<~MD
        ## §07 · Бізнес
        #### BIZ.10 — far-horizon, no checkbox by construction
        - **P3** · 🤖 · 🌿 · → `07_01 §8`
        - **Стан:** post-TRL, робота ще попереду.
      MD
      expect(described_class.stale_who(far)).to be_empty
    end

    it "exempts a ⚫ vacuous item with nothing open — it stays as a closed-canon note" do
      vacuous = <<~MD
        ## §07 · Бізнес
        #### BIZ.11 — premise refuted, item kept in place as a note
        - **P3** · ⚖️ · ⚫ · → `07_01 §8`
        - **Стан:** нема-що-завершувати.
      MD
      expect(described_class.stale_who(vacuous)).to be_empty
    end

    it "does NOT exempt a 🔗 item with nothing open — a blocked item must name its trigger" do
      blocked = <<~MD
        ## §07 · Бізнес
        #### BIZ.12 — blocked, but nothing open and no trigger residual
        - **P2** · 👤 · 🔗 · → `07_01 §8`
        - **Стан:** чекає.
      MD
      expect(described_class.stale_who(blocked)).to include(a_string_matching(/BIZ\.12.*ZERO open residuals/))
    end

    it "collects items at all (positive scope proof — an empty scope reads as clean)" do
      expect(described_class.stale_who(md).size + described_class.stale_who(glyphs).size).to eq(3)
    end
  end

  describe ".understated_who" do
    # Reverse axis of .stale_who [DOC-T.54]: that guard catches meta
    # OVERSTATING (claims 🤖 nobody backs); this one catches meta UNDERSTATING — open
    # work the meta-line never declares. The meta-line IS the scan layer, so a pure-👤
    # meta over a body full of 🤖 residuals reads as "nothing here for the machine".
    let(:md) do
      <<~MD
        ## §01a · Anchor
        #### HW.1 — meta says 👤 while six machine residuals sit in the body
        - **P0** · 👤 · 🟡 · → `01_01 §1`
        - **Стан:** x.
        - [ ] 👤 фіз-друк
        - [ ] 🤖 генератор креслення
        #### HW.2 — meta already the honest union
        - **P1** · 🤖+👤 · 🟡 · → `01_01 §1`
        - **Стан:** x.
        - [ ] 👤 передати на завод
        - [ ] 🤖 дописати CEM-поле
        #### HW.3 — all three executors open: the pair 🤖+👤 satisfies the union (⚖️ ⊂ 👤)
        - **P1** · 🤖+👤 · 🟡 · → `01_01 §1`
        - **Стан:** x.
        - [ ] 👤 лаба
        - [ ] 🤖 розрахунок
        - [ ] ⚖️ присуд
        #### HW.4 — meta 👤 covers an open ⚖️ residual (⚖️ ⊂ 👤)
        - **P2** · 👤 · ⚪ · → `01_01 §1`
        - **Стан:** x.
        - [ ] ⚖️ присуд
        #### HW.5 — 🔗-led residual delegates its WHO to the gating item
        - **P2** · 👤 · 🔗 · → `01_01 §1`
        - **Стан:** x.
        - [ ] 👤 руки
        - [ ] 🔗 gated на HW.24 — машинна нога живе там
      MD
    end

    it "flags ONLY the item whose meta-line omits an executor its open residuals carry" do
      expect(described_class.understated_who(md).map { |v| v.split(":").first }).to eq([ "HW.1" ])
    end

    it "names the missing glyph and how many open residuals carry it" do
      expect(described_class.understated_who(md).first).to include("misses 🤖×1")
    end

    it "needs no three-executor exemption — {🤖,👤,⚖️} collapses onto the legal pair 🤖+👤" do
      expect(described_class.understated_who(md).join).not_to include("HW.3")
    end

    it "reads the LEADING token only — a 👤 residual citing 🤖 work in prose is not open 🤖" do
      prose = <<~MD
        ## §02a · Node
        #### HW.9 — hands-work whose text cites an already-shipped machine check
        - **P1** · 👤 · ⚪ · → `02_01 §8`
        - **Стан:** x.
        - [ ] 👤 RF Keep-Out DRC — 3D-геометрія вже 🤖-verified (`Assembly.RfClearanceMm`)
      MD
      expect(described_class.understated_who(prose)).to be_empty
    end

    it "treats a meta 👤 as covering an open ⚖️ residual, since ⚖️ ⊂ 👤" do
      expect(described_class.understated_who(md).join).not_to include("HW.4")
    end

    it "does NOT treat a meta ⚖️ as covering open 👤 hands-work — the subset runs one way" do
      inverted = <<~MD
        ## §07 · Бізнес
        #### BIZ.30 — meta ⚖️ over an open 👤 residual
        - **P1** · ⚖️ · 🟡 · → `07_01 §8`
        - **Стан:** x.
        - [ ] 👤 зустріч із юристом
      MD
      expect(described_class.understated_who(inverted).first).to include("misses 👤×1")
    end

    it "exempts a 🔗-led residual — its eventual WHO lives in the item it is gated on" do
      expect(described_class.understated_who(md).join).not_to include("HW.5")
    end

    it "collects residuals at all (positive scope proof — an empty scope reads as clean)" do
      one = <<~MD
        ## §01a · Anchor
        #### HW.9 — single undeclared machine residual
        - **P1** · 👤 · 🟡 · → `01_01 §1`
        - **Стан:** x.
        - [ ] 🤖 скрипт
      MD
      expect(described_class.understated_who(one).size).to eq(1)
    end

    it "never reads a fenced example or the intro blockquote as a real residual" do
      noise = <<~MD
        > **Форма:** `- [ ] 🤖 …` — приклад у преамбулі.

        ## §01a · Anchor
        #### HW.10 — body quotes a machine residual inside a fence
        - **P1** · 👤 · 🟡 · → `01_01 §1`
        - **Стан:** x.
        ```
        - [ ] 🤖 приклад у фенсі
        ```
        - [ ] 👤 руки
      MD
      expect(described_class.understated_who(noise)).to be_empty
    end
  end

  # [DOC-T.73] Форма порядку: всередині `## §NN` пріоритет не сміє РОСТИ згори вниз.
  # Писач (`scripts/tracker_sort.rb`) існував давно — бракувало саме читача, тож
  # дрейф був невидимий: сортування §04 знайшло 8 порушень у 5 секціях, і жоден
  # гейт не червонів.
  describe ".priority_order_violations" do
    let(:ordered) do
      <<~MD
        ## §04 · Backend
        #### A.1 — найгостріше
        - **P0** · 🤖 · ⚪ · → `04_01 §1`
        #### A.2 — так само гостре
        - **P0** · 🤖 · ⚪ · → `04_01 §1`
        #### A.3 — нижче
        - **P2** · 🤖 · ⚪ · → `04_01 §1`
      MD
    end

    it "мовчить на незростаючій послідовності (рівні P поруч — законні)" do
      expect(described_class.priority_order_violations(ordered)).to be_empty
    end

    it "ловить вищий пріоритет, що осів ПІД нижчим, і називає обидва сусіди" do
      bad = ordered.sub("#### A.3 — нижче\n- **P2**", "#### A.3 — нижче\n- **P1**")
                   .sub("#### A.2 — так само гостре\n- **P0**", "#### A.2 — так само гостре\n- **P3**")

      violations = described_class.priority_order_violations(bad)
      expect(violations.size).to eq(1)
      expect(violations.first).to include("A.3 (P1)", "A.2 (P3)", "§04")
    end

    it "рахує послідовність ОКРЕМО в кожній секції (перехід через заголовок не є порушенням)" do
      two_sections = <<~MD
        ## §04 · Backend
        #### A.1 — низький хвіст секції
        - **P3** · 🤖 · ⚪ · → `04_01 §1`
        ## §05 · Web3
        #### B.1 — новий високий старт
        - **P0** · 🤖 · ⚪ · → `05_01 §1`
      MD

      expect(described_class.priority_order_violations(two_sections)).to be_empty
    end

    it "не читає `**P?**`, процитований у ТІЛІ пункту (лише meta-рядок)" do
      quoting = <<~MD
        ## §04 · Backend
        #### A.1 — перший
        - **P1** · 🤖 · ⚪ · → `04_01 §1`
        - **Стан:** сусід колись був **P0**, і цитата не сміє зсувати послідовність.
        #### A.2 — другий
        - **P1** · 🤖 · ⚪ · → `04_01 §1`
      MD

      expect(described_class.priority_order_violations(quoting)).to be_empty
    end

    # Обидві межі скану РЕАЛЬНІ в живому трекері, тому пінимо їх, а не знімаємо:
    # інтро несе ```-блок із прикладом meta-рядка, а `## 🎯 Мета` / `## 🗄️ Архів` —
    # не-реєстрові заголовки, які мусять СКИДАТИ послідовність, а не продовжувати її.
    it "ігнорує приклади всередині code-fence і не рахує не-§ секції" do
      noisy = <<~MD
        ## 🎯 Мета
        ```
        #### X.1 — приклад із документації
        - **P0** · 🤖 · ⚪ · → `00_06 §1`
        ```
        ## §04 · Backend
        #### A.1 — перший
        - **P2** · 🤖 · ⚪ · → `04_01 §1`
        #### A.2 — другий
        - **P2** · 🤖 · ⚪ · → `04_01 §1`
        ## 🗄️ Архів
        #### Z.9 — архівний рядок із високим P
        - **P0** · 🤖 · ⚪ · → `04_01 §1`
      MD

      expect(described_class.priority_order_violations(noisy)).to be_empty
      # ⚠️ Стеля ліхтаря, названа прямо: він рахує секції, де порівняння МОЖЛИВЕ
      # (≥2 items дають пару). Секція з одним пунктом просканована, але в лічбу не
      # входить — і саме тому пін на живому трекері вимагає `>= 8`, а не «всі».
      expect(described_class.priority_ordered_sections(noisy)).to eq([ "§04" ])
    end

    # 🔴 Ліхтар: без нього «нуль порушень» на живому файлі означало б «нуль перевірок»
    # рівно тоді, коли парсер тихо втратив скоуп (перейменована секція, зсунутий
    # ITEM_HEAD). Пінимо НЕПОРОЖНЮ множину секцій на РЕАЛЬНОМУ трекері.
    it "сканує непорожню множину секцій живого трекера" do
      sections = described_class.priority_ordered_sections
      expect(sections.size).to be >= 8
      expect(sections).to all(start_with("§"))
    end

    it "живий трекер тримає порядок" do
      expect(described_class.priority_order_violations).to be_empty
    end
  end
end
