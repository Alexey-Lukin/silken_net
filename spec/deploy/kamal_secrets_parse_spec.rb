# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "kamal"

# The two committed secrets files, read by the parser that actually reads them in a deploy:
# `Kamal::Secrets` (Dotenv + Kamal's inline command substitution). Until 2026-09-02 every
# gate over these files judged their TEXT — `deploy_secret_scan` blessed the "loud
# placeholder" form `${TWIN:-MARKER}` on 2026-08-31 and again on 2026-09-02 — and the first
# canopy boot showed what the parser made of it: Dotenv's variable regex accepts `${NAME`
# and stops at the `:`, so the container received `<value>:-MARKER}` (Puma's before_fork
# raised URI::InvalidURIError on the real Upstash URL) and, through the same shape in
# secrets-common, a RAILS_MASTER_KEY of `<key>:-}` — present, non-empty, wrong, invisible
# to every presence check. A file another program parses is judged by THAT program or not
# at all (`ssot-maintenance` guard-craft #117); this spec is that judgement.
#
# 🔒 Declared ceiling: values are resolved with a controlled ENV, so this proves the FORM
# of every line, not the operator's values. No example touches config/master.key any more —
# the RAILS_MASTER_KEY line left secrets-common on 2026-09-02 (SEC.22 Phase-2), and the
# example below is the ratchet that keeps it out.
RSpec.describe "Kamal secrets files through Kamal's own parser [B4 / INF.27]" do # rubocop:disable RSpec/DescribeClass
  let(:remaps) do
    {
      "REDIS_URL"                => "CANOPY_REDIS_URL",
      "ALCHEMY_POLYGON_RPC_URL"  => "CANOPY_ALCHEMY_POLYGON_RPC_URL",
      "ALCHEMY_ETHEREUM_RPC_URL" => "CANOPY_ALCHEMY_ETHEREUM_RPC_URL",
      "SOLANA_RPC_URL"           => "CANOPY_SOLANA_RPC_URL",
      "CELO_RPC_URL"             => "CANOPY_CELO_RPC_URL",
      # [OPS.37 ⚖️ 2026-09-02] the testnet signer set behind canopy's own job role, plus the
      # Devnet fee-payer's public identifiers — same overlay, same parser, same two verdicts.
      "ORACLE_MINTER_PRIVATE_KEY"      => "CANOPY_ORACLE_MINTER_PRIVATE_KEY",
      "ORACLE_SLASHER_PRIVATE_KEY"     => "CANOPY_ORACLE_SLASHER_PRIVATE_KEY",
      "ORACLE_CELO_PRIVATE_KEY"        => "CANOPY_ORACLE_CELO_PRIVATE_KEY",
      "ETHEREUM_ANCHOR_PRIVATE_KEY"    => "CANOPY_ETHEREUM_ANCHOR_PRIVATE_KEY",
      "SOLANA_WALLET_KEYPAIR"          => "CANOPY_SOLANA_WALLET_KEYPAIR",
      "SOLANA_FEE_PAYER_PUBKEY"        => "CANOPY_SOLANA_FEE_PAYER_PUBKEY",
      "SOLANA_FEE_PAYER_TOKEN_ACCOUNT" => "CANOPY_SOLANA_FEE_PAYER_TOKEN_ACCOUNT",
      "SOLANA_USDC_MINT_ADDRESS"       => "CANOPY_SOLANA_USDC_MINT_ADDRESS"
    }
  end

  # Every ENV name the two files reference, so "unset" is unset and not "whatever the
  # developer's shell happens to carry".
  let(:referenced) { remaps.values + %w[RAILS_MASTER_KEY SECRET_KEY_BASE GCP_ARTIFACT_REGISTRY_KEY] }

  def with_env(overrides)
    saved = ENV.to_h
    referenced.each { |k| ENV.delete(k) }
    overrides.each { |k, v| ENV[k] = v }
    Dir.chdir(Rails.root) { yield }
  ensure
    ENV.replace(saved)
  end

  def canopy = Kamal::Secrets.new(destination: "canopy")
  def production = Kamal::Secrets.new

  it "resolves every canopy remap to its CANOPY_* twin when the twin is set" do
    set = remaps.values.to_h { |twin| [ twin, "sentinel://#{twin.downcase}" ] }
    with_env(set) do
      s = canopy
      aggregate_failures do
        remaps.each { |name, twin| expect(s[name]).to eq("sentinel://#{twin.downcase}") }
      end
    end
  end

  it "resolves every canopy remap to its LOUD marker when the twin is unset (never a production value)" do
    with_env({}) do
      s = canopy
      aggregate_failures do
        remaps.each { |name, twin| expect(s[name]).to eq("#{twin}_NOT_SET") }
      end
    end
  end

  # [SEC.22 Phase-2, 2026-09-02] The master key travels on NEITHER leg any more: the image
  # ships no credentials.yml.enc, so it decrypted nothing in any container, and the vault
  # holds only `secret_key_base` (its own secret). A re-added line is the runtime vault
  # dependency the latch exists to dissolve — this pin is the ratchet, and it runs with the
  # key PRESENT in the deploying shell so that «not shipped» is a property of the files.
  it "ships no RAILS_MASTER_KEY on either leg even when the deploying shell carries one (SEC.22 Phase-2)" do
    with_env("RAILS_MASTER_KEY" => "0123456789abcdef0123456789abcdef", "SECRET_KEY_BASE" => "skb") do
      aggregate_failures do
        expect(canopy.to_h).not_to have_key("RAILS_MASTER_KEY")
        expect(production.to_h).not_to have_key("RAILS_MASTER_KEY")
        expect(production["SECRET_KEY_BASE"]).to eq("skb")
      end
    end
  end

  # The corruption tell, over EVERY value both legs would ship: no bash-default residue.
  it "ships no value carrying Dotenv's `:-` residue on either leg" do
    set = remaps.values.to_h { |twin| [ twin, "sentinel://#{twin.downcase}" ] }
    with_env(set.merge("SECRET_KEY_BASE" => "skb", "GCP_ARTIFACT_REGISTRY_KEY" => "tok")) do
      aggregate_failures do
        { canopy: canopy.to_h, production: production.to_h }.each do |leg, values|
          bad = values.select { |_, v| v.include?(":-") || v.end_with?("}") }
          expect(bad).to be_empty, "#{leg}: Dotenv-mangled value(s): #{bad.keys.join(', ')}"
          expect(values.size).to be > 3, "#{leg}: parsed only #{values.size} secrets — the files did not load"
        end
      end
    end
  end
end
