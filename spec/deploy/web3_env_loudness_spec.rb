# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "kamal"

# INF.12 behavior-half (canon-promise). The declaration spec (env_fetch_declaration_spec)
# proves a code-fetched var REACHES runtime on every deploy surface; THIS spec proves the
# var's failure-LOUDNESS is deliberately classified — because "declared" says nothing
# about behavior: DAO_TREASURY_ADDRESS passed the declaration set-diff while its
# read-sites swallowed the config bug under RPC-rescue umbrellas (Dynamic Tax silently
# off, the log lying "RPC degraded"). The 06_04 §2.1 canon promise («fail-loud on use
# поки не задані» + the boot-guard exceptions) becomes a machine set-diff:
#
#   every web3-family ENV on the deploy surface ∈ exactly one of
#     GUARD — a Web3NetworkGuard boot-set member (boot-refuse in prod/strict);
#     LOUD  — unset raises past every rescue on its real read-site;
#     SOFT  — nil-safe skip by design, documented in 06_04.
#
# A new web3-looking var landing in config/deploy.yml stays RED until classified here
# deliberately — the silent-class (a rescue umbrella masking a misconfig as an
# operational state) cannot recur unnoticed.
#
# Ceiling (deliberate): LOUD/SOFT rationales are verified by READING the read-site
# (2026-07-12), not asserted at runtime — interprocedural rescue-flow can't be pinned
# statically. Re-verify the rationale when a read-site moves; the guard-set half IS
# machine-live (membership pinned below + unit-tested in web3_network_guard_spec).
RSpec.describe "Web3 ENV loudness classification (INF.12 behavior-half)" do # rubocop:disable RSpec/DescribeClass
  # Family filter: prefixes and suffixes that mark a chain/money var on the deploy surface.
  let(:web3_family) do
    /\A(?:ORACLE_|SOLANA_|CELO_|ETHEREUM_|ALCHEMY_|POLYGON_|WEB3_|DAO_)|_CONTRACT(?:_ADDRESS)?\z|_RPC_URL\z/
  end

  let(:declared) do
    text = File.read(Rails.root.join("config/deploy.yml"))
    (text.scan(/^\s+-\s*([A-Z][A-Z0-9_]{2,})\s*$/) + text.scan(/^\s+([A-Z][A-Z0-9_]{2,}):/))
      .flatten.uniq.grep(web3_family)
  end

  let(:guard_sets) do
    g = Security::Web3NetworkGuard
    g::RPC_URL_ENVS + g::RPC_FALLBACK_URL_ENVS + g::ORACLE_KEY_ENVS + g::SIGNER_KEYS.values +
      g::SILENT_ADDRESS_ENVS.keys + g::SILENT_RPC_ENVS.keys + g::SOLANA_SIGNER_ENVS + [ g::CHAIN_ENV_VAR ]
  end

  # Unset raises past every rescue on the real read-site (verified by reading 2026-07-12;
  # the worker layer re-raises → Sidekiq retry → DeadSet, visible).
  let(:loud) do
    {
      "CELO_CUSD_CONTRACT_ADDRESS"           => "Celo::CommunityRewardService ENV.fetch outside rescue; CeloRewardWorker re-raises",
      "KLIMA_RETIREMENT_CONTRACT"            => "KlimaDao::RetirementService ENV.fetch outside rescue; worker re-raises",
      "ETHERISC_DIP_CONTRACT_ADDRESS"        => "Etherisc::ClaimService ENV.fetch outside rescue; InsurancePayoutWorker re-raises",
      "PURO_EARTH_REGISTRY_CONTRACT_ADDRESS" => "PuroEarth::PassportService ENV.fetch outside rescue (registry metadata read is separately nil-safe by design)"
    }
  end

  # Nil-safe skip by design — documented in 06_04 §2.1.
  let(:soft) do
    {
      "WEB3_STRICT_MODE"                     => "boolean mode flag; prod enforces the gates regardless (belt-and-suspenders, INF.11)",
      "PROTOCOL_PARAMETERS_CONTRACT_ADDRESS" => "ENV[] nil-safe → ParameterSyncWorker self-skips until the governance deploy (GOV.1)"
    }
  end

  it "classifies every deployed web3-family var (guard boot-set, documented-LOUD, or documented-SOFT)" do
    unclassified = declared - guard_sets - loud.keys - soft.keys
    expect(unclassified).to be_empty,
                            "unclassified web3 ENV on the deploy surface — add it to a Web3NetworkGuard " \
                            "boot-set OR document it as LOUD/SOFT here (deliberately): #{unclassified.join(', ')}"
  end

  it "keeps the LOUD/SOFT lists live (no entries orphaned off the deploy surface)" do
    orphaned = (loud.keys + soft.keys) - declared
    expect(orphaned).to be_empty,
                        "classified but no longer declared in config/deploy.yml: #{orphaned.join(', ')}"
  end

  it "keeps the classes disjoint (one var, one loudness story)" do
    aggregate_failures do
      expect(guard_sets & (loud.keys + soft.keys)).to be_empty
      expect(loud.keys & soft.keys).to be_empty
    end
  end

  # Silent narrowing of a boot-set would demote a gated var to unclassified-nothing without
  # failing the guard's own unit spec — pin the membership explicitly.
  it "pins the Web3NetworkGuard boot-set membership (no silent narrowing)" do
    g = Security::Web3NetworkGuard
    aggregate_failures do
      expect(g::SILENT_ADDRESS_ENVS.keys)
        .to match_array(%w[DAO_TREASURY_ADDRESS CARBON_COIN_CONTRACT_ADDRESS FOREST_COIN_CONTRACT_ADDRESS ETHEREUM_ANCHOR_CONTRACT])
      # [INF.27 Q1] The silent-RPC sister set. A second member is a real decision (which
      # read-site swallows its absence?), so the membership is pinned by NAME, not by count.
      expect(g::SILENT_RPC_ENVS.keys).to eq(%w[ALCHEMY_POLYGON_RPC_URL])
      # [INF.27 move (2)] The overlay `.kamal/secrets.canopy` remaps exactly the guard's RPC
      # set from CANOPY_* twins; `deploy_secret_scan` judges the FORM of each remap, this
      # pins that the two lists are the SAME list (the script is stdlib and cannot read here).
      expect(g::RPC_URL_ENVS)
        .to match_array(%w[ALCHEMY_ETHEREUM_RPC_URL ALCHEMY_POLYGON_RPC_URL CELO_RPC_URL SOLANA_RPC_URL])
      expect(g::SOLANA_SIGNER_ENVS)
        .to match_array(%w[SOLANA_WALLET_KEYPAIR SOLANA_FEE_PAYER_PUBKEY SOLANA_FEE_PAYER_TOKEN_ACCOUNT
                           SOLANA_USDC_MINT_ADDRESS])
      expect(g::SIGNER_KEYS.values).to match_array(%w[ORACLE_MINTER_PRIVATE_KEY ORACLE_SLASHER_PRIVATE_KEY])
      # [OPS.37] The chain-family axis is GUARD-class, not SOFT: unlike WEB3_STRICT_MODE
      # (whose absence prod compensates for), an unrecognised value here REFUSES the boot.
      expect(g::CHAIN_ENV_VAR).to eq("WEB3_CHAIN_ENV")
      expect(g::CHAIN_ENVS).to match_array(%w[mainnet testnet])
      expect(g::DEFAULT_CHAIN_ENV).to eq("mainnet")
      expect(g::RPC_URL_ENVS).to include("CELO_RPC_URL", "SOLANA_RPC_URL", "ALCHEMY_POLYGON_RPC_URL")
      expect(g::ORACLE_KEY_ENVS)
        .to include("ORACLE_MINTER_PRIVATE_KEY", "ORACLE_SLASHER_PRIVATE_KEY", "ETHEREUM_ANCHOR_PRIVATE_KEY")
    end
  end

  # [INF.27] The guard against the LIVE manifests, resolved the way Kamal resolves them, per
  # process class. Every example above judges the guard's SETS; none judged what the guard
  # would SAY about the container we actually ship — and the two disagreed twice in one day
  # (2026-09-01): the dormant `coap` role refused its boot on inherited address placeholders
  # it never reads, and canopy could not be raised until its addresses were real. Resolving
  # `role.env(host).clear` through `Kamal::Configuration` is what turned both from prose into
  # a verdict; the secret half (`env.secret`) is deliberately NOT resolved here — its values
  # live in CI shell/GitHub Secrets and are judged by `env_fetch_declaration_spec`.
  #
  # 🔒 Declared ceiling: `env.clear` only — a testnet slot on a MAINNET RPC is invisible to
  # these examples (the `[chain]` axis needs the secret values), and so is a wrong-but-
  # well-formed address (EIP-55 sees a typo, never a wrong chain). The canopy example is the
  # machine witness of the runbook order "Фаза 2t before Фаза 3": it was RED on 2026-09-01.
  describe "the guard against the live manifests, per process class [INF.27]" do
    def role_clear(destination, role)
      cfg = Kamal::Configuration.create_from(config_file: Rails.root.join("config/deploy.yml"),
                                             destination: destination)
      r = cfg.role(role)
      r.env(r.primary_host).clear
    ensure
      ENV.delete("KAMAL_DESTINATION") # `create_from` sets it as a side effect
    end

    def guard = Security::Web3NetworkGuard

    it "lets the dormant coap role boot past the address placeholders it inherits (format scoped like presence, Q3)" do
      violations = guard.violations(role_clear(nil, "coap"), signer_process: false, web_process: false)
      expect(violations.grep(/\[address\]/)).to be_empty
    end

    it "declares canopy a TESTNET slot whose web container carries no address placeholder (Фаза 2t before Фаза 3)" do
      clear = role_clear("canopy", "web")
      expect(guard.chain_env(clear)).to eq("testnet")
      expect(guard.violations(clear, signer_process: false, web_process: true).grep(/\[address\]/)).to be_empty
    end

    # Era-stable by construction: the expectation is derived from the manifest's VALUES, so
    # it reads "only still-placeholder vars are refused, and every web-scoped placeholder IS
    # refused" — true today with SCC still a placeholder on production, true the day Фаза 2
    # fills it (both sides become empty), and RED the day a mispasted real address slips in.
    it "keeps production declared MAINNET, and its web verdict names exactly the web-scoped placeholders" do
      clear = role_clear(nil, "web")
      expect(guard.chain_env(clear)).to eq("mainnet")
      refused = guard.violations(clear, signer_process: false, web_process: true)
                     .grep(/\[address\]/).map { |m| m[/\[address\] ([A-Z0-9_]+)/, 1] }
      expected = guard::SILENT_ADDRESS_ENVS.select { |var, spec| spec[:web] && clear[var] == "REQUIRED_SECRET_NOT_SET" }.keys
      expect(refused).to match_array(expected)
    end

    it "resolves non-empty role envs (the parser is not judging an empty hash)" do
      aggregate_failures do
        expect(role_clear(nil, "coap").size).to be > 10
        expect(role_clear("canopy", "web")["DEPLOYMENT_SLOT"]).to eq("canopy")
        expect(role_clear(nil, "web")["DEPLOYMENT_SLOT"]).to eq("production")
      end
    end
  end
end
