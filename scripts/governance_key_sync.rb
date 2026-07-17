#!/usr/bin/env ruby
# frozen_string_literal: true

# Governance-key sync gate (GOV.2).
#
# The ProtocolParameters.sol ⟷ Governance::ParameterSyncWorker bridge rests
# ENTIRELY on `solidity_keccak256(param_key.to_s)` — a match of the string NAME.
# Nothing pinned it. Three silent-failure classes:
#
#   1. a KEY_* added on-chain with no Ruby entry → the DAO votes on a parameter
#      the backend never reads (governance no-op, CI green);
#   2. a key renamed in Solidity → the Ruby keccak targets a dead slot → the
#      parameter silently falls back to its hardcoded default (e.g. slash_gamma
#      back to 1.3 despite the vote);
#   3. a Lorenz key MOVED from DCI_LOCKED_KEYS into PARAMETER_MAP → governance
#      gains the lever to break device↔server parity (FW.7) — precisely the
#      catastrophe the tripwire exists to prevent.
#
# Class 3 is why the two sets are compared SEPARATELY rather than as a union:
# a move leaves the union unchanged, so a union check would stay green through
# the one failure the gate was built for.
#
# Canon pin: "8 Lorenz-ключів" (05_06 §7) — a structural DCI invariant. The
# economic count is deliberately NOT pinned: it grows legitimately as the
# protocol adds parameters, and a volatile counter would flag every honest
# addition as drift until someone silences the gate.
#
# Pure Ruby (stdlib only — the worker pulls in `eth` + ApplicationWeb3Worker,
# so the Ruby side is regex-scanned, not required). A pattern that stops
# matching aborts as a dead-mirror tripwire rather than passing vacuously. Run:
#   ruby scripts/governance_key_sync.rb
# Exit 0 = in sync; exit 1 = drift. Method/why → docs/00_06 §3.

ROOT     = File.expand_path("..", __dir__)
SOLIDITY = File.join(ROOT, "contracts/ProtocolParameters.sol")
WORKER   = File.join(ROOT, "app/workers/governance/parameter_sync_worker.rb")
CANON    = File.join(ROOT, "docs/05_06_Governance_and_DAO.md")

errors = []

# ── Solidity: the KEY_* well-known constants (GOVERNANCE_ROLE is a role, not a
#    parameter — the KEY_ prefix is what separates them) ──────────────────────
sol_pairs = File.read(SOLIDITY)
             .scan(/bytes32\s+public\s+constant\s+(KEY_\w+)\s*=\s*keccak256\("([^"]+)"\)/)
abort("governance_key_sync: жодної `KEY_* = keccak256(\"…\")` константи у ProtocolParameters.sol (форма змінилась?)") if sol_pairs.empty?

sol_lorenz = sol_pairs.select { |const, _| const.start_with?("KEY_LORENZ_") }.map { |_, k| k.to_sym }.sort
sol_econ   = sol_pairs.reject { |const, _| const.start_with?("KEY_LORENZ_") }.map { |_, k| k.to_sym }.sort

# ── Ruby: PARAMETER_MAP (synced) + DCI_LOCKED_KEYS (tripwire-only) ───────────
worker = File.read(WORKER)

param_block = worker[/PARAMETER_MAP\s*=\s*\{(.*?)^\s*\}\.freeze/m, 1] or
  abort("governance_key_sync: PARAMETER_MAP не розпарсився у parameter_sync_worker.rb (форма змінилась?)")
param_keys = param_block.scan(/^\s*(\w+):\s*\{/).flatten.map(&:to_sym).sort

dci_block = worker[/DCI_LOCKED_KEYS\s*=\s*%i\[(.*?)\]\.freeze/m, 1] or
  abort("governance_key_sync: DCI_LOCKED_KEYS не розпарсився у parameter_sync_worker.rb (форма змінилась?)")
dci_keys = dci_block.split.map(&:to_sym).sort

# ── 1. Lorenz half: KEY_LORENZ_* ⟷ DCI_LOCKED_KEYS ──────────────────────────
if sol_lorenz != dci_keys
  (sol_lorenz - dci_keys).each do |k|
    errors << "`#{k}` оголошений KEY_LORENZ_* on-chain, але НЕ в DCI_LOCKED_KEYS — " \
              "governance дістає важіль ламати device↔server parity (FW.7)"
  end
  (dci_keys - sol_lorenz).each do |k|
    errors << "DCI_LOCKED_KEYS тримає `#{k}`, якого нема серед KEY_LORENZ_* у Solidity — мертвий tripwire-запис"
  end
end

# ── 2. Economic half: the rest of KEY_* ⟷ PARAMETER_MAP ─────────────────────
if sol_econ != param_keys
  (sol_econ - param_keys).each do |k|
    errors << "`#{k}` оголошений on-chain, але НЕ в PARAMETER_MAP — " \
              "DAO голосує за параметр, який бекенд ніколи не читає (governance-no-op)"
  end
  (param_keys - sol_econ).each do |k|
    errors << if sol_lorenz.include?(k)
                "PARAMETER_MAP синкає `#{k}`, а on-chain це KEY_LORENZ_* — " \
                "Lorenz-константа мусить лишатись DCI-locked (FW.7), не синкатись"
    else
                "PARAMETER_MAP синкає `#{k}`, якого нема в ProtocolParameters.sol — " \
                "keccak цілить у мертвий слот → тихий відкат на хардкод-дефолт"
    end
  end
end

# ── 3. Canon pin: 05_06 §7 declares the DCI-locked count + names them ───────
canon_decl = File.read(CANON).match(/\*\*(\d+) Lorenz-ключів = DCI-locked\*\*\s*\(([^)]+)\)/) or
  abort("governance_key_sync: 05_06 §7 більше не декларує «N Lorenz-ключів = DCI-locked (…)» (форма змінилась?)")
declared = canon_decl[1].to_i
listed   = canon_decl[2].split("/").map(&:strip)

errors << "05_06 §7 декларує #{declared} Lorenz-ключів, DCI_LOCKED_KEYS тримає #{dci_keys.size}" if declared != dci_keys.size
errors << "05_06 §7 декларує #{declared} Lorenz-ключів, а перелічує #{listed.size}: #{listed.inspect}" if listed.size != declared

# ── report ──────────────────────────────────────────────────────────────────
if errors.empty?
  puts "governance_key_sync ✓ — ProtocolParameters.sol ⟷ ParameterSyncWorker " \
       "(#{sol_econ.size} економічних синкаються, #{dci_keys.size} Lorenz DCI-locked ⟷ 05_06 §7)"
  exit 0
else
  warn "governance_key_sync ✗ — governance-key drift (GOV.2):"
  errors.each { |e| warn "  · #{e}" }
  exit 1
end
