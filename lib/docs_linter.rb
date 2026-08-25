# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "digest"

# [SSOT anti-drift] Pure-function structural lints for docs/*.md (00_06).
# No Rails, no file I/O — each method takes file *text* and returns an array of
# human-readable violation strings, so it is unit-tested
# (spec/lib/docs_linter_spec.rb) and reused from lib/tasks/docs.rake
# (rake docs:check_refs). Mirrors the lib/tracker/dashboard.rb engine pattern.
module DocsLinter
  module_function

  # TRL matrix single-value (HARD; scope: 00_03 §1 canonical matrix).
  # Per-module cells must be a single integer 1-9, never a range ("5-6"/"8-9")
  # — 00_03 §1 fixes the NASA 1-9 scale. Only rows whose first cell is
  # "NN <module>" are inspected; NASA-scale *stage* rows start "**TRL 5-6**" and
  # are skipped. Returns ["06 DevOps → TRL cell '5-6' ...", ...].
  def trl_matrix_range_violations(text)
    text.each_line.filter_map do |line|
      m = line.match(/\A\|\s*(\d{2}\s+[^|]+?)\s*\|\s*([^|]+?)\s*\|/)
      next unless m
      next if m[2].strip.match?(/\A[1-9]\z/)

      "#{m[1].strip} → TRL cell '#{m[2].strip}' (must be a single 1-9, not a range)"
    end
  end

  # [SSOT anti-drift] TRL range-consistency (HARD; owner 00_03 §1). The per-module
  # TRL band lives in the "Per-module TRL" table (module → current | target). That
  # row is the MINIMUM member-TRL of a module's *critical-path* sub-docs — so a
  # sub-doc may legitimately sit ABOVE the row (it is the source; the row takes the
  # min) and an off-critical-path sub-doc may sit BELOW it (06_01=4 vs row 5; 00_03's
  # Статус reports the *System* TRL 3, not its own maturity). That makes the LOWER
  # bound exception-ridden — "critical-path membership" is not machine-derivable from
  # the files — so this guard checks only the bounds with NO legitimate exception:
  #   (a) band well-formed — each row's current ≤ target;
  #   (b) row not inflated — a module's current ≤ the MAX member-TRL of its NN_xx docs
  #       (the row is a min; it may never sit above EVERY member);
  #   (c) doc ceiling     — a sub-doc's member-TRL ≤ its module's target (a doc cannot
  #       declare itself more ready than its own module's goal → inflated claim or a
  #       stale target governance forgot to raise).
  # The caller passes the 00_03 matrix text + {basename => member_TRL int} and gets
  # ready, self-prefixed strings (mixed module- and doc-scoped, like the sibling). Rows
  # are detected exactly as trl_matrix_range_violations (first cell "NN <name>"), so the
  # NASA-stage table ("**TRL n-m**") is never parsed. Pure: no I/O.
  TRL_BAND_ROW_RE = /\A\|\s*(\d{2})\s+[^|]*\|\s*(\d)\s*\|\s*(\d)\s*\|/

  def trl_range_consistency(matrix_text, doc_trls)
    bands = {}
    rows  = {}
    matrix_text.each_line do |line|
      m = line.match(TRL_BAND_ROW_RE)
      next unless m

      bands[m[1]] = [ m[2].to_i, m[3].to_i ]
      rows[m[1]]  = line
    end
    return [] if bands.empty?

    members = doc_trls.group_by { |base, _| base[0, 2] }.transform_values { |pairs| pairs.map(&:last) }
    by_doc  = doc_trls.group_by { |base, _| base[0, 2] }

    out = []
    bands.each do |mod, (cur, tgt)|
      out << "00_03 §1: module #{mod} current TRL #{cur} > target #{tgt} (band inverted)" if cur > tgt
      max = members[mod]&.max
      out << "00_03 §1: module #{mod} current TRL #{cur} > its highest sub-doc member-TRL #{max} (row is a min, never above every member)" if max && cur > max
      # 🔴 Друга половина ТОГО САМОГО правила, якої не було до 2026-08-22. §1 каже
      # жирним «рядок модуля = агрегат (МІНІМУМ) member-TRL», а перевірялась лише
      # верхня межа — тож рядок 4 при члені 3 проходив мовчки. Виміряно: порушували
      # ДВА модулі, і один свій розрив оголошував у клітинці блокера поіменно, другий
      # ні. Тому гейт вимагає не рівності, а ОГОЛОШЕННЯ: рядок вище мінімуму
      # легітимний (успадкований System-lock, fallback-шлях поза критичним шляхом) —
      # але клітинка мусить НАЗВАТИ гейтуючий док, інакше розрив мовчазний.
      minm = members[mod]&.min
      if minm && cur > minm
        low = by_doc[mod].to_a.select { |_, v| v == minm }.map(&:first)
        named = low.any? { |d| rows[mod].to_s.include?(d[0, 5]) }
        unless named
          out << "00_03 §1: module #{mod} row #{cur} is ABOVE its lowest member #{minm} (#{low.map { |d| d[0, 5] }.join(", ")}) " \
                 "and the blocker cell names none of them — the row IS the minimum by §1, so a higher row is " \
                 "legitimate only when the cell says WHICH doc gates and why (the 06 row is the reference form)"
        end
      end
    end
    doc_trls.each do |base, trl|
      tgt = bands[base[0, 2]]&.last
      out << "#{base}: member-TRL #{trl} > module #{base[0, 2]} target #{tgt} (00_03 §1 — inflated claim or stale target)" if tgt && trl > tgt
    end
    out
  end

  # [SSOT anti-drift] Public-manifesto TRL parity (HARD; owner 00_03 §1).
  # `docs/manifest.md` §5 states a TRL for four layers, and it is the only PUBLIC
  # artifact here that does — §5 turns the statement into a promise of its own
  # ("Anyone proposing to issue tokenized claims on real-world biology owes that
  # level of transparency"). Every OTHER axis of that file is already governed by
  # name — offering_lexicon_check holds it in HARD_DOCS, linkify_bare_refs and the
  # rate-mirror carry genre exemptions — so the manifesto is already treated as its
  # own genre with its own rules, and this was the one axis left unwritten. Silent
  # drift here is not cosmetic: it is a stale claim about our own honesty.
  #
  # Why no existing gate sees it: the manifesto is NOT a canon doc and has no
  # `## ✅ Статус` block, while trl_range_consistency reads member-TRLs harvested
  # from exactly those blocks. Its absence is structural, not an oversight.
  #
  # ANCHOR — a claim is `**<label>:** TRL N`. The bold label is what makes a number
  # an ASSERTION instead of prose, and that distinction carries the gate: the same
  # bullets also say "the TRL-9 gate", "physical TRL 4" and "in-silico = TRL 3",
  # every one a TARGET or a norm, never a statement about today. The cheap rule
  # (min of every TRL digit in the bullet) returns the right answer on today's text
  # — but only by accident, because a target is always ≥ the current level; one
  # honest sentence like "past the TRL 2 stage" would make it scream. Read the
  # claim FORM, never the digit.
  #
  # AGGREGATION — a bullet may carry several claims (capsule TRL 6 beside its power
  # chain TRL 4) and the module reads at the lowest. That is not manifesto prose but
  # the canon rule itself (00_03 §1: «рядок модуля = агрегат (мінімум) member-TRL»),
  # so MIN(claims in the bullet) must equal MIN(00_03 current) over the bullet's
  # modules — the same arithmetic on both sides of the comparison.
  #
  # OWNERSHIP IS DECLARED, never inferred. Which module a public bullet speaks for
  # is a human judgement — the Backend bullet legitimately covers 04 AND 05 — and a
  # guessing gate would be wrong in the silent direction. The registry doubles as
  # the SET pin: a bullet that quietly disappears is itself a violation, because a
  # check that only validates the claims it happens to find is green on an empty
  # page. Ceiling, stated: a TRL claim written WITHOUT the bold-label form is
  # invisible here by construction — that is the price of not firing on prose.
  MANIFEST_TRL_CLAIM  = /\*\*([^*]+?):\*\*\s*TRL[[:space:]-]*(\d)(?![\d])/
  MANIFEST_TRL_OWNERS = {
    "Backend"                 => %w[04 05],
    "Firmware"                => %w[03],
    "Hardware capsule"        => %w[02],
    "Tri-zone coaxial anchor" => %w[01]
  }.freeze

  def manifest_trl_parity(matrix_text, manifest_text)
    return [] if matrix_text.nil? || manifest_text.nil?

    bands = {}
    matrix_text.each_line do |line|
      m = line.match(TRL_BAND_ROW_RE)
      bands[m[1]] = m[2].to_i if m
    end
    return [ "manifest.md: 00_03 §1 per-module band unreadable — parser found no rows, so parity was never measured" ] if bands.empty?

    out  = []
    seen = {}
    manifest_text.each_line do |line|
      claims = line.scan(MANIFEST_TRL_CLAIM)
      next if claims.empty?

      lead  = claims.first.first
      owner = MANIFEST_TRL_OWNERS.keys.find { |k| lead.include?(k) }
      unless owner
        out << "manifest.md: TRL claim by an unregistered layer #{lead.inspect} — declare its module(s) in MANIFEST_TRL_OWNERS, or drop the claim"
        next
      end
      out << "manifest.md: layer #{owner.inspect} states a TRL twice — one public claim per layer" if seen.key?(owner)
      seen[owner] = true

      canon = MANIFEST_TRL_OWNERS[owner].filter_map { |mod| bands[mod] }.min
      next if canon.nil?

      claimed = claims.map { |_, n| n.to_i }.min
      next if claimed == canon

      out << "manifest.md: PUBLIC TRL #{claimed} for #{owner.inspect} ≠ 00_03 §1 module " \
             "#{MANIFEST_TRL_OWNERS[owner].join('/')} = #{canon} — fix whichever is stale"
    end

    (MANIFEST_TRL_OWNERS.keys - seen.keys).each do |missing|
      out << "manifest.md: §5 states no TRL for #{missing.inspect} — the layer lost its public claim (or the anchor moved)"
    end
    out
  end

  # Blockers live in 00_07, not canon (decided 2026-05-29). Canon docs must not
  # host a blocker SECTION — neither open ("🛑 Блокери", "🛑 Відкриті Блокери")
  # nor a resolved-archive ("✅ Архів", "✅ Закриті Блокери (PR #…)"). ALL blockers
  # (open + closed) live in 00_07 (open → §module, closed → §🗄️ Архів); canon keeps
  # the design/constraint as body prose. Heuristic: a `## ` heading bearing a status
  # emoji (🛑/✅/🟢/🟡/🔴/🚨) together with a blocker/archive word. Returns the offending
  # headings. Lines inside ``` fenced blocks are skipped, so a skeleton *example*
  # (e.g. 00_06 §1) is not a false positive. (Caller exempts 00_07.)
  STATUS_EMOJI = "🛑✅🟢🟡🔴🚨"

  def canon_blocker_sections(text)
    in_fence = false
    text.each_line.filter_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence
      next unless line.start_with?("## ")

      heading = line.strip
      next unless heading.match?(/[#{STATUS_EMOJI}]/)

      # "Архів" alone (resolved-archive) or any "…Блокер…" with the status emoji.
      heading if heading.match?(/Архів/i) || heading.match?(/блокер/i)
    end
  end

  # [SSOT standard conformance] Each canon doc must carry the standard skeleton
  # (00_06): a ✅ Статус, a top 🔗 Cross-references, and an auto-ToC (TOC:AUTO
  # markers). Exempt: 00_00 (SSOT index), 00_07 (tracker / blocker home), and
  # legacy appendix files (any *_Appendix / *_appendix name — case-insensitive first
  # letter so the real `..._Appendix` basename matches). Caller passes basename (sans .md)
  # + text; returns the missing element names so a CI gate keeps the tree from regressing.
  CONFORMANCE_EXEMPT = /\A00_00_|\A00_07_|_[Aa]ppendix/

  def conformance_violations(basename, text)
    return [] unless basename.match?(/\A\d\d_\d\d_/)

    miss = []
    # [DOC-T.49] H1 is checked BEFORE the exempt-return: the skeleton exemptions exist
    # because 00_00/00_07/appendix legitimately lack ✅ Статус — none of them may lack a
    # TITLE. A lost H1 is the one skeleton defect no other gate can see, and it un-anchors
    # the file wholesale: an editing accident glued 00_07's H1 into a preceding paragraph
    # (`#🔴 …` — no space after `#`, so CommonMark reads a plain paragraph, not a heading)
    # and every doc gate stayed green for a whole commit. First NON-BLANK line, so leading
    # blank lines are tolerated; `#x` without a space correctly fails (it is not a heading).
    miss << "# H1 heading (first non-blank line)" unless text.lines.find { |l| !l.strip.empty? }&.start_with?("# ")
    return miss if basename.match?(CONFORMANCE_EXEMPT)

    miss << "## ✅ Статус" unless text.include?("## ✅ Статус")
    miss << "## 🔗 Cross-references" unless text.include?("## 🔗 Cross-references")
    miss << "📑 auto-ToC markers" unless text.include?("<!-- TOC:AUTO:START -->")
    miss
  end

  # [SSOT anti-drift] RTC backup registers (DR0–DR19) are a finite, SSOT-owned
  # resource whose allocation map lives canonically in 03_01 §2. A register's
  # *availability* ("free"/"reserve"/"вільн"/"резерв"/"spare"/"vacant") is owned
  # by that map — when any OTHER doc restates it, it drifts (exactly how
  # "DR15 наразі резерв" survived in 03_02/00_07 after FW.2 claimed DR15 in
  # 03_01). Other docs may freely REFERENCE a register ("FC у DR15", "DR15
  # зайнято FW.2") — only *availability* claims are flagged. Bit-field "reserved"
  # (e.g. "reserved:8", "зарезервовано:") is excluded (those are reserved BITS,
  # not a spare register). Advisory: caller passes basename + text, skips the
  # owner (03_01); returns ["DR15 — availability claim …", …]. Lines inside
  # ``` fences are skipped.
  # Exempt the SSOT docs that legitimately describe register allocation:
  # 03_01 (the canonical RTC map) and 03_05 (the FW.2 FC/nonce policy, which
  # owns the DR15 narrative + cross-refs 03_01). Every other doc must only
  # *reference* a register, never assert its availability.
  RTC_OWNER_DOC = /\A03_01_|\A03_05_/
  # Whole-register availability words at a Unicode-letter boundary, so
  # "звільнило"/"зарезервовано:"/"резервних" do NOT match (those are "freed a
  # different reg" / bit-field / "no reserves left"); only standalone
  # вільн*/резерв/free/reserve(-for) — the real "this register is spare" claim.
  #
  # ⚠️ Оголошена стеля (виміряна 2026-08-24, FP): словник збігається з
  # ІДЕНТИФІКАТОРАМИ, а не лише з прозою — метрика `…_insurance_reserve_hold_total`
  # у code-span на тому самому РЯДКУ, що й приклад `DR0..DR19`, дає хибний хіт.
  # Гейт лишено як є свідомо: він рядковий, а лік дешевший за зміну периметра —
  # не тримати назву-ідентифікатор в одному рядку з DRn (у нас це вирішилось
  # розбиттям надто довгого булета, який і без того просився на два).
  RTC_AVAIL_RE = /(?<!\p{L})(вільн|spare|vacant|вакант|free\b|reserve(?!d?:)|резерв(?![\p{L}:]))/i

  def rtc_register_allocation_drift(basename, text)
    return [] if basename.match?(RTC_OWNER_DOC)

    in_fence = false
    text.each_line.filter_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence
      next if line.lstrip.start_with?("|") # skip tables (coverage matrices etc.)

      # Match bare DRn, `DRn`, and RTC_BKP_DRn (the leading "_" blocks \b).
      dr = line[/(?<![A-Za-z])DR(\d{1,2})\b/, 1]
      next unless dr && dr.to_i.between?(0, 19)
      next unless line.match?(RTC_AVAIL_RE)

      "DR#{dr} availability claim outside owner (03_01 RTC map) → #{line.strip[0, 110]}"
    end
  end

  # [SSOT anti-drift] STM32WLE5JC physically has only 20 RTC backup registers
  # (DR0..DR19 — canon 03_01 §2 / 05_02). DR20+ DO NOT EXIST on this silicon, yet
  # future-feature notes asserted phantom DR20-DR31 (Edge-RL), DR20-DR21 (ARCH.35
  # ring) and DR24-DR26 (old FW.8) as usable state buffers — a hardware
  # impossibility the allocation-drift guard missed (that one skips tables + needs
  # an availability word; this needs neither, and the two live phantoms sat in a
  # table row + a blockquote). Flags any DRn with n>19 UNLESS the line marks it
  # dead (DEPRECATED / не існу / фізично неможлив / not exist / слід читати / the
  # DR0..DR19 boundary / лише 20). Skips fenced code (05_02 keeps a labelled
  # deprecated DR20-DR23 example block). Applies to ALL docs incl. the owner —
  # the chip has no DR20 for anyone.
  RTC_PHANTOM_NEGATION = /DEPRECATED|не існу|фізично неможлив|not exist|слід читати|DR0\s*\.\.\s*DR19|лише 20/i

  def rtc_register_out_of_range(text)
    in_fence = false
    text.each_line.filter_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence
      next if line.match?(RTC_PHANTOM_NEGATION)

      phantom = line.scan(/(?<![A-Za-z])DR(\d{1,2})\b/).flatten.map(&:to_i).find { |n| n > 19 }
      next unless phantom

      "phantom RTC register DR#{phantom} — STM32WLE5JC has only DR0..DR19 " \
        "(03_01 §2); route to Flash-KV/SRAM, not a non-existent register | #{line.strip[0, 100]}"
    end
  end

  # [SSOT anti-drift] Lorenz constants (σ=10 / ρ=28 / β=8÷3, dt, iterations) are
  # SSOT-owned by 03_04 §1.2 (firmware↔backend mirror). Re-declaring the formula
  # values elsewhere drifts — exactly how 05_01 §2 + 00_01 §5 carried a stale
  # σ/ρ/β code block until the 2026-05-30 05/07 restructure. Other docs must
  # REFERENCE 03_04 §1.2, never re-state. Heuristic: a β *assignment*
  # (`beta = 8.0 / 3.0` / `BASE_BETA = …`) is the unique Lorenz re-declaration
  # signature — an inline mention ("…(8.0/3.0, parity-tested)") inside DCI prose
  # is NOT a re-declaration and is not flagged. Flag the assignment outside the
  # owner UNLESS the line is a labelled mirror ("дзеркало"/"SSOT"/"не дублю"/
  # cites 03_04) or a firmware-file content reference (`firmware/…`, which shows
  # the firmware-side value). Tables (illustrative governance "hardcoded-
  # constants" rows) and the firmware-lifecycle doc 03_01 (legit firmware-side
  # BASE_BETA) are exempt. Owner-only-vocabulary, same shape as RTC drift.
  LORENZ_OWNER_DOC = /\A03_04_|\A03_01_/
  LORENZ_BETA_RE = %r{(?:base_)?beta\s*=\s*\(?\s*8\.0\s*/\s*3\.0}i
  LORENZ_MIRROR_RE = %r{дзеркало|SSOT|не дублю|03_04|firmware/}i

  def lorenz_formula_drift(basename, text)
    return [] if basename.match?(LORENZ_OWNER_DOC)

    text.each_line.filter_map do |line|
      next if line.lstrip.start_with?("|") # skip tables (illustrative rows)
      next unless line.match?(LORENZ_BETA_RE)
      next if line.match?(LORENZ_MIRROR_RE)

      "Lorenz β `8.0/3.0` re-stated outside owner (03_04 §1.2) → #{line.strip[0, 100]}"
    end
  end

  # [SSOT anti-drift] telemetry_logs has NO chain_hash column (it lives in audit_logs /
  # ethereum_anchors). The Merkle-anchor (ARCH.12) leaf-formula is Z-based (05_02 §E.60),
  # NOT a tree over TelemetryLog.chain_hash — a plausible-but-false recipe that drifted in
  # 05_04. Catches the POSITIVE claim; negation/explanation lines (the drift-fix itself,
  # which must name the wrong token to forbid it) are exempt. No owner doc — the column
  # never exists anywhere, so stating it is always drift. HARD.
  TL_CHAIN_HASH_RE = %r{TelemetryLog\s*\.?\s*chain_hash|telemetry_logs?\b[^\n]{0,40}\bchain_hash|\bchain_hash\b[^\n]{0,40}\btelemetry_logs?\b}i
  TL_CHAIN_HASH_EXEMPT = %r{нема|не існ|не має|відсут|такої колонк|drift|нікол|\bНЕ\b|does not|doesn't|no .{0,20}column}i

  def telemetry_log_chain_hash_drift(text)
    text.each_line.filter_map do |line|
      next if line.lstrip.start_with?("|") # skip tables (illustrative rows)
      next unless line.match?(TL_CHAIN_HASH_RE)
      next if line.match?(TL_CHAIN_HASH_EXEMPT)

      "telemetry_logs has no chain_hash column — Merkle leaf = Z-based (05_02 §E.60), not TelemetryLog.chain_hash → #{line.strip[0, 100]}"
    end
  end

  # [ARCH.11] REJECTED VOCABULARY — `bio_potential` as a ROUTING metric (HARD).
  # The ADR rejected it on a MECHANISM, not on taste: routing traffic through the
  # healthiest tree loads it with ~90% of relaying → drains its ionistor → it fails to
  # send its OWN telemetry → its Z-attractor "falls" → the system classifies a HEALTHY
  # tree as sick. Two distinct faults ride together: an observer-effect (the network
  # load distorts the very signal being measured — `bio_potential` is the MEASURAND,
  # never a routing resource) and a positive feedback loop that systematically kills
  # the best nodes.
  #
  # 🔴 Why a guard at all, when the term appears nowhere today: a rejection with no
  # carrier is exactly the shape that rots. The phrase is INTUITIVE — "route through
  # the healthiest node" reads as obviously good — so it re-enters by being re-derived,
  # not by being copied, and no owner doc can be exempt because the term is wrong
  # EVERYWHERE. Hence owner-less, unlike the σ/ρ/β class.
  #
  # ⚠️ NEGATION-EXEMPT is load-bearing, not politeness: the rejection itself must name
  # the token to forbid it, so a line carrying «відхилено»/«rejected»/«НЕ метрика»
  # passes. Without it the guard reds on the ADR that created it — the same trap the
  # neighbouring `chain_hash` rule names.
  BIO_POTENTIAL_RE = %r{bio[_\s-]?potential}i
  BIO_POTENTIAL_EXEMPT = %r{відхил|відкинут|rejected|reject|\bНЕ\b|не є|ніколи|never|observer.effect|vocabulary|guard|заборон}i

  def bio_potential_as_metric(text)
    text.each_line.filter_map do |line|
      next if line.lstrip.start_with?("|")
      next unless line.match?(BIO_POTENTIAL_RE)
      next if line.match?(BIO_POTENTIAL_EXEMPT)

      "`bio_potential` is the MEASURAND, never a routing metric — ADR rejected it on the " \
        "observer-effect mechanism (00_07 ARCH.11) → #{line.strip[0, 100]}"
    end
  end

  # [SSOT anti-drift] Retired growth_points formula (HARD). TWO generations are now dead:
  #   (1) pre-FW.29-PACK 6-bit wire clamp `clamp(reward, 10, 63)`;
  #   (2) pre-E.63 chaos-derived reward `(reward / 2).clamp(5, 31)` from `50 - deviation`
  #       (|OPTIMAL_Z − z|) — proven economically null/inverted (00_07 E.63).
  # [E.63] growth_points in homeostasis is now `metabolic_health(delta_t)` (monotonic
  # recharge vigor), owned by 03_04 §4.3 and mirrored in firmware `bio_contract.rb`;
  # backend only DECODES the wire value (`(status_byte & 0x1F) * 2`). It is the
  # token-MINTING reward, so a stale copy of EITHER dead formula silently misstates
  # emission — invisible to every other guard (Lorenz knows only β; rate-guard exempts
  # manifest). Signature tokens unique to the dead formulas: `clamp(… 10, 63 …)`,
  # `reward / 2`, `50 - deviation`. The live form (`5 + m * 26` / `metabolic_health`)
  # never matches. NOT table-skipped (drift lived in a manifest table cell). Owner
  # 03_04 (may keep history) + standard 00_06 (cites it) + 00_07 (tracker) exempt —
  # 03_01 was DROPPED from the exempt set in E.63 so its stale mirror is forced to a
  # thin §4.3 reference (One-Home). Same shape as lorenz_formula_drift.
  GP_CLAMP_OWNER_DOC  = /\A03_04_|\A00_06_|\A00_07_/
  GP_CLAMP_RETIRED_RE = %r{clamp\([^)\n]*\b10\s*,\s*63\b|\breward\s*/\s*2\b|\b50\s*-\s*deviation\b}

  def growth_points_clamp_drift(basename, text)
    return [] if basename.match?(GP_CLAMP_OWNER_DOC)

    text.each_line.filter_map do |line|
      next unless line.match?(GP_CLAMP_RETIRED_RE)

      "retired growth_points formula (`10,63` / `reward / 2` / `50 - deviation`) — [E.63] live form is `metabolic_health(delta_t)` (03_04 §4.3) → #{line.strip[0, 100]}"
    end
  end

  # [SSOT anti-drift] StatusByte layout One-Home (DOC-T.43). Post-FW.29 wire byte 10 =
  # [PanicFlag:1 (bit7) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)] — pack
  # (status << 5) | gp, mask & 0x1F. Owner logic+packing = 03_04 §4.3/§4.4; wire byte-position =
  # 03_05 §2.1; 7 sites (03_01/03_02/05_02/04_01/04_02) reference, not restate. FW.2 wire-rev2.1
  # moves the packet, so a site lagging back to the pre-FW.29 6-bit layout is a silent drift that
  # carries growth_points (the mint magnitude). ANTI-RETIRED, not positive-consistency: most live
  # sites state the layout in PROSE ("bits 6..5") with no code literal → a "must be present" rule
  # would FP every one of them; instead ban the dead pre-FW.29 signature (status << 6, the 6-bit
  # mask 0x3F, "bits 7..6"/[7:6], a 6-bit growth width), which has ZERO docs hits today. Context-
  # anchored to a StatusByte keyword so an unrelated 0x3FFF/0x7F/96-bit UID is ignored; a line
  # marking the value historical (the owner's "6 → 5" migration note) is exempt. NOT table-skipped
  # (gp_clamp drift lived in a table cell). Meta 00_06/00_07 exempt (they name the retired form as
  # an example). Orthogonal to growth_points_clamp_drift (that bans the wire RANGE 10,63; this bans
  # the bit GEOMETRY — the two never share a regex). Same shape as anchor_dimension_drift.
  STATUSBYTE_META_DOC = /\A00_06_|\A00_07_/
  STATUSBYTE_CTX_RE   = /StatusByte|status_byte|PanicFlag|PANIC_FLAG|bio_status|growth[_ ]?points|GrowthPoints/i
  STATUSBYTE_RETIRED  = [
    [ /\bstatus\b[^\n]{0,14}<<\s*6\b/i,               "status packed << 6 (was bits 7..6)" ],
    [ /(?<![0-9A-Fa-fx])0x3F(?![0-9A-Fa-f])/,         "6-bit growth mask 0x3F (live = 0x1F)" ],
    [ /bits?\s*7\s*[.:]+\s*6\b|\[\s*7\s*:\s*6\s*\]/i, "status in bits 7..6 / [7:6]" ],
    [ /(?:growth[_ ]?points|GrowthPoints|\bgp\b)[^\n]{0,20}\b6[\s-]*(?:bit|біт)/i, "6-bit growth width" ]
  ].freeze
  STATUSBYTE_HISTORICAL = /переїхав|зменшено|було|раніше|superseded|застаріл|historical|retired|deprecated|до FW\.29|6\s*[→–-]+\s*5|→\s*6\.\.5|усунено|колишн|\bold\b|former/i

  def status_byte_layout_drift(basename, text)
    return [] if basename.match?(STATUSBYTE_META_DOC)

    out = []
    text.each_line do |line|
      next unless line.match?(STATUSBYTE_CTX_RE)
      next if line.match?(STATUSBYTE_HISTORICAL)

      STATUSBYTE_RETIRED.each do |retired_re, label|
        out << "retired pre-FW.29 StatusByte layout (#{label}) — live = [PanicFlag:1|Status:2 (bits 6..5)|GrowthPoints:5 (bits 4..0)], pack (status<<5)|gp, mask 0x1F (03_04 §4.3/§4.4 + wire 03_05 §2.1) → #{line.strip[0, 90]}" if line.match?(retired_re)
      end
    end
    out
  end

  # [SSOT anti-drift] Tokenomics / carbon RATE One-Home (HARD after the 2026-05-31
  # dedup). The mint rate (`10,000 growth_points = 1 SCC`) and carbon rate
  # (`2000 SCC = 1 tCO₂`) are governance-CHANGEABLE parameters (05_06), so they get
  # ONE home: 05_03 (technical) + 00_04 §3 (business view). Re-stating the VALUE
  # elsewhere drifts the instant governance re-prices — exactly the silent dup found
  # across 8 docs (00_01/04_01/05_01/05_02/05_06/00_04 body/03_03). Other docs must
  # REFERENCE the home, never restate the number. Exempt: 05_03 + 00_04 (homes),
  # 00_07 (tracker archive) and manifest
  # (the standalone manifesto). A line that itself references the home or is a
  # labelled mirror is not flagged — same shape as lorenz_formula_drift.
  RATE_OWNER_DOC     = /\A05_03_|\A00_04_|\A00_07_|\Amanifest/
  TOKENOMICS_RATE_RE = /10[ .,]?000[^\n]{0,30}=\s*1\s*SCC/i
  CARBON_RATE_RE     = /2[ .,]?000\s*SCC\s*=\s*1\s*[тt]/i
  RATE_MIRROR_RE     = /дзеркал|mirror|05_03|00_04|ProtocolParameters|SystemParameter/i

  def tokenomics_rate_drift(basename, text)
    return [] if basename.match?(RATE_OWNER_DOC)

    text.each_line.filter_map do |line|
      next if line.match?(RATE_MIRROR_RE)

      if line.match?(TOKENOMICS_RATE_RE)
        "mint rate `10,000 gp = 1 SCC` re-stated outside home (05_03 / 00_04 §3) → #{line.strip[0, 90]}"
      elsif line.match?(CARBON_RATE_RE)
        "carbon rate `2000 SCC = 1 tCO₂` re-stated outside home (05_03 / 00_04 §3) → #{line.strip[0, 90]}"
      end
    end
  end

  # [SSOT anti-drift] Rate-guard SELF-ANCHOR (DOC-T.40). The guard's regexes hardcode the
  # CURRENT governance-changeable values — a deliberate tripwire (§3 footnote), but a latent
  # mine: a re-price edits the home doc, the stale regex silently stops guarding the NEW value,
  # and the One-Home function is lost without a single red light. The anchor closes that loop:
  # each home must still MATCH the guard's own pattern, so re-pricing the home fails CI until
  # the regex is consciously updated together with every mirror. The violation text doubles as
  # the mirror checklist — manifest.md is exempt from the drift-guard by design (genre),
  # so THIS is the only red light that will ever name them on a re-price (DOC-T.41).
  RATE_ANCHOR_HOMES = {
    "05_03" => [ [ :TOKENOMICS_RATE_RE, "mint rate `10,000 gp = 1 SCC`" ] ],
    "00_04" => [ [ :TOKENOMICS_RATE_RE, "mint rate `10,000 gp = 1 SCC`" ],
                 [ :CARBON_RATE_RE, "carbon rate `2000 SCC = 1 tCO₂`" ] ]
  }.freeze

  def tokenomics_rate_anchor(basename, text)
    (RATE_ANCHOR_HOMES[basename[/\A\d\d_\d\d/]] || []).filter_map do |const, label|
      next if text.match?(DocsLinter.const_get(const))

      "home #{basename[/\A\d\d_\d\d/]} no longer matches the guard's #{const} (#{label}) — " \
        "re-price? Update the regex in lib/docs_linter.rb AND sweep the mirrors: " \
        "manifest.md (§2 genre home), 02_06 §7 ROI, 03_04/05_02 references"
    end
  end

# [SLASH-1] DAO-мутабельний ПОРІГ, поданий клієнтові як ФІКСОВАНА умова.
#
# Сусідній rate-guard вище стереже СТАВКИ (10 000:1 · 2000:1) — конвенції, що не
# рухаються без присуду. `stress_index >= 0.83` інший звір: він DAO-live
# (`SystemParameter :stress_threshold` ← `ProtocolParameters.sol`, bounds 0.65..1.0),
# тож голос governance МОВЧКИ інвалідує вже опубліковану умову — а `00_04` є тим
# документом, із якого ростуть MSA/SLA. Клас був відомий репо, але поріг у сітку
# rate-guard'а не потрапляв: той шукає ставку, а не заяву про фіксованість.
#
# ⛔ ОГОЛОШЕНА СТЕЛЯ (без неї зелений почав би читатись ширше, ніж є):
#   • Периметр — ЛИШЕ `00_04` (customer-facing юр-дім). `05_05`/`04_02` цитують
#     поріг як інженерний факт, і там застереження було б шумом.
#   • Гейт судить НАЯВНІСТЬ маркера мутабельності в тому самому рядку, ніколи —
#     чи він доречний і чи число ще правильне.
#   • Порожня множина тут — МЕТА, не провал: у мить написання всі три сайти вже
#     несуть маркер, тож живість доводиться мутацією, не популяцією (§Guard-craft #61).
MUTABLE_THRESHOLD_RE = /stress_index\s*[<>=]{1,2}\s*0[.,]83/i
THRESHOLD_MUTABILITY_RE = /DAO-керован|DAO-live|SystemParameter|ProtocolParameters|поточний дефолт/i

def customer_facing_threshold_drift(basename, text)
  return [] unless basename.start_with?("00_04")

  text.each_line.filter_map do |line|
    next unless line.match?(MUTABLE_THRESHOLD_RE)
    next if line.match?(THRESHOLD_MUTABILITY_RE)

    "customer-facing `stress_index 0.83` подано без маркера DAO-мутабельності — " \
      "голос governance інвалідує опубліковану умову мовчки (SLASH-1; дім значення — " \
      "`SystemParameter :stress_threshold`) → #{line.strip[0, 90]}"
  end
end

  # [SSOT anti-drift] Solidity solc / pragma version One-Home (HARD). The locked
  # compiler version (`pragma solidity 0.8.X`, foundry `solc_version`, myth `--solv`) is a
  # single repo-wide fact — every contract pins the SAME version. Its documented home is
  # the contracts doc 05_03 (Pragma table, "Dual Token System"); the ultimate SSOT is the
  # CODE (contracts/foundry.toml + each *.sol pragma), pin-policy → 03_01 §12.5. Re-stating
  # the literal elsewhere drifts the instant we bump solc — exactly the silent dup just
  # found: 9 stale `0.8.28` copies survived the 0.8.35 bump across 00_05/05_04 until swept.
  # Other docs REFERENCE 05_03, never restate the number. Owner 05_03 keeps the Pragma table
  # + the foundry/slither/myth command examples (it IS the home). Exempt: 05_03 (owner) +
  # 00_06 (this standard) + 00_07 (tracker historical log). A line that references the home
  # (`05_03`) or is a labelled mirror is not flagged. NOT table-skipped (the 05_04 drift
  # lived in a table cell). Same shape as tokenomics_rate_drift.
  SOLC_OWNER_DOC  = /\A05_03_|\A00_06_|\A00_07_/
  SOLC_VERSION_RE = /(?:pragma(?:\s+solidity)?|solc\w*|--solv)[^\n]{0,20}?(?<!\d)0\.8\.\d+/i
  SOLC_MIRROR_RE  = /дзеркал|mirror|05_03/i

  def solc_pragma_version_drift(basename, text)
    return [] if basename.match?(SOLC_OWNER_DOC)

    text.each_line.filter_map do |line|
      next unless line.match?(SOLC_VERSION_RE)
      next if line.match?(SOLC_MIRROR_RE)

      "solc/pragma version re-stated outside owner (05_03 Pragma table; code SSOT = contracts/foundry.toml + *.sol) → #{line.strip[0, 100]}"
    end
  end

  # [SSOT anti-drift] AI-vendor name re-stated outside owner (HARD, owner-only vocabulary).
  # The AI tool roster is VOLATILE (vendors come and go); canon must describe stable ROLES
  # (frontier-LLM / coding-agent) with concrete instances snapshotted ONCE in 00_06 §5.1
  # A vendor token re-stated elsewhere drifts the moment the roster shifts. Same shape as
  # solc/tokenomics. Case-sensitive on purpose (lowercase "cursor"/"grok" = UI/verb, не вендор).
  # EXCLUDES overloaded/generic tokens that would false-positive: "Codex" (OpenAI's coding
  # agent collides with "The Codex" SSOT-guard nickname), bare "Claude"/"Opus"/"Sonnet"/"Fable"
  # (model words that collide with prose). Exempt набір — це САМЕ те, що кодує AI_VENDOR_OWNER_DOC нижче: 00_06 (дім
  # ростера + цитує приклади) і 00_07 (трекер). ⛔ Не переказуй його прозою:
  # тут доти стояв ще й 00_02 «roster home», розчинений DOC-T.68 фазою 3, і
  # number_keyed_exemptions цього не бачив за побудовою — він валідує КОНСТАНТУ,
  # а не коментар поруч. Skips fenced code (a script may legitimately name a tool).
  AI_VENDOR_OWNER_DOC = /\A00_06_|\A00_07_/
  AI_VENDOR_RE        = /(?<![A-Za-z])(Gemini|Cursor|Copilot|Windsurf|ChatGPT|Grok|DeepSeek|Claude Code)(?![A-Za-z])/
  AI_VENDOR_MIRROR_RE = /дзеркал|mirror|00_06 §5/i

  def ai_vendor_name_drift(basename, text)
    return [] if basename.match?(AI_VENDOR_OWNER_DOC)

    in_fence = false
    text.each_line.filter_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence
      next if line.match?(AI_VENDOR_MIRROR_RE)
      next unless (m = line.match(AI_VENDOR_RE))

      "AI-vendor name `#{m[1]}` outside owner (00_06 §5 roster = ROLES frontier-LLM/coding-agent; reference the role) → #{line.strip[0, 90]}"
    end
  end

  # [SSOT anti-drift] Deprecated-term registry (HARD) — the enforcement arm of
  # Ruthless Pruning (00_06 §4). Tokens retired SSOT-wide must not reappear in the
  # ACTIVE canon; as each drift is fixed, the old form is added here so CI blocks its
  # return (the general "scripts catch drift" net). Keyed retired-token → replacement
  # hint. Use ONLY for UNAMBIGUOUS retired strings with no legit current use: a retired
  # part number (ZP-3/ZP-5 ∅27mm through-hole piezo → SMD Murata/TDK, 02_01 §3)
  # qualifies; a token still alive somewhere does NOT — LTC3108 survives as a DNP
  # cold-start fallback, so it is deliberately absent. Substring match → keep tokens
  # specific. Meta/legacy docs are EXEMPT (they legitimately NAME retired things):
  # 00_06 (this standard cites them as examples), 00_07 (tracker may reference an
  # old baseline in a "migrate-from" note).
  # [SSOT anti-drift] Frozen anchor key-dimensions (01_01 §1 home, radial+axial freeze
  # 2026-06-20). ONE physical anchor crosses every domain doc (geometry / metallurgy /
  # capsule / pogo / economics / RF), so each legitimately cites its dims — and a freeze must
  # collapse the OLD range to the new single value in ALL of them at once (the 7-doc manual
  # grep-sweep that motivated this guard). A SUPERSEDED range reappearing next to its part
  # keyword = freeze-drift. Heuristic mirrors the RTC guard: a range pattern AND a part-context
  # keyword on the same line; skip fenced code; a line marking the value historical is exempt.
  # Applies to ALL docs incl. the 01_01 owner (owner states the NEW value, never the old range).
  # At the NEXT freeze, add the newly-superseded range here — exactly like DEPRECATED_TERMS.
  ANCHOR_DIM_DRIFT = [
    [ /(?<!\d)20\s*[–-]\s*30(?!\d)/, /фланець|radome|радом|таблетк|купол|crown/i,
     "flange/radome Ø = 25 mm frozen (01_01 §1)" ],
    [ /(?<!\d)40\s*[–-]\s*60(?!\d)/, /zone ?2|зона ?2|втулк|терморозрив/i,
     "Zone 2 length = 50 mm frozen (01_01 §1)" ]
  ].freeze

  ANCHOR_DIM_HISTORICAL = /було|superseded|застаріл|replaced|замінен|historical|історичн|former|деприкейт/i

  def anchor_dimension_drift(_basename, text)
    in_fence = false
    out = []
    text.each_line do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence
      next if line.match?(ANCHOR_DIM_HISTORICAL)

      ANCHOR_DIM_DRIFT.each do |range_re, ctx_re, frozen|
        out << "superseded anchor range → #{frozen} | #{line.strip[0, 90]}" if line.match?(range_re) && line.match?(ctx_re)
      end
    end
    out
  end

  # [SSOT anti-drift] Superseded HW.3.IS thermal-stress / press-fit numbers (One-Home = the report +
  # 01_01 §4.2). The Lamé press-fit numbers were on the stale baseline (Ø10 / 3 mm) AND carried a
  # contact_pressure bug (b = R_INNER, not R_INTERFACE); frozen + fixed 2026-06-21, then the unified
  # thick-wall Lamé re-run 2026-06-22 moved SF again (σ_t SF 9.9×→3.4×→5.6× combined; P_c 34.7→22.6
  # buggy → 0.49-3.32→0.32-2.16). Both superseded SF generations (9.9× and 3.4×) are caught now. A
  # value pattern AND a thermal-context keyword on one line; a line marking the value historical
  # (correction/baseline/buggy/застаріл/колишній/старий/артефакт) is exempt — the
  # owner's Correction B quotes the old number legitimately. Mirrors anchor_dimension_drift; at the next
  # re-run that moves these numbers, supersede the patterns here too (like DEPRECATED_TERMS).
  THERMAL_STRESS_DRIFT = [
    [ /(?<!\d)(?:9\.9|3\.4)\s*[×x](?!\d)/, /\bSF\b|safety|Lam[ée]|PEEK|σ_?t|press[- ]?fit|thermal|термонапр/i,
     "thermal-stress SF = 5.6× combined / 14.6× thermal-only frozen (01_01 §4.2 / THERMAL_STRESS_REPORT)" ],
    [ /(?<!\d)(?:34\.7|22\.6)(?!\d)/, /P_c|press[- ]?fit|MPa|МПа|contact|relax|натяг/i,
     "press-fit P_c = 0.49-3.32→0.32-2.16 MPa frozen+bug-fixed (THERMAL_STRESS_REPORT)" ]
  ].freeze

  THERMAL_STRESS_HISTORICAL = /correction|baseline|buggy|застаріл|було|\bold\b|superseded|баговий|раніше|historical|колишній|старий|артефакт|former|artifact|overstated|over-stated/i
  # The report itself is the second owner (01_01 §4.2 + THERMAL_STRESS_REPORT, 00_06 §3 row):
  # its Correction-B/C chronology quotes every superseded number legitimately, incl. the frozen
  # pre-Correction §1 blockquote that carries no historical marker on the line. The exempt was
  # unnecessary while the scan stopped at docs/*.md; the DOC-T.42 extended surface reaches the
  # report, so the owner-exempt becomes load-bearing (same shape as RATE_OWNER_DOC).
  THERMAL_STRESS_OWNER_DOC = /\ATHERMAL_STRESS_REPORT\z/

  def thermal_stress_drift(basename, text)
    return [] if basename.match?(THERMAL_STRESS_OWNER_DOC)

    in_fence = false
    out = []
    text.each_line do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence
      next if line.match?(THERMAL_STRESS_HISTORICAL)

      THERMAL_STRESS_DRIFT.each do |val_re, ctx_re, frozen|
        out << "superseded thermal-stress value → #{frozen} | #{line.strip[0, 90]}" if line.match?(val_re) && line.match?(ctx_re)
      end
    end
    out
  end

  DEPRECATED_TERMS = {
    "silkennet-v1-aes256" => 'use "silken-aes-128-lora-key" / "silken-aes-256-device-key" (ARCH.42 256→128 HKDF info)',
    "ZP-3" => "retired ∅27mm through-hole piezo SKU → SMD piezo (Murata 7BB-15-6L0 / TDK B-Series), canon 02_01 §3",
    "ZP-5" => "retired ∅27mm through-hole piezo SKU → SMD piezo (Murata 7BB-15-6L0 / TDK B-Series), canon 02_01 §3",
    # FPU-міф (знято 2026-06-10): STM32WL M4 — БЕЗ FPU; усі ARM-збірки -mfloat-abi=soft.
    "fpv4-sp-d16" => "WLE5 has NO FPU → ARM builds are -mfloat-abi=soft (03_01 §12.4 ABI-інваріант)",
    "FPv4-SP-D16" => "WLE5 has NO FPU → ARM builds are -mfloat-abi=soft (03_01 §12.4 ABI-інваріант)",
    "mfloat-abi=hard" => "WLE5 has NO FPU → ARM builds are -mfloat-abi=soft (03_01 §12.4 ABI-інваріант)",
    "Cortex-M4F" => "WLE5 core is Cortex-M4 WITHOUT FPU (03_01 §12.4 / 03_03 §1.1)",
    "Cortex-M4 з FPU" => "WLE5 core is Cortex-M4 WITHOUT FPU (03_01 §12.4 / 03_03 §1.1)",
    # Retired project codename (BIZ.16, 2026-06-16): dissolved by altitude →
    # SilkenNet (product) / GaiaNexus (planetary federation). Distinct literal from
    # the LIVE "Gen 2.0" EBFC biochem axis (substring match → no false positive).
    "Gaia 2.0" => "retired project codename → SilkenNet (product) / GaiaNexus (planetary federation), 00_02 §5",
    # Binstub'и (CLAUDE.md §3): `bin/X` вантажиться швидше й не залежить від
    # того, чи активний правильний gemset. Ключі ПОІМЕННІ, а не голий
    # "bundle exec": `i18n-tasks`, `sidekiq`, `ruby` binstub'ів НЕ мають, тож
    # загальний ключ червонив би на прод-YAML і на легітимних ad-hoc викликах.
    "bundle exec rspec" => "use `bin/rspec` (binstub exists — CLAUDE.md §3)",
    "bundle exec rubocop" => "use `bin/rubocop` (binstub exists — CLAUDE.md §3)",
    "bundle exec brakeman" => "use `bin/brakeman` (binstub exists — CLAUDE.md §3)",
    "bundle exec bundler-audit" => "use `bin/bundler-audit` (binstub exists — CLAUDE.md §3)",
    "bundle exec rails" => "use `bin/rails` (binstub exists — CLAUDE.md §3)"
  }.freeze

  # [SSOT anti-drift] `[[wiki-link]]` — форма посилань МОЄЇ памʼяті
  # (`~/.claude/projects/**/memory/`), яка живе ПОЗА репозиторієм. У каноні вона
  # висяча за побудовою: читач, що клонував репо, відкрити її не може, а жоден
  # ref-гейт цього не бачить — вони резолвлять `NN_NN`-адреси й markdown-лінки,
  # а `[[...]]` для них просто текст.
  #
  # Клас не гіпотетичний: чотири входження у двох комітах за чотири дні, усі мої,
  # і обидва рази це був `00_07` — тобто рівно той файл, який `DEPRECATED_EXEMPT`
  # звільняє. Тому окрема перевірка БЕЗ винятків, а не ще один термін у мапі.
  #
  # Лік у прозі («не лінкуй памʼять із канону») не спрацював би: правило треба
  # в МОМЕНТ письма, а не в стандарті, який у цю мить ніхто не читає. Назву
  # класу пишемо словами — вона переносна й для стороннього читача.
  # ⊥ Скіли (`.claude/**`) НЕ входять у периметр свідомо: вони мій шар, як і
  # памʼять, тож там лінк резолвний і доречний.
  # ⚠️ Fenced-блоки пропускаємо, як роблять сусідні перевірки цього ж файлу
  # (`conformance_violations`, `bare_section_ref`, …). Причина конкретна, а не
  # симетрія: док, що ІЛЮСТРУЄ цей самий антипатерн літеральним прикладом у
  # код-блоці, — природна річ (сам `00_06 §3` уже мусив обходити самозловлювання
  # вручну, написавши форму елізією). Без пропуску гейт червонів би HARD на
  # інертному прикладі, а не на живому висячому посиланні — рівно та форма, де
  # цитата стає твердженням (`guard-craft` #29).
  MEMORY_WIKILINK = /\[\[[a-z][a-z0-9_]*\]\]/

  def memory_wikilink_violations(text)
    in_fence = false
    text.lines.filter_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence

      line.scan(MEMORY_WIKILINK)
    end.flatten.uniq.map do |link|
      "memory-лінк `#{link}` у каноні — `memory/` живе поза репозиторієм, тож " \
        "для читача це висяче посилання; назви КЛАС словами (скіли — виняток)"
    end
  end

  DEPRECATED_EXEMPT = %w[00_06 00_07].freeze

  def deprecated_terms(basename, text)
    return [] if DEPRECATED_EXEMPT.any? { |prefix| basename.start_with?(prefix) }

    DEPRECATED_TERMS.filter_map do |term, hint|
      "deprecated term `#{term}` present → #{hint}" if text.include?(term)
    end
  end

  # [SSOT anti-drift] Superseded term in FRONT-MATTER (HARD). A decision that was
  # REVERSED (e.g. ATECC608B → SE050, SEC.6 2026-06-07) can legitimately survive in
  # the BODY as a documented legacy/reusable pattern — so `deprecated_terms` cannot
  # ban it outright — but it must NOT appear in the doc's FRONT-MATTER (🎯 Мета /
  # ✅ Статус), where only the CURRENT decision belongs. That is exactly how the
  # SE050 migration left 03_05's 🎯 still naming ATECC608B as the current SE — a
  # silent drift the structure-map's 🎯-column surfaced but no per-line gate caught.
  # Scans ONLY the front-matter slice (between the 🎯 Мета and 🔗 Cross-references
  # headings); the body is untouched (legacy pattern is allowed there).
  SUPERSEDED_FRONTMATTER = {
    "ATECC608B" => "SE = SE050 (`03_05 §3.7`, SEC.6); ATECC608B survives only as a legacy provisioning-pattern in the body"
  }.freeze

  SUPERSEDED_FM_EXEMPT = %w[00_06 00_07].freeze

  def superseded_term_in_frontmatter(basename, text)
    return [] if SUPERSEDED_FM_EXEMPT.any? { |prefix| basename.start_with?(prefix) }

    m = text.match(/^##\s*🎯(?<front>.*?)^##\s*🔗/m)
    return [] unless m

    SUPERSEDED_FRONTMATTER.filter_map do |term, hint|
      "superseded term `#{term}` in front-matter (🎯/✅) → #{hint}" if m[:front].include?(term)
    end
  end

  # [SSOT anti-drift] Link label ↔ href doc mismatch (HARD). A cross-ref written
  # `[`NN_NN §X`](NN_NN_Name)` must point at the SAME doc its visible label cites.
  # When the label LEADS with one NN_NN but the href resolves to a different doc,
  # the link silently lies — exactly how 00_06 §4 read "00_06 §2/§4" yet linked the
  # 00_05 file (a renamed-doc residue `docs:check_refs` could not catch, because the
  # href still resolves to a real file). Heuristic: compare the label's FIRST doc-ID
  # token to the href's NN_NN; flag a mismatch. A label with no NN_NN, or whose
  # leading NN_NN equals the target, is fine — later "(див. також NN_NN)" secondary
  # mentions are ignored (only the lead token is authoritative). The NN_NN pattern is
  # digit-bounded so a long number ("2026_05") never matches. Returns
  # ["label `00_06 …` → href 00_05_… (label leads with 00_06, not 00_05)", …].
  LABEL_DOC_RE = /(?<!\d)\d\d_\d\d(?!\d)/

  # Both href FORMS, because the class does not stop at the docs/ boundary: canon
  # pages link wiki-style (`](NN_NN_Name)`), while root files and .github/ link by
  # PATH (`](docs/NN_NN_Name.md)`) — and the path form is where a re-point campaign
  # leaves the lie unseen, since the in-docs loop never reads those files
  # [DOC-T.68 закривна]. Mutation-verified: restoring the GOVERNANCE.md residue
  # (label `docs/00_02` → href docs/00_03_…) turns this RED.
  #
  # 🔴 THIRD href form added 2026-08-15, and its absence is the same self-defeating
  # perimeter as the `.md` hole in `section_ref_after_doclink`: this guard's corpus
  # was widened to `.github/**` + root `*.md`, and a file one directory down can
  # only write `](../docs/NN_NN_Name.md)` — the one form the pattern did not admit.
  # Live proof at the moment of the fix: `.github/pull_request_template.md` carried
  # the label `00_06 §3` over an href to `06_07_…` — the very class this guard
  # exists for, in the very file that sends contributors to read `00_06 §3`, green
  # since the widening. §Guard-craft #51.
  #
  # 🔴 The LABEL is parsed by walking back to the MATCHING `[`, not by `[^\]]*`,
  # and that is a correctness fix rather than a nicety. A character class starting
  # at the FIRST bracket mis-captures two live shapes in opposite directions: a
  # bold prose marker wrapping a real link (`**[`00_07`-прямий + [`00_02 §4.3`](…)]**`)
  # yields a label of foreign text and a FALSE accusation, while a legitimate label
  # carrying nested brackets (`[`05_02 §… [DOC.7]`](…)`) is not seen AT ALL. Both
  # exist in the tree today; measured on the flip: naive widening = 1 false positive,
  # balanced walk-back = 0.
  #
  # ⚠️ DECLARED CEILING: unlike its siblings this guard is NOT fence-aware, so a
  # link inside a ``` block is still inspected. Zero live instances (measured over
  # 4933 files), and the class is illustrative-example-shaped, so it stays named
  # rather than fixed — a skip added without a case to justify it is a blind zone.
  def link_label_target_mismatch(text)
    text.to_enum(:scan, LINK_HREF_RE).filter_map do
      m         = Regexp.last_match
      target_id = m[1]
      label     = balanced_link_label(text, m.begin(0)) or next
      label_id  = label[LABEL_DOC_RE]
      next unless label_id           # label cites no doc-ID → nothing to verify
      next if label_id == target_id  # label leads with the doc it links to → ok

      "label `#{label.strip[0, 48]}` → href #{target_id}_… (label leads with #{label_id}, not #{target_id})"
    end
  end

  # Anchored on `](` so the label is never part of the match — the label is then
  # recovered by bracket-balance (above). Accepts all three written dialects:
  # wiki `](NN_NN_Name)` · path `](docs/NN_NN_Name.md)` · relative `](../docs/…)`.
  LINK_HREF_RE = %r{\]\((?:\.{1,2}/)*(?:docs/)?(\d\d_\d\d)_[A-Za-z0-9_]+(?:\.md)?(?:\#[^)]*)?\)}

  # Walk back from the `]` at `close_idx` to its matching `[`, honouring nesting.
  # Returns nil at a newline (a markdown label never spans lines) or if unbalanced,
  # so an unmatched bracket makes the link INVISIBLE rather than mis-attributed —
  # the safe direction for a guard that accuses.
  def balanced_link_label(text, close_idx)
    depth = 0
    i     = close_idx
    while i >= 0
      case text[i]
      when "]" then depth += 1
      when "[" then (depth -= 1) == 0 and return text[(i + 1)...close_idx]
      when "\n" then return nil
      end
      i -= 1
    end
    nil
  end

  # [SSOT anti-drift] §-section label drift (ADVISORY). Extracted from the inline
  # docs.rake scan (2026-05-30) so it is unit-tested like every other guard. A
  # cross-ref `[`NN_NN §Ref`](NN_NN_Name)` whose visible label cites a section
  # §Ref must have a matching heading in the TARGET doc — catches a section that
  # was renumbered/removed (e.g. 08_02 §1.3 after the registry collapsed its
  # per-publication sub-sections into institution-level §1A/§1B/§2..§5). The
  # canonical ref format (00_06 §1) is `[`NN_NN §X`](NN_NN_DocName)` with §X a
  # REAL section number; a descriptive §-word (e.g. §Web3CircuitBreaker) is
  # non-standard and STAYS flagged so the data gets normalized — the guard stays
  # strict, the refs get standardized (not the other way round). `headings` maps
  # doc-id → its downcased heading lines (so a key's presence ≡ target exists; a
  # missing target is the dangling guard's job, not this one). Refs < 2 chars
  # (bare "§5") and labels citing no §Ref are skipped. Pure: no I/O.
  SECTION_REF_RE = /§\s*([0-9A-Za-zА-Яа-яІіЇїЄє.\-]+)/

  def section_label_drift(text, headings)
    text.scan(/\[([^\]]*)\]\((\d\d_\d\d_[A-Za-z0-9_]+)(?:#[^)]*)?\)/).filter_map do |label, target|
      next unless headings.key?(target) # target doc absent → dangling guard handles it

      ref = label[SECTION_REF_RE, 1]
      next unless ref && ref.length >= 2
      next if headings[target].include?(ref.downcase)

      "label `§#{ref}` → #{target} (no heading contains '#{ref}')"
    end
  end

  # [SSOT anti-drift] Bare section-ref FORMAT guard (HARD). The
  # canonical cross-ref form (00_06 §1) is the full link `[`NN_NN §X`](DocName)`;
  # a *bare* code-span `NN_NN §X` (not wrapped in a link) is both non-standard AND
  # a blind spot — section_label_drift only validates LINKED refs, so a bare `§7.2`
  # that goes stale is never caught. This flags bare code-span refs so they get
  # standardized into links (after which section_label_drift covers their §X).
  # FP-controlled heuristic: a code span whose content STARTS with a doc-id and
  # carries a `§`, NOT preceded by `[` (so a real link's `[`label`]` is excluded).
  # Skips ``` fences. Skips meta-syntactic PLACEHOLDERS (`§NN`/`§N`/`§X`/`§X.Y`/
  # `§x`/`§NN_NN` — illustrative format examples, not refs; their §-token is only
  # [nxy._]). Tables are NOT skipped (unlike the value-drift guards: a table cell
  # legitimately carries a real ref to standardize). Owner/index docs are exempt:
  # 00_00 (index — already all-links), 00_06 (DEFINES the ref FORMAT; its §2/§3
  # registry tables are the bare-by-design home registry), 00_07 (tracker — terse
  # pointers by design, §-resolution is tracker:check's job), legacy appendix.
  # Caller passes basename (sans .md) + text; returns ["bare ref `05_05 §3` …", …].
  BARE_REF_EXEMPT = /\A00_00_|\A00_06_|\A00_07_|_[Aa]ppendix/
  BARE_SECTION_REF_RE = /(?<!\[)`(\d\d_\d\d[^`]*§[^`]*)`/
  PLACEHOLDER_SECTION_RE = /\A[nxy._]+\z/i

  def bare_section_ref(basename, text)
    return [] if basename.match?(BARE_REF_EXEMPT)

    in_fence = false
    text.each_line.flat_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next [] if in_fence

      line.scan(BARE_SECTION_REF_RE).filter_map do |(content)|
        token = content[/§\s*([^\s]+)/, 1]
        next if token && token.match?(PLACEHOLDER_SECTION_RE)

        "bare ref `#{content.strip}` (should be `[`…`](DocName)`) → #{line.strip[0, 90]}"
      end
    end
  end

  # [SSOT anti-drift] Bare DOC-ID format guard (HARD). Sibling of bare_section_ref:
  # that one flags a bare `NN_NN §X` (carries a section); THIS one flags a bare
  # code-span `NN_NN` / `docs/NN_NN` / `NN_NN_FullName` carrying NO section — the
  # whole-doc reference form. Canon (00_06 §1): a doc ref is the link
  # `[`NN_NN`](DocName)`, never a lone code-span (non-clickable + a blind spot).
  # Caught the 213-ref thread-A sweep (2026-05-31, scripts/linkify_bare_refs.rb).
  # Only ids that RESOLVE to a current doc (valid_ids) are flagged, so a *retired*-doc
  # mention (the historical `04_07`, merged into 08_03) is NOT a live ref and stays
  # prose. Skips spans already in a link (preceded by '['), ``` fences. Same exempt
  # set as bare_section_ref + manifest — index / standard-owner / tracker / appendix /
  # manifesto keep their bare-by-design refs. Caller passes basename + text + the Set
  # of valid NN_NN ids. Pure: no I/O.
  BARE_DOC_EXEMPT = /\A00_00_|\A00_06_|\A00_07_|_[Aa]ppendix|\Amanifest/
  BARE_DOC_REF_RE = /(?<!\[)`(?:docs\/)?(\d\d_\d\d)(?:_[A-Za-z0-9_]+)?`/

  def bare_doc_ref(basename, text, valid_ids)
    return [] if basename.match?(BARE_DOC_EXEMPT)

    in_fence = false
    text.each_line.flat_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next [] if in_fence

      line.scan(BARE_DOC_REF_RE).filter_map do |(id)|
        next unless valid_ids.include?(id)

        "bare doc-ref `#{id}` (should be `[`#{id}`](DocName)`) → #{line.strip[0, 90]}"
      end
    end
  end

  # [SSOT anti-drift] Cross-ref label single-form (HARD). Every link to a canon doc
  # must lead with a CODE-SPAN doc-id — the one sanctioned dialect (00_06 §1):
  #   [`NN_NN`](Doc)  ·  [`NN_NN §X`](Doc)  ·  [`NN_NN` — Title](Doc)
  # A plain [NN_NN …](Doc), escaped [NN\_NN\_…](Doc), or full-name-in-codespan
  # [`NN_NN_Full_Name`](Doc) is the SAME ref in a second spelling → flagged (caught
  # 445 such across 50 docs, unified 2026-06-01 via scripts/normalize_crossrefs.rb).
  # A pure prose-phrase label (no doc-id token at all) is a legit descriptive link →
  # left alone. Skips fenced code. Pure: no I/O.
  CANON_LINK_RE = /\[([^\]]*)\]\((\d\d_\d\d)_[A-Za-z0-9_]+(?:#[^)]*)?\)/

  def crossref_label_form(text)
    in_fence = false
    text.each_line.flat_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next [] if in_fence

      line.scan(CANON_LINK_RE).filter_map do |label, id|
        l = label.strip
        next if l =~ /\A`#{id}(\s+§[^`]*)?`/                     # canonical: code-span leads with id (+ opt §)
        next if l !~ /#{id}/ && l !~ /#{id[0, 2]}\\_#{id[3, 2]}/ # prose-phrase (no doc-id) → legit

        "label `#{l[0, 44]}` → #{id}_… (doc-id link must lead with code-span `#{id}`)"
      end
    end
  end

  # [SSOT anti-drift, DOC-T.16] Section-ref AFTER a whole-doc link (HARD). The
  # canonical section ref (00_06 §1) folds the section INTO the link label —
  # `[`NN_NN §X`](DocName)`. A whole-doc (or directory-form) link immediately
  # trailed by a loose `§X` — `[`NN_NN`](DocName) §X` — is that same ref split in
  # two: the §X dangles outside the link (non-clickable) AND is invisible to BOTH
  # sibling guards (`bare_section_ref` needs the doc-id + § in ONE bare code-span;
  # `crossref_label_form` only inspects the label↔href, never the text after `)`).
  # Fold it back. Fires on a link whose label LEADS with a code-span doc-id
  # (`[`NN_NN`…]` or directory `[`NN_NN` — Title]`) followed by optional space +
  # `§token`. The href may be a bare `NN_NN_Name` (top-level canon) OR a relative
  # `../../NN_NN_Name` (the docs/protocols/ subtree references canon by relative
  # path) — both are canon refs, so both are in scope. Filename-label links
  # (`[`SUMMARY.md`](SUMMARY.md)`) are NOT canon NN_NN refs (protocols/ internal
  # convention) → out of scope by design. Skips ``` fences + meta placeholders
  # (`§X`/`§N`). Same exempt set as the bare-ref siblings (index / standard-owner /
  # tracker / appendix). Pure: no I/O.
  #
  # 🔴 `(?:\.md)?` IS LOAD-BEARING, and its absence made the `(?:\.\./)*` beside it
  # DECORATIVE for two months (2026-08-15). The relative branch exists precisely for
  # `docs/protocols/**` — and that subtree writes the extension in EVERY canon href
  # (`](../../NN_NN_Name.md)`), so the group never closed and the guard reached
  # exactly ZERO of the files it was widened for. Measured on flipping it: 8 → 24
  # hits, i.e. **16 real violations** had been invisible since the widening. Same
  # class as the sibling `link_label_target_mismatch`, which was extended to
  # `.github/**` while `.github/` can only write `](../docs/…)` — §Guard-craft #51,
  # twice in one family. Reflex: after widening a gate FOR a tree, open that tree
  # and read one real line — a perimeter extension that cannot match the dialect it
  # was extended for is a decoration that reports coverage.
  SECTION_AFTER_DOCLINK_RE = %r{\[(`\d\d_\d\d[^`]*`[^\]]*)\]\((?:\.\./)*(\d\d_\d\d_[A-Za-z0-9_]+)(?:\.md)?(?:#[^)]*)?\)[ \t]*§[ \t]*(\S+)}

  def section_ref_after_doclink(basename, text)
    return [] if basename.match?(BARE_REF_EXEMPT)

    in_fence = false
    text.each_line.flat_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next [] if in_fence

      line.scan(SECTION_AFTER_DOCLINK_RE).filter_map do |label, target, token|
        next if token.match?(PLACEHOLDER_SECTION_RE)

        id = label[/\d\d_\d\d/]
        "§-after-link `…](#{target}) §#{token[0, 10]}` (fold → `[`#{id} §…`](DocName)`) → #{line.strip[0, 80]}"
      end
    end
  end

  # [SSOT anti-drift] Magic-marker hex self-consistency (HARD, DOC-T.46). Firmware uses
  # 4-byte ASCII magic markers ("RITE"/"LZST"/"KEYL"/"LSED"/"KEYC"/"QUID"…) whose
  # uint32 literal is the byte-packing of the four characters — but the codebase
  # mixes endianness ("RITE"=0x45544952 little-endian vs "LZST"=0x4C5A5354 big-
  # endian), so a hardcoded name→hex table would itself drift. Instead this guard is
  # SELF-VALIDATING + table-free: it inspects only a *definition* — a quoted 4-letter
  # marker immediately (≤24 chars) followed by an ASCII-range hex literal (0x4x/0x5x,
  # the printable-letter byte range, which excludes 0x0803… Flash addresses) — and
  # requires that hex to equal the big- OR little-endian packing of that marker's
  # bytes. A mismatch → a typo'd/stale marker value (the 9cb1d86 drift class). A hex
  # *referenced by value* with no adjacent quoted name (e.g. "DR19 ≠ 0x4C5A5354") is
  # NOT a definition and is left alone, so the guard stays false-positive-free. Pure:
  # no I/O, no table. Scoped to lines mentioning `magic`.
  MAGIC_DEF_RE = /["'`]([A-Z]{4})["'`][^\n]{0,24}?0x([45][0-9A-Fa-f]{7})(?![0-9A-Fa-f])/

  def magic_marker_hex_drift(text)
    text.each_line.flat_map do |line|
      next [] unless line.match?(/magic/i)

      line.scan(MAGIC_DEF_RE).filter_map do |name, hex|
        bs = name.bytes
        valid = [ bs, bs.reverse ].map { |b| b.map { |c| format("%02X", c) }.join }
        next if valid.include?(hex.upcase)

        "magic `\"#{name}\"` = 0x#{hex.upcase} ≠ its BE/LE ASCII → #{line.strip[0, 80]}"
      end
    end
  end

  # [SSOT anti-drift] External doc-path references (HARD). `docs:check_refs` validates
  # links INSIDE docs/, but repo files OUTSIDE docs/ — `.github/`, root README/CLAUDE/
  # AGENTS, AND source trees (bin/lib/app/firmware/contracts/spec code comments) — also
  # reference canon docs by path. A renamed/renumbered doc leaves those stale and the
  # in-docs gate never sees them (exactly how `docs/00_07_GitHub_Projects_and_IaC_Automation`
  # (→ 00_05), `docs/08_07_SEU_…` (→ 08_03) and source `docs/00_08_Action_Plan_Tracker`
  # (→ 00_07) rotted unnoticed — the `.github`/root/source blind spot). The linter + its
  # spec are exempt (they cite stale paths as examples). Flags
  # any `docs/NN_NN_Name` path whose EXACT basename is not a current doc (catches a
  # wrong-number AND a wrong-name residue). `existing` = Set of current doc basenames
  # (sans .md). The trailing `.md` is naturally excluded — `.` ends the char class. A
  # bare `docs/NN_NN` (no `_Name`) is skipped: ambiguous module ref, not a file path.
  # Pure: caller passes path + text + existing.
  EXTERNAL_DOC_PATH_RE = %r{docs/(\d\d_\d\d_[A-Za-z0-9_]+)}

  # [SSOT anti-drift, DOC-T.84 друге плече] Canon names its own honesty-gates BY PATH
  # (`spec/quality/…_spec.rb`), and until 2026-08-23 nothing checked those paths: the
  # ref family only knows `docs/NN_NN_Name`, so renaming a cited gate spec left every
  # gate green while the canon kept promising a guard that no longer answers to that
  # name — proven by mutation, not suspected. Cost of switching this on was measured
  # first: 297 citations across canon + routing layer, ZERO dead.
  #
  # ⚠️ Declared ceiling — `spec/` ONLY, and that is deliberate. The neighbouring genres
  # under `app/`/`firmware/`/`deploy/` are dominated by paths that MUST NOT exist:
  # ❌-marked anti-examples («this component may not live here»), files marked
  # «(планований)», and one that is gitignored by construction. Measured 2026-08-22:
  # 11 dead paths outside `spec/`, essentially all legitimate — a broader rule would be
  # almost pure false positive. `spec/` carries no such genre, which is why it gates.
  CITED_SPEC_PATH_RE = %r{`(spec/[\w./-]*\.rb)`}

  def cited_spec_path_drift(path, text, exists)
    text.each_line.flat_map do |line|
      line.scan(CITED_SPEC_PATH_RE).flatten.reject { |p| exists.call(p) }.map do |p|
        "#{path}: cited spec `#{p}` does not exist — canon promises a guard under a name " \
          "nothing answers to (renamed? deleted? then say so here) → #{line.strip[0, 80]}"
      end
    end
  end

  def external_doc_path_drift(path, text, existing)
    text.each_line.flat_map do |line|
      line.scan(EXTERNAL_DOC_PATH_RE).filter_map do |(base)|
        next if existing.include?(base)

        "#{path}: stale doc path `docs/#{base}` (no current doc)"
      end
    end
  end

  # [OPS.32] Друга вісь тієї самої поверхні: шлях може РЕЗОЛВИТИСЬ, а `#фрагмент`
  # після нього — ні, і тоді читача мовчки викидає на початок сторінки. Найдорожчий
  # споживач саме тут: `deploy/grafana/**` кладе такі URL у `runbook_url`, тобто
  # читає їх ЛЮДИНА в мить інциденту. Виміряно 2026-08-23 по всьому набору
  # `external_files`: фрагмент-рефів у path-формі рівно ЧОТИРИ, усі в `deploy/`,
  # і ТРИ з них були мертві (`#OracleBalance` · `#reserve-gate` · `#SEC10`), а
  # четвертий ніс великі літери там, де слаг GitHub завжди нижнього регістру.
  # Ціна вмикання = нуль хибних позитивів, множина непорожня → живість гейта
  # доводиться мутацією на реальному члені, а не порожнім зеленим.
  #
  # ⚠️ Стеля, названа поіменно — ЩО цей гейт НЕ бачить:
  #   • лише path-форма `docs/NN_NN_Name.md#frag`; внутрішньодокову
  #     `[мітка](DocName#frag)` судить `docs:graph`, і той **advisory за дизайном**
  #     ([`00_06 §Статус`]) — цю асиметрію знято не було й тут вона не змінюється;
  #   • `anchor_set` збирає слаги ЛИШЕ із заголовків, тож явний HTML-якір
  #     (`<a id="…">`) у цілі читатиметься як відсутній — з'явиться такий, гейт
  #     треба вчити, а не послаблювати;
  #   • мертвий сам ДОКУМЕНТ лишається предметом `external_doc_path_drift` вище
  #     (`anchors` його не має → пропускаємо), щоб один гейт не судив двох речей.
  #
  # `anchors` = та сама мапа, що живить `DocsGraph.dangling_anchors` — ключ `NN_NN`,
  # значення Set слагів. Ключуємось на НОМЕР, а не на повний basename, свідомо: ім'я
  # після номера вже судить `external_doc_path_drift`, і дублювати ту вісь тут означало
  # б два вироки на один дефект, з яких другий назве не ту причину.
  EXTERNAL_DOC_ANCHOR_RE = %r{docs/(\d\d_\d\d)(?:_[A-Za-z0-9_]+)\.md\#([^\s"'`)\]]+)}

  def external_doc_anchor_drift(path, text, anchors)
    text.each_line.flat_map do |line|
      line.scan(EXTERNAL_DOC_ANCHOR_RE).filter_map do |(base, frag)|
        known = anchors[base]
        next if known.nil? || known.include?(frag)

        "#{path}: dead anchor `#{base} ##{frag}` — the doc resolves, the heading slug " \
          "does not (a reader following this link lands at the top of the page)"
      end
    end
  end

  # [SSOT anti-drift, DOC-T.15 firmware + DOC-T.17 Ruby + DOC-T.29 class/prose] Volatile
  # source line-refs in three dialects: (1) path-form `*.c`/`*.h`/`*.rb`/`*.rake`/`*.sol`,
  # (2) Ruby-symbol `ClassName:NNN`, (3) Ukrainian-prose `(р.162)`/`(рядок 31)`. A file
  # grows and every `main.c:747` / `BlockchainMintingService:107` / `(рядок 31)` in the
  # docs silently points at the wrong line — exactly the drift the campaign avoids (FW.4's
  # trio once aimed at `DEFAULT_TTL` instead of `Run_Inference`; verified 2026-06-16:
  # `BlockchainMintingService:107`→120, `application.rb (рядок 31)`→41). Cite the stable
  # symbol/`#define`/class/method, not a line number. Scanned over docs/ + .github/ only
  # (source trees legitimately carry path-refs in code comments). NOT fence-skipped — many
  # refs live in `// path:N` comments inside ```c blocks. The `.md`/decimal forms never
  # match the path alternation (requires a literal `.c`/`.h`/`.rb`/`.rake`/`.sol` before
  # the colon); the class form anchors on a `::`-namespace or a Ruby class-suffix so
  # wire-field notation (`Payload:16`, `[DID:4]`) is NOT a false positive. Pure.
  SOURCE_LINE_REF_RE = %r{(?<![\w/])[\w/*.-]+\.(?:[ch]|rb|rake|sol):\d+(?:[–-]\d+)?}
  CLASS_LINE_REF_RE  = /(?<![\w:])[A-Z][A-Za-z0-9]*(?:::[A-Z][A-Za-z0-9]*)+:\d+|(?<![\w:])[A-Z][A-Za-z0-9]*(?:Service|Worker|Controller|Job|Channel|Mailer|Component|Pool):\d+/
  PROSE_LINE_REF_RE  = /\(\s*(?:р|ряд(?:ок|ки))\.?\s*\d+(?:\s*,\s*\d+)*\s*\)/
  # (4) doc-id dialect `NN_NN:line` (stan_audit dig 2026-07-12 caught a live `03_02:9`) —
  # points at a LINE of a canon doc, which moves on every edit; none of the three
  # dialects above matched it. §/heading anchors are the stable form — a `:`-digit
  # tail after a doc-id is never legitimate. Tracker NOT exempt (the ref lived there).
  DOC_LINE_REF_RE = /(?<![\w.:])\d\d_\d\d:\d+\b/

  # 🔴 The illustration exemption is SECTION-scoped, not file-scoped (narrowed
  # 2026-08-22). It used to be `base.start_with?("00_06", "00_07")` — a blanket
  # immunity for two whole files, i.e. exactly the standard and the tracker, the
  # two largest and most consequential documents in the corpus. Measured cost of
  # narrowing: six hits total, five of them legitimate illustrations inside the
  # gate registry and one ARCHIVE row — and one LIVE volatile ref on the hot path
  # (`TelemetryUnpackerService:<line>` inside an open item) that the blanket had
  # hidden. A green run on those two files was therefore never evidence for these
  # dialects. Illustrations legitimately live in exactly two places: the drift-gate
  # registry of the standard, and the tracker's archive — both are declarations
  # ABOUT bad forms; everywhere else in those files a line-ref is a live claim.
  ILLUSTRATION_SECTION_RE = /\A##+\s*(?:🛡️\s*)?3\.\s*Drift-prevention|\A##\s*🗄️/

  def source_line_ref_drift(path, text)
    base = File.basename(path.to_s)
    exempt_file = base.start_with?("00_06", "00_07")
    in_illustration = false
    text.each_line.flat_map do |line|
      if line.start_with?("#")
        in_illustration = exempt_file && line.match?(ILLUSTRATION_SECTION_RE)
      end
      cites_examples = in_illustration
      [
        line[SOURCE_LINE_REF_RE],
        (line[CLASS_LINE_REF_RE] unless cites_examples),
        (line[PROSE_LINE_REF_RE] unless cites_examples),
        (line[DOC_LINE_REF_RE] unless in_illustration && base.start_with?("00_06"))
      ].compact.map do |ref|
        "#{path}: volatile source line-ref `#{ref}` — cite the symbol/#define, not a line → #{line.strip[0, 80]}"
      end
    end
  end

  # [SSOT anti-drift] Canonical source-block pin (HARD) — generalizes the solc /
  # judge-prompt "hash the canonical block, force a re-pin on change" pattern to
  # value-bearing constant blocks that legitimately live in BOTH code (the SSOT) AND
  # doc mirrors (CLAUDE.md, 03_04). solc One-Home FORBIDS the mirror; here the mirror
  # is wanted (pedagogical), so instead we PIN the code block's hash: when the SSOT
  # consts change, check_refs fails until the author reconciles the mirrors and
  # re-pins (`rake docs:repin`). Stays pure (text + names + expected sha in, strings
  # out); the file I/O (read source, read canonical_block_pins.yml) lives in docs.rake.
  #
  # Extract each `NAME = value` definition line (trailing #comment stripped), normalize
  # the value's inner whitespace, hash the sorted `name=value` set. Returns [sha, missing].
  def canonical_block_sha(source_text, const_names)
    missing = []
    pairs = const_names.filter_map do |name|
      m = source_text.match(/^\s*#{Regexp.escape(name)}\s*=\s*(.+?)\s*(?:#.*)?$/)
      next (missing << name) && nil unless m

      "#{name}=#{m[1].gsub(/\s+/, ' ').strip}"
    end
    [ Digest::SHA256.hexdigest(pairs.sort.join("\n")), missing ]
  end

  # Compare a source block's live hash to its pinned hash; returns drift strings.
  # A renamed/removed const reports separately (the sha comparison would be vacuous).
  def canonical_block_drift(key, source_basename, source_text, const_names, expected_sha)
    sha, missing = canonical_block_sha(source_text, const_names)
    unless missing.empty?
      return [ "#{key}: pinned const(s) absent in #{source_basename} → #{missing.join(', ')} (renamed? update canonical_block_pins.yml + `rake docs:repin`)" ]
    end
    return [] if sha == expected_sha

    [ "#{key}: canonical block in #{source_basename} changed (#{sha[0, 12]}… ≠ pinned #{(expected_sha.to_s.empty? ? '(unpinned)' : expected_sha[0, 12])}…) — reconcile the mirrors in canonical_block_pins.yml, then `rake docs:repin`" ]
  end

  # [SSOT anti-drift] Code-fence parity (HARD, DOC-T.45). The fence-skip logic in ~9
  # DocsLinter methods + DocsToc is a single `in_fence = !in_fence if line.start_with?` on
  # a ``` prefix: an ODD number of fence markers (one opened, never closed) leaves that
  # toggle stuck `true` to EOF, so every downstream `next if in_fence` silently swallows the
  # rest of the file — one unclosed fence disables EVERY fence-aware guard at once AND
  # truncates the auto-ToC (DocsToc.content_headings drops the trailing headings). This is
  # the structural invariant that keeps that toggle honest, so it MUST count fences by the
  # EXACT predicate the guards use — a line starting with three backticks (a bare or
  # info-string fence toggles; a `~~~` tilde fence and an indented / inline fence do not —
  # mirror the guards, not CommonMark). Deterministic (an unclosed fence always breaks the
  # render), so there is NO owner exemption and NO legit odd-fence doc — every markdown file
  # must balance. Reports the line where the still-open fence began. Pure: no I/O.
  FENCE_PREFIX = "```"

  def unbalanced_code_fences(text)
    open_line = nil
    lineno = 0
    text.each_line do |line|
      lineno += 1
      next unless line.start_with?(FENCE_PREFIX)

      open_line = open_line ? nil : lineno
    end
    return [] unless open_line

    [ "unclosed #{FENCE_PREFIX} code fence opened at line #{open_line} — odd fence count " \
      "desyncs every fence-aware guard (in_fence toggle stuck) + truncates the ToC" ]
  end

  # [SSOT anti-drift, DOC-T.68 фаза 0] Every doc NUMBER named in an owner/exempt
  # constant must still resolve to a real doc.
  #
  # WHY this is its own guard: the owner-only-vocabulary gates above grant immunity by
  # NUMBER PREFIX (`\A05_03_`, `\A00_04_`, …), and a number is not a stable identity —
  # it can be freed and later re-populated by an unrelated page. When that happens the
  # stale entry hands the previous occupant's immunity to whatever lands there next: the
  # new page may restate the mint rate, name an AI vendor or carry a retired term, and
  # nothing objects. That is the third, quietest face of the reference-gate family —
  # renaming empties a gate's input, re-use re-points citations, and an inherited
  # exemption is a permission NOBODY GRANTED (`ssot-maintenance` §Guard-craft #50).
  #
  # The number set is collected from the CONSTANTS THEMSELVES — never from a
  # hand-written roster, which would be a second home for the same fact and would rot
  # exactly like the thing it guards. A constant naming no `NN_NN` contributes nothing
  # (`TL_CHAIN_HASH_EXEMPT` matches prose; `THERMAL_STRESS_OWNER_DOC` matches a report
  # basename), so the sweep is safe over the whole family. Returns number → [const names].
  #
  # 🔴 The suffix list is the lantern's OWN blind spot, and it was measured on 2026-08-22:
  # four `*_MIRROR_RE` constants name a doc number literally and were invisible here, so
  # renaming that doc broke them TWO ways at once and neither was loud — legitimate lines
  # citing the NEW number lost their immunity, while the dead old number stayed in the
  # regex granting immunity to anything that happened to mention it, forever. Widening the
  # list to include them cost NOTHING: 7 more constants, exactly one new number key, and
  # zero false positives, because the real filter is the `\d\d_\d\d` scan on the VALUE —
  # the name filter does no protective work at all today (removing it entirely measured
  # identical). It is kept narrow only so a future detector-regex that merely *mentions* a
  # number in an error string does not silently join the owner family.
  #
  # ⛔ TWO CEILINGS THIS GATE HAS AND CANNOT CLOSE — do not read a green run as coverage:
  # (1) `constants` here resolves to the constants of THIS FILE, not the process. Every
  #     doc-number-keyed constant in `scripts/*.rb`, `lib/tracker/dashboard.rb` and
  #     `lib/docs_graph.rb` is structurally out of reach; no suffix widens into them.
  #     Most break loudly (`Errno::ENOENT` on a path), but the regex-shaped ones do not.
  # (2) The Hash branch below reads KEYS only by design, so a number living in a Hash
  #     VALUE (`DEPRECATED_TERMS`, `SUPERSEDED_FRONTMATTER`) is invisible on purpose and
  #     stays invisible. Their numbers must be swept by hand on any renumber.
  # Mirror of this ceiling in prose: `00_06 §3`, row "exemption subject".
  EXEMPTION_CONST_RE = /_(?:OWNER_DOC|EXEMPT|HOMES|MIRROR_RE|META_DOC|DRIFT)\z/

  def number_keyed_exemptions
    constants.grep(EXEMPTION_CONST_RE).each_with_object({}) do |name, out|
      value = const_get(name)
      # A Hash is read by its KEYS only — its values are human labels, and a label that
      # happened to mention a doc number would invent a subject that grants nothing.
      # Everything else (Regexp source, Array of ids) stringifies without that risk, so
      # there is no third branch: a `case` arm nobody can reach is untestable by
      # construction, and an unreachable arm is deleted, never covered.
      text = value.is_a?(Hash) ? value.keys.join(" ") : value.to_s
      text.scan(/\d\d_\d\d/).uniq.each { |num| (out[num] ||= []) << name.to_s }
    end
  end
end
