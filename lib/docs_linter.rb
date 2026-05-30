# frozen_string_literal: true

# [SSOT anti-drift] Pure-function structural lints for docs/*.md (00_06).
# No Rails, no file I/O — each method takes file *text* and returns an array of
# human-readable violation strings, so it is unit-tested
# (spec/lib/docs_linter_spec.rb) and reused from lib/tasks/docs.rake
# (rake docs:check_refs). Mirrors the lib/tracker/dashboard.rb engine pattern.
module DocsLinter
  module_function

  # TRL matrix single-value (HARD; scope: 00_03 §1 canonical matrix).
  # Per-module cells must be a single integer 1-9, never a range ("5-6"/"8-9")
  # — 00_05 §1.1: Current TRL is single-select. Only rows whose first cell is
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

  # Blockers live in 00_07, not canon (decided 2026-05-29). Canon docs must not
  # host a blocker SECTION — neither open ("🛑 Блокери", "🛑 Відкриті Блокери")
  # nor a resolved-archive ("✅ Архів", "✅ Закриті Блокери (PR #…)"). ALL blockers
  # (open + closed) live in 00_07 (open → §module, closed → §🗄️ Архів); canon keeps
  # the design/constraint as body prose. Heuristic: a `## ` heading bearing a status
  # emoji (🛑/✅/🟢/🟡/🔴) together with a blocker/archive word. Returns the offending
  # headings. Lines inside ``` fenced blocks are skipped, so a skeleton *example*
  # (e.g. 00_06 §1) is not a false positive. (Caller exempts 00_07.)
  STATUS_EMOJI = "🛑✅🟢🟡🔴"

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
  # legacy appendix files (02_06 / *_appendix_*). Caller passes basename (sans .md)
  # + text; returns the missing element names so a CI gate keeps the tree from regressing.
  CONFORMANCE_EXEMPT = /\A00_00_|\A00_07_|\A02_06_|_appendix_/

  def conformance_violations(basename, text)
    return [] unless basename.match?(/\A\d\d_\d\d_/)
    return [] if basename.match?(CONFORMANCE_EXEMPT)

    miss = []
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

  # [SSOT anti-drift] Lorenz constants (σ=10 / ρ=28 / β=8÷3, dt, iterations) are
  # SSOT-owned by 03_04 §4.1 (firmware↔backend mirror). Re-declaring the formula
  # values elsewhere drifts — exactly how 05_01 §2 + 00_01 §5 carried a stale
  # σ/ρ/β code block until the 2026-05-30 05/07 restructure. Other docs must
  # REFERENCE 03_04 §4.1, never re-state. Heuristic: a β *assignment*
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

      "Lorenz β `8.0/3.0` re-stated outside owner (03_04 §4.1) → #{line.strip[0, 100]}"
    end
  end

  # [SSOT anti-drift] Deprecated-term registry. Tokens retired SSOT-wide must
  # not reappear in any canon doc; as each drift is fixed, the old form is added
  # here so CI blocks its return (the general "scripts catch drift" net). Keyed
  # deprecated-token → replacement hint. Use only for UNAMBIGUOUS retired strings
  # (no legit current/historical use), else this false-positives.
  DEPRECATED_TERMS = {
    "silkennet-v1-aes256" => 'use "silken-aes-128-lora-key" / "silken-aes-256-device-key" (ARCH.42 256→128 HKDF info)'
  }.freeze

  def deprecated_terms(text)
    DEPRECATED_TERMS.filter_map do |term, hint|
      "deprecated term `#{term}` present → #{hint}" if text.include?(term)
    end
  end

  # [SSOT anti-drift] Link label ↔ href doc mismatch (HARD). A cross-ref written
  # `[`NN_NN §X`](NN_NN_Name)` must point at the SAME doc its visible label cites.
  # When the label LEADS with one NN_NN but the href resolves to a different doc,
  # the link silently lies — exactly how 00_02 §3 read "00_06 §2/§4" yet linked the
  # 00_05 file (a renamed-doc residue `docs:check_refs` could not catch, because the
  # href still resolves to a real file). Heuristic: compare the label's FIRST doc-ID
  # token to the href's NN_NN; flag a mismatch. A label with no NN_NN, or whose
  # leading NN_NN equals the target, is fine — later "(див. також NN_NN)" secondary
  # mentions are ignored (only the lead token is authoritative). The NN_NN pattern is
  # digit-bounded so a long number ("2026_05") never matches. Returns
  # ["label `00_06 …` → href 00_05_… (label leads with 00_06, not 00_05)", …].
  LABEL_DOC_RE = /(?<!\d)\d\d_\d\d(?!\d)/

  def link_label_target_mismatch(text)
    text.scan(/\[([^\]]*)\]\((\d\d_\d\d)_[A-Za-z0-9_]+(?:#[^)]*)?\)/).filter_map do |label, target_id|
      label_id = label[LABEL_DOC_RE]
      next unless label_id           # label cites no doc-ID → nothing to verify
      next if label_id == target_id  # label leads with the doc it links to → ok

      "label `#{label.strip[0, 48]}` → href #{target_id}_… (label leads with #{label_id}, not #{target_id})"
    end
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

  # [SSOT anti-drift] Magic-marker hex self-consistency (ADVISORY). Firmware uses
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
end
