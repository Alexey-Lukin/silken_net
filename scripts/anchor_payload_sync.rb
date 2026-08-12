#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Anchor payload-composition gate (ARCH.97).
#
# `EthereumAnchor.aggregate_payload` builds ONE pipe-joined string that becomes
# `leaf0` of the weekly Ethereum L1 state root. Its field composition — WHICH
# fields and IN WHAT ORDER — is mirrored in six places, and the mirror is what
# rots: E.53/E.54 added two fields and left the contract's NatSpec describing a
# 3-field formula for months. A stale mirror here is not cosmetic, because the
# document IS the instruction an external auditor follows to reproduce the hash:
# a wrong field order makes «anyone can verify this» false while every hash the
# backend produces stays internally consistent, so nothing ever goes red.
#
# ── CHECK A — composition parity (order-sensitive) ──────────────────────────
# Source of truth = the method itself: kwargs of the signature ∪ the order of
# `#{…}` slots in the returned string. Those two are compared to EACH OTHER
# first — a kwarg accepted and never interpolated is a field the caller believes
# it anchored and did not (silent evidence loss, the worst direction).
#
# ── CHECK B — SCALE parity ──────────────────────────────────────────────────
# Every decimal column of the payload must be `numeric(30,6)`, because the
# SOURCES (`wallets.balance`, `blockchain_transactions.amount`) are `(24,6)`:
# generate hashes the UNROUNDED value while verify recomputes from the STORED
# column, so a narrower column makes an HONEST anchor fail its own verification.
# This axis is here rather than in a spec because it is what actually leaked:
# the scale fix landed on two of three fields, the third stayed `(30,4)` for
# half a day, protected not by an invariant but by the COINCIDENCE that mint
# writes whole `tokens_to_mint`. Coincidence broke on the insurance tract
# (`payout_amount` is a bare `numeric`). Two axes, declared separately —
# §Guard-craft #8: a gate owning one axis over a surface launders the others.
#
# ── CEILING (declared, per §Guard-craft #3) ─────────────────────────────────
# • Sees only the PIPE form. The kwarg form (`create!(total_growth_points:, …)`,
#   the return hash) was measured and deliberately EXCLUDED: it enumerates
#   COLUMNS, not the hashed string — it legitimately carries `state_root` and
#   legitimately orders fields differently. Including it produced a confident
#   false positive on the first run.
# • A segment that is not a canonical field NAME is checked POSITIONALLY only.
#   Real mirrors quote the service's LOCAL variables (`timestamp`,
#   `latest_chain_hash`) and method suffixes (`anchored_at.iso8601`); the gate
#   judges that such a segment sits in the right SLOT, never what it holds.
#   Consequence, stated plainly: renaming `chain_hash` to something wrong INSIDE
#   a doc example is invisible here.
# • Prose describing the payload in words does not exist for this gate.
# • Judges COMPOSITION and ORDER, never APPROPRIATENESS — a field that should
#   not be anchored at all passes, as long as all mirrors agree on it.
# • CHECK B judges the DECLARED scale in `db/structure.sql`, not the live DB.
# • A mirror that stops matching the extraction ABORTS as a dead-mirror
#   tripwire, never passes vacuously (§Guard-craft #10 — announcing failure and
#   exiting 0 is worse than silence, because it asserts health).
#
# Mutation-verified ×5, each class in isolation with a revert between: a field
# dropped from the NatSpec (the literal E.53/E.54 defect) · two fields swapped in
# the canon home · a column scale lowered to `(30,4)` · a kwarg accepted without
# an interpolation slot · a mirror's form erased entirely (must ABORT, not pass).
# Base and post-revert runs both exit 0. There is no spec for this script; this
# header is the only record that the proof was done.
#
# Pure Ruby, stdlib only, no Rails boot (UI.1 — every `docs_check` step must run
# without the app). Run: `ruby scripts/anchor_payload_sync.rb`
# Exit 0 = in sync; exit 1 = drift. Method/why → docs/00_06 §3.

ROOT  = File.expand_path("..", __dir__)
MODEL = File.join(ROOT, "app/models/ethereum_anchor.rb")

# Mirrors: every file that spells the composition out. A file listed here MUST
# yield at least one parsed sequence, or the gate aborts — that is the whole
# point of naming them rather than globbing.
MIRRORS = {
  "docs/05_04_Ethereum_L1_State_Anchor.md" => "канон-дім формули",
  "docs/05_01_Multichain_Architecture.md"  => "дзеркало §4",
  "docs/04_01_Data_Models_and_Entities.md" => "картка EthereumAnchor",
  "docs/04_02_Business_Logic_and_Services.md" => "картка StateAnchorService",
  "contracts/StateRootAnchor.sol"          => "NatSpec контракту"
}.freeze

errors = []

# ── Source of truth ──────────────────────────────────────────────────────────
model = File.read(MODEL)

sig = model[/def self\.aggregate_payload\((.*?)\)\s*$/m, 1] or
  abort("anchor_payload_sync: сигнатуру `aggregate_payload` не розпарсено (форма змінилась?)")
kwargs = sig.scan(/(\w+):/).flatten

body = model[/def self\.aggregate_payload\(.*?\)\s*\n(.*?)\n  end/m, 1] or
  abort("anchor_payload_sync: тіло `aggregate_payload` не розпарсено (форма змінилась?)")
slots = body.scan(/\#\{(\w+)/).flatten
abort("anchor_payload_sync: у тілі `aggregate_payload` нема `\#{…}`-слотів (форма змінилась?)") if slots.empty?

# A kwarg accepted but never interpolated = evidence the caller believes it
# anchored and did not. Compared as SETS here (order is CHECK A's business).
if kwargs.sort != slots.sort
  (kwargs - slots).each do |k|
    errors << "`#{k}` приймається як kwarg `aggregate_payload`, але НЕ потрапляє в рядок — " \
              "викликач вважає поле заякореним, а воно не хешується (тиха втрата доказу)"
  end
  (slots - kwargs).each do |s|
    errors << "`#{s}` інтерполюється в payload, але не оголошений kwarg'ом — " \
              "значення приїде з зовнішньої змінної/методу, а не з аргументу"
  end
end

CANON = slots # порядок у РЯДКУ, не в сигнатурі: хешується саме він

# ── Extraction ───────────────────────────────────────────────────────────────
# Normalisation must survive all four spellings measured in the corpus:
#   1. `"#{a}|#{b}|…"`                      (Ruby, docs code-fence)
#   2. `"#{a}|#{b}|" \` + continuation line (Ruby line-continuation)
#   3. `a | b | …` split across two NatSpec ` * ` lines
#   4. `a \| b \| …`                        (inside a markdown TABLE cell)
def normalise(text)
  text
    .gsub(/\\\n\s*/, "")        # Ruby line-continuation
    .gsub(/\n\s*\*\s*/, " ")    # NatSpec ` * ` prefix on a wrapped line
    .gsub("\\|", "|")           # escaped pipe inside a markdown table cell
    .gsub(/[\#{}"]/, "")        # interpolation punctuation
end

# A composition claim = ≥3 pipe-joined identifier segments where at least two
# are canonical field names. Below that it is prose, not a claim about the hash.
# Each segment keeps only its BASE name (`anchored_at.iso8601` → `anchored_at`);
# a non-canonical base stays as-is and is judged by POSITION alone.
def pipe_sequences(text, canon)
  text.scan(/[a-z_][\w.]*(?:\s*\|\s*[a-z_][\w.]*){2,}/)
      .map { |hit| hit.split("|").map { |seg| seg.strip.split(".").first } }
      .select { |seq| (seq & canon).size >= 2 }
end

# ── CHECK A — every mirror agrees on composition AND order ───────────────────
MIRRORS.each do |rel, label|
  path = File.join(ROOT, rel)
  abort("anchor_payload_sync: дзеркало #{rel} не існує (перейменовано?)") unless File.exist?(path)

  text = normalise(File.read(path))
  seqs = pipe_sequences(text, CANON)

  if seqs.empty?
    abort("anchor_payload_sync: у #{rel} (#{label}) не знайдено ЖОДНОЇ послідовності полів payload'а — " \
          "форма дзеркала змінилась, гейт осліп (dead-mirror tripwire, не тихий пропуск)")
  end

  seqs.uniq.each do |seq|
    detail = []

    if seq.size != CANON.size
      detail << "полів #{seq.size}, а формула має #{CANON.size} (#{seq.join('|')})"
    else
      # Позиційна звірка: канонічне ім'я мусить стояти у СВОЄМУ слоті;
      # неканонічний сегмент = локальна змінна прикладу, судимо лише місце.
      CANON.each_with_index do |field, i|
        next if seq[i] == field
        next unless CANON.include?(seq[i]) || seq.include?(field)

        detail << "слот #{i + 1} несе `#{seq[i]}`, а формула — `#{field}`"
      end
    end

    next if detail.empty?

    errors << "#{rel} (#{label}): склад payload'а розходиться з `aggregate_payload` — #{detail.join('; ')}. " \
              "Зовнішній аудитор, що йде за цим документом, відтворить ІНШИЙ хеш"
  end
end

# ── CHECK B — decimal columns of the payload carry the SOURCE scale ──────────
structure = File.read(File.join(ROOT, "db/structure.sql"))
anchors_ddl = structure[/CREATE TABLE public\.ethereum_anchors \((.*?)^\);/m, 1] or
  abort("anchor_payload_sync: DDL `ethereum_anchors` не розпарсено у structure.sql (форма змінилась?)")

decimal_cols = anchors_ddl.scan(/^\s*(\w+)\s+numeric\((\d+),(\d+)\)/)
abort("anchor_payload_sync: у DDL `ethereum_anchors` нема numeric-колонок (форма змінилась?)") if decimal_cols.empty?

decimal_cols.each do |name, precision, scale|
  next unless CANON.include?(name)
  next if scale.to_i >= 6

  errors << "колонка `ethereum_anchors.#{name}` = numeric(#{precision},#{scale}), а джерела доказових " \
            "величин — numeric(24,6): generate хешує НЕокруглене, verify читає ОКРУГЛЕНЕ → " \
            "`verify_state_root` віддає false для ЧЕСНОГО якоря (ARCH.97, `05_04 §3`)"
end

if errors.empty?
  puts "✅ anchor_payload_sync: склад payload'а (#{CANON.size} полів) і шкали узгоджені " \
       "у #{MIRRORS.size} дзеркалах + DDL"
  exit 0
end

warn "❌ anchor_payload_sync: розходження складу/шкали payload'а L1-якоря"
errors.each { |e| warn "   • #{e}" }
exit 1
