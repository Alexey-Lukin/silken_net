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

  # [SSOT anti-drift] Tokenomics / carbon RATE One-Home (HARD after the 2026-05-31
  # dedup). The mint rate (`10,000 growth_points = 1 SCC`) and carbon rate
  # (`2000 SCC = 1 tCO₂`) are governance-CHANGEABLE parameters (05_06), so they get
  # ONE home: 05_03 (technical) + 07_01 §3 (business view). Re-stating the VALUE
  # elsewhere drifts the instant governance re-prices — exactly the silent dup found
  # across 8 docs (00_01/04_01/05_01/05_02/05_06/07_01 body/03_03). Other docs must
  # REFERENCE the home, never restate the number. Exempt: 05_03 + 07_01 (homes),
  # 07_02 (a labelled "дзеркало SSOT" ROI calc), 00_07 (tracker archive), manifest
  # (the standalone manifesto). A line that itself references the home or is a
  # labelled mirror is not flagged — same shape as lorenz_formula_drift.
  RATE_OWNER_DOC     = /\A05_03_|\A07_01_|\A07_02_|\A00_07_|\Amanifest/
  TOKENOMICS_RATE_RE = /10[ .,]?000[^\n]{0,30}=\s*1\s*SCC/i
  CARBON_RATE_RE     = /2[ .,]?000\s*SCC\s*=\s*1\s*[тt]/i
  RATE_MIRROR_RE     = /дзеркал|mirror|05_03|07_01|ProtocolParameters|SystemParameter/i

  def tokenomics_rate_drift(basename, text)
    return [] if basename.match?(RATE_OWNER_DOC)

    text.each_line.filter_map do |line|
      next if line.match?(RATE_MIRROR_RE)

      if line.match?(TOKENOMICS_RATE_RE)
        "mint rate `10,000 gp = 1 SCC` re-stated outside home (05_03 / 07_01 §3) → #{line.strip[0, 90]}"
      elsif line.match?(CARBON_RATE_RE)
        "carbon rate `2000 SCC = 1 tCO₂` re-stated outside home (05_03 / 07_01 §3) → #{line.strip[0, 90]}"
      end
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
  # 02_06 (legacy-appendix home), 00_06 (this standard cites them as examples),
  # 00_07 (tracker may reference an old baseline in a "migrate-from" note).
  DEPRECATED_TERMS = {
    "silkennet-v1-aes256" => 'use "silken-aes-128-lora-key" / "silken-aes-256-device-key" (ARCH.42 256→128 HKDF info)',
    "ZP-3" => "retired ∅27mm through-hole piezo SKU → SMD piezo (Murata 7BB-15-6L0 / TDK B-Series), canon 02_01 §3",
    "ZP-5" => "retired ∅27mm through-hole piezo SKU → SMD piezo (Murata 7BB-15-6L0 / TDK B-Series), canon 02_01 §3"
  }.freeze

  DEPRECATED_EXEMPT = %w[02_06 00_06 00_07].freeze

  def deprecated_terms(basename, text)
    return [] if DEPRECATED_EXEMPT.any? { |prefix| basename.start_with?(prefix) }

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

  # [SSOT anti-drift] Bare section-ref FORMAT guard (ADVISORY → HARD). The
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
  BARE_REF_EXEMPT = /\A00_00_|\A00_06_|\A00_07_|\A02_06_|_appendix_/
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
  BARE_DOC_EXEMPT = /\A00_00_|\A00_06_|\A00_07_|\A02_06_|_appendix_|\Amanifest/
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

  # [SSOT anti-drift] External doc-path references (HARD). `docs:check_refs` validates
  # links INSIDE docs/, but repo files OUTSIDE docs/ — `.github/` (workflows + configs +
  # copilot/labels) and root README/CLAUDE/AGENTS — also reference canon docs by path.
  # A renamed/renumbered doc leaves those stale and the in-docs gate never sees them
  # (exactly how `docs/00_07_GitHub_Projects_and_IaC_Automation` (→ 00_05) and
  # `docs/08_07_SEU_…` (→ 08_03) rotted unnoticed — a `.github/`/root blind spot). Flags
  # any `docs/NN_NN_Name` path whose EXACT basename is not a current doc (catches a
  # wrong-number AND a wrong-name residue). `existing` = Set of current doc basenames
  # (sans .md). The trailing `.md` is naturally excluded — `.` ends the char class. A
  # bare `docs/NN_NN` (no `_Name`) is skipped: ambiguous module ref, not a file path.
  # Pure: caller passes path + text + existing.
  EXTERNAL_DOC_PATH_RE = %r{docs/(\d\d_\d\d_[A-Za-z0-9_]+)}

  def external_doc_path_drift(path, text, existing)
    text.each_line.flat_map do |line|
      line.scan(EXTERNAL_DOC_PATH_RE).filter_map do |(base)|
        next if existing.include?(base)

        "#{path}: stale doc path `docs/#{base}` (no current doc)"
      end
    end
  end
end
