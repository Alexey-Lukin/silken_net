#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Solidity signature-arity gate (DOC-T.89).
#
# `contracts/*.sol` is the code-SSOT of every on-chain function and event; the
# canon RESTATES those signatures — in `05_03` (the declared home: §Функції,
# §Події, the «Повна Матриця», the mint-flow diagram and a copy of the
# subgraph.yaml event block) and, as a short «Ключові функції» summary for a
# different module's reader, in `05_01`. Both mirrors are WANTED — the same
# judgement the canonical-pin engine records for the Lorenz block — so the
# answer is not to delete them but to pin them.
#
# What rotted, and why nothing went red: E.60 Фаза 1б added `bytes32 archiveRoot`
# to `mint`/`mintForTree`/`_mintSCC`/`batchMint` and to the `CarbonMinted` /
# `ForestMinted` events, symmetrically on SCC and SFC, and updated
# `subgraph.yaml`. The canon kept the four-parameter form in twenty places, and
# the «Повна Матриця» went on certifying ✅ against a signature that neither the
# contract nor the subgraph uses — a document attesting to itself. Every
# reference gate stayed green because a reference gate judges whether a link
# resolves, never whether a sentence about the target is still true. The
# canonical-pin engine cannot reach this class either: it extracts `NAME = value`
# definitions, so it sees constants and is blind to parameter lists by
# construction. That is the hole this script fills.
#
# ── The axis: ARITY, and only arity ─────────────────────────────────────────
# The corpus spells one signature in four dialects — Solidity source
# (`function mint(address to, uint256 amount, …)`), the ABI/topic form
# (`CarbonMinted(indexed address,uint256,…)`), a NatSpec-ish table cell
# (`CarbonMinted(address indexed investor, …)`) and a bare heading. A gate keyed
# on the TEXT would know only the spellings its author happened to meet
# (§Guard-craft #75). Arity is the one property all four dialects agree on, and
# it is exactly what the drift moved (4 → 5). So the gate compares a number, not
# a string, and is dialect-proof by construction rather than by enumeration.
#
# ── ⛔ Declared ceiling — what a green run does NOT say ──────────────────────
#   * TYPES, ORDER, NAMES and MODIFIERS are unchecked. A doc that renames
#     `treeDid` → `did`, reorders two parameters, or drops `indexed` passes.
#     Those are cheaper drifts and they read as wrong to a human; a missing
#     parameter does not.
#   * A symbol declared in BOTH tokens (`mint`, `batchMint`, `slash`, `_update`,
#     `pause`) is judged against the UNION of the declared arities, because a
#     doc line carries no attribution to one contract. So an ASYMMETRIC change —
#     SCC grows a parameter, SFC does not — is invisible here. The symmetry that
#     makes the union safe today is a property of E.60, not an invariant; if the
#     two tokens ever diverge, this ceiling is the thing to revisit first.
#   * Shorthand (`mint(bytes32)`, `batchMint(+bytes32)`) is deliberately OUT of
#     scope: it names the CHANGE, not the signature, and admitting it would put
#     the gate's precision at 27% (measured — 8 of 11 hits outside the two homes
#     were shorthand or a Ruby-call diagram). Two discriminators buy that back:
#     a candidate needs ≥2 top-level parameters, and no `:` — Solidity parameter
#     lists never contain one, Ruby kwarg diagrams always do.
#   * 🔴 An argument list written with NAMES ONLY — a CALL rather than a
#     declaration, e.g. the mint-flow diagram's `mint(to, amount, treeDid)` — is
#     invisible here, because it carries no type token and the type token is the
#     single discriminator holding precision at 100%. Two such lines existed in
#     `05_03` at the time this gate was written and were fixed BY HAND. So a
#     green run is not a statement about call-shaped prose: when a signature
#     changes, grep the flow diagrams too. Widening the gate to cover them was
#     measured and refused — dropping the type-token requirement admits every
#     Ruby/JS call named `mint(` in the corpus.
#
# ── Perimeter ───────────────────────────────────────────────────────────────
# ALL of `docs/**/*.md`, not a named allow-list. Measured before enabling: 44
# candidates corpus-wide, 20 of them drifted, and after the two discriminators
# ZERO false positives — so the wide perimeter is free, and it catches the next
# restatement wherever someone writes it. `docs/**` and `contracts/**` are both
# already inside the `changes:` filter of docs.yml; without that this gate would
# be decorative (§Guard-craft #1).
#
# Victory here is NOT an empty set (§Guard-craft #61): 24 legitimate
# restatements must keep matching, and that live population is what proves the
# gate is still looking. It prints the green count for exactly that reason — a
# candidate count that silently falls to zero means the extraction broke, not
# that the corpus got clean.
#
# Mutation-verified ×3, and the first attempt is worth recording because it
# FAILED to discriminate for two separate reasons, both instructive:
#   (1) mutating `mintForTree` proved nothing — that symbol appears in the canon
#       only as a bare `mintForTree()` mention, i.e. it is not in the set this
#       gate judges, and a no-op mutation is indistinguishable from a blind gate;
#   (2) mutating `mint` in ONE contract also stayed green — `mint` is declared in
#       both tokens, so the union ceiling above swallowed it. That is not a bug
#       found during verification; it is the declared ceiling demonstrating
#       itself, and it is the strongest argument for re-reading this header the
#       day SCC and SFC stop changing symmetrically.
# The three that DO discriminate: a parameter removed SYMMETRICALLY from both
# contracts (reds 6 named doc sites), a parameter removed from ONE doc line
# (reds exactly that line), and a broken `DECL` regex (aborts loudly — it must
# never report a clean tree on an empty truth set). Files restored byte-identical
# after each. There is no spec for this script; this header is the only record.

require "pathname"

ROOT = Pathname.new(File.expand_path("..", __dir__))
CONTRACTS_GLOB = "contracts/*.sol"
DOCS_GLOB = "docs/**/*.md"

# A parameter list is a candidate only if it looks like Solidity.
TYPE_TOKEN = /\b(?:address|uint\d*|int\d*|bytes\d*|string|bool)\b/
MIN_PARAMS = 2

# Top-level `function` / `event` declarations are indented exactly four spaces in
# every contract here (contract-body scope). Nested/interface declarations are
# deliberately out of the truth set — the canon restates the deployable surface.
DECL = /^\s{4}(?:function|event)\s+(\w+)\s*\(/

# Slice the balanced parenthesis run starting at `open_idx`. A naive `[^)]*`
# truncates `keccak256(bytes(treeDid))` and reports a WRONG arity, which is the
# failure that would make this gate's own numbers untrustworthy.
def balanced_inner(str, open_idx)
  depth = 0
  idx = open_idx
  while idx < str.length
    case str[idx]
    when "(" then depth += 1
    when ")"
      depth -= 1
      return str[(open_idx + 1)...idx] if depth.zero?
    end
    idx += 1
  end
  nil
end

# Split on commas at nesting depth 0 — `string[] calldata treeDids` and
# `mapping(a => b) x` must each stay ONE parameter.
def split_top_level(inner)
  depth = 0
  parts = [ +"" ]
  inner.each_char do |char|
    case char
    when "(", "[" then depth += 1
      parts.last << char
    when ")", "]" then depth -= 1
      parts.last << char
    when ","
      depth.zero? ? parts << +"" : parts.last << char
    else parts.last << char
    end
  end
  parts.map(&:strip).reject(&:empty?)
end

def declared_arities
  truth = {}
  Dir.chdir(ROOT) { Dir[CONTRACTS_GLOB].sort }.each do |rel|
    source = (ROOT + rel).read
    source.scan(DECL) do
      name = Regexp.last_match(1)
      open_idx = source.index("(", Regexp.last_match.begin(1))
      inner = balanced_inner(source, open_idx)
      next unless inner

      (truth[name] ||= []) << split_top_level(inner).size
    end
  end
  truth.transform_values(&:uniq)
end

def scan_docs(truth)
  candidates = 0
  violations = []
  Dir.chdir(ROOT) { Dir[DOCS_GLOB].sort }.each do |rel|
    (ROOT + rel).each_line.with_index(1) do |line, lineno|
      truth.each_key do |name|
        pos = 0
        while (found = line.index(/(?<![\w.])#{Regexp.escape(name)}\s*\(/, pos))
          open_idx = line.index("(", found)
          inner = balanced_inner(line, open_idx)
          pos = open_idx + 1
          next unless inner
          next unless inner.match?(TYPE_TOKEN)
          next if inner.include?(":") # Ruby kwarg diagram, not a Solidity list

          params = split_top_level(inner)
          next if params.size < MIN_PARAMS # shorthand `mint(bytes32)` — see ceiling

          candidates += 1
          next if truth[name].include?(params.size)

          violations << [ rel, lineno, name, params.size, truth[name], line.strip ]
        end
      end
    end
  end
  [ candidates, violations ]
end

truth = declared_arities
if truth.empty?
  warn "❌ solidity_signature_arity: НУЛЬ декларацій витягнуто з #{CONTRACTS_GLOB} — " \
       "зламана екстракція, не чисте дерево. Перевір DECL-регекс."
  exit 1
end

candidates, violations = scan_docs(truth)

if violations.empty?
  puts "✅ Solidity signature arity: #{candidates} переказів сигнатур у docs/ — усі несуть " \
       "арність контракту (#{truth.size} символів у джерелі)."
  exit 0
end

warn "❌ Solidity signature arity — #{violations.size} із #{candidates} переказів розійшлись із contracts/*.sol:"
violations.each do |rel, lineno, name, actual, expected, text|
  warn "   #{rel}:#{lineno}  #{name}: #{actual} параметр(и) ≠ #{expected.join('/')} у контракті"
  warn "        #{text[0, 150]}"
end
warn ""
warn "   Лік: звірити переказ із декларацією в contracts/*.sol (ДЖЕРЕЛО), не навпаки."
warn "   Гейт судить ЛИШЕ арність — типи/порядок/імена лишаються на очах ревʼюера."
exit 1
