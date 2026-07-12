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

    it "resolves EVERY member of a comma/backtick-joined §-list under one doc-id" do
      # The run used to stop at the comma / closing backtick → the trailing ref went
      # unchecked (`04_05 §2.9, §6` blind spot). All four below are real sections.
      expect(described_class.file_section_dangling_refs("see `03_05 §3.6`, §3.7 and 04_05 §1, §3")).to be_empty
    end

    it "flags a STALE trailing ref in a comma-joined list (not just the first)" do
      expect(described_class.file_section_dangling_refs("04_05 §1, §9 here"))
        .to include(a_string_matching(%r{04_05 §9}))
    end

    it "does NOT sweep a §X separated from the doc-id by intervening prose" do
      # only separator chars join consecutive § tokens; a word ("плюс") ends the run,
      # so the stale §9 is never (mis)attributed to 04_05 and falsely flagged.
      expect(described_class.file_section_dangling_refs("04_05 §1 плюс §9")).to be_empty
    end

    it "skips a §-ref to a doc-id that doesn't exist at all (not this guard's job)" do
      # `anchors[doc]` is nil for an unknown doc-id — resolving THAT is the
      # canon-ref existence guard's (`dangling_refs`) job, not this one's.
      expect(described_class.file_section_dangling_refs("ref `99_99 §1` here")).to be_empty
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
        - **P1** · 👤 · 🟢 · → `02_01 §3.4`, `07_02 §1.3`
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
end
