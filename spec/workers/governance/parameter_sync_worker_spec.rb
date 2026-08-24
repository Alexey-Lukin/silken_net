# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Governance::ParameterSyncWorker, type: :worker do
  describe "sidekiq_options" do
    it "uses the web3_low queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_low")
    end

    it "has retry set to 3" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end

    it "has unique_for set to 24 hours to match daily cron" do
      expect(described_class.sidekiq_options["unique_for"]).to eq(24.hours)
    end
  end

  describe "module inclusion" do
    it "includes ApplicationWeb3Worker" do
      expect(described_class.ancestors).to include(ApplicationWeb3Worker)
    end
  end

  describe "PARAMETER_MAP" do
    it "defines 9 economic parameters" do
      expect(described_class::PARAMETER_MAP.size).to eq(9)
    end

    it "includes tokenomics parameters" do
      tokenomics_keys = described_class::PARAMETER_MAP.select { |_, v| v[:category] == "tokenomics" }.keys
      expect(tokenomics_keys).to contain_exactly(
        :emission_threshold, :scc_per_tonne_co2, :scc_fallback_price_usd
      )
    end

    it "keeps dynamic_tax_rate and insurance_pool_threshold in their seeded categories" do
      expect(described_class::PARAMETER_MAP[:dynamic_tax_rate])
        .to include(value_type: "decimal", category: "minting")
      expect(described_class::PARAMETER_MAP[:insurance_pool_threshold])
        .to include(value_type: "integer", category: "insurance")
    end

    it "includes slashing parameters" do
      alerts_keys = described_class::PARAMETER_MAP.select { |_, v| v[:category] == "alerts" }.keys
      expect(alerts_keys).to contain_exactly(
        :slash_threshold, :stress_threshold, :slash_gamma, :slash_penalty_factor_max
      )
    end

    # [E.64 §7] «Z alone never slashes»: stress_threshold floor мусить лишатись ВИЩИМ за
    # Z-anomaly base_stress (0.6, insight_generator_service.rb:337) — інакше DAO-vote у
    # (0.6, floor] дав би Z-anomaly (0.6) перетнути поріг → slash на одному Z. Structural guard.
    it "keeps stress_threshold floor above Z-anomaly base_stress 0.6 (§7 «Z alone never slashes»)" do
      z_anomaly_base_stress = 0.6 # insight_generator_service.rb#calculate_stress_index_heuristic
      expect(described_class::PARAMETER_MAP[:stress_threshold][:min]).to be > z_anomaly_base_stress
    end

    it "contains NO Lorenz keys (DCI-locked, GOV.1)" do
      expect(described_class::PARAMETER_MAP.keys.grep(/lorenz/)).to be_empty
    end

    it "has valid value_types for all parameters" do
      described_class::PARAMETER_MAP.each do |key, config|
        expect(config[:value_type]).to be_in(%w[integer float decimal string boolean json]),
          "#{key} has invalid value_type: #{config[:value_type]}"
      end
    end

    it "has valid categories for all parameters" do
      described_class::PARAMETER_MAP.each do |key, config|
        expect(config[:category]).to be_in(SystemParameter::CATEGORIES),
          "#{key} has invalid category: #{config[:category]}"
      end
    end

    it "has sane bounds (min < max) for all parameters" do
      described_class::PARAMETER_MAP.each do |key, config|
        expect(config[:min]).to be < config[:max], "#{key} has min >= max"
      end
    end
  end

  describe "DCI_LOCKED_KEYS" do
    it "lists all 8 firmware-parity Lorenz keys" do
      expect(described_class::DCI_LOCKED_KEYS).to contain_exactly(
        :lorenz_sigma, :lorenz_rho, :lorenz_beta, :lorenz_dt,
        :lorenz_iterations, :lorenz_z_min, :lorenz_z_max, :lorenz_z_target
      )
    end

    it "does not overlap with the synced PARAMETER_MAP" do
      expect(described_class::DCI_LOCKED_KEYS & described_class::PARAMETER_MAP.keys).to be_empty
    end
  end

  describe "FIXED_POINT_DIVISOR" do
    it "equals 1e18 as BigDecimal" do
      expect(described_class::FIXED_POINT_DIVISOR).to eq(BigDecimal("1000000000000000000"))
    end
  end

  describe "#perform" do
    let(:worker) { described_class.new }
    let(:mock_client) { instance_double(Eth::Client) }
    let(:mock_contract) { instance_double(Eth::Contract) }
    let(:contract_address) { "0x" + "ab" * 20 }

    before do
      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
      allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
      allow(SilkenNet::Metrics::RPC_ERRORS_TOTAL).to receive(:increment)
      allow(SilkenNet::Metrics::GOVERNANCE_PARAM_REJECTED_TOTAL).to receive(:increment)
    end

    context "when PROTOCOL_PARAMETERS_CONTRACT_ADDRESS is not set" do
      before { allow(ENV).to receive(:[]).and_call_original }

      it "skips sync and logs info" do
        allow(ENV).to receive(:[]).with("PROTOCOL_PARAMETERS_CONTRACT_ADDRESS").and_return(nil)
        allow(ENV).to receive(:fetch).and_call_original

        allow(Rails.logger).to receive(:info).with(/Skipping sync/)
        allow(Web3::RpcConnectionPool).to receive(:client_for)

        worker.perform

        expect(Rails.logger).to have_received(:info).with(/Skipping sync/)
        expect(Web3::RpcConnectionPool).not_to have_received(:client_for)
      end
    end

    context "when contract address is configured" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("PROTOCOL_PARAMETERS_CONTRACT_ADDRESS").and_return(contract_address)
        allow(ENV).to receive(:fetch).and_call_original
      end

      it "creates Eth::Contract with correct ABI" do
        stub_all_parameters_unset

        worker.perform

        expect(Eth::Contract).to have_received(:from_abi).with(
          name: "ProtocolParameters",
          address: contract_address,
          abi: described_class::CONTRACT_ABI
        )
      end

      it "connects to Polygon RPC" do
        stub_all_parameters_unset

        worker.perform

        expect(Web3::RpcConnectionPool).to have_received(:client_for).with("ALCHEMY_POLYGON_RPC_URL")
      end

      context "when no parameters are set on-chain" do
        before { stub_all_parameters_unset }

        it "skips all parameters" do
          allow(Rails.logger).to receive(:info)
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).not_to have_received(:set)

          expect(Rails.logger).to have_received(:info).with(/9 skipped/)
        end
      end

      context "when a parameter is set on-chain" do
        before do
          stub_all_parameters_unset
          # Override: slash_gamma is set on-chain with value 1.5 (1.5e18)
          stub_parameter_set(:slash_gamma, 1_500_000_000_000_000_000)
        end

        it "updates SystemParameter with governance source and bounds" do
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).to have_received(:set).with(
            :slash_gamma,
            anything,
            hash_including(source: "governance", value_type: "float", category: "alerts",
                           min_value: 1.0, max_value: 3.0)
          )
        end

        it "converts 18-decimal fixed-point to Ruby float" do
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).to have_received(:set).with(
            :slash_gamma,
            "1.5",
            anything
          )
        end

        it "logs the update" do
          allow(SystemParameter).to receive(:set)
          allow(Rails.logger).to receive(:info)

          worker.perform

          expect(Rails.logger).to have_received(:info).with(/Updated slash_gamma/)
          expect(Rails.logger).to have_received(:info).with(/1 updated/)
        end
      end

      context "when on-chain value matches current SystemParameter" do
        before do
          create(:system_parameter, key: "slash_threshold", value: "0.2",
                                    value_type: "float", category: "alerts")
          stub_all_parameters_unset
          # Set on-chain value to 0.2 (matches current)
          stub_parameter_set(:slash_threshold, 200_000_000_000_000_000)
        end

        it "skips the parameter (no update)" do
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).not_to have_received(:set)
        end
      end

      context "when integer parameter is set on-chain" do
        before do
          stub_all_parameters_unset
          # emission_threshold = 10000 stored as 10000e18
          stub_parameter_set(:emission_threshold, 10_000_000_000_000_000_000_000)
        end

        it "converts to integer correctly" do
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).to have_received(:set).with(
            :emission_threshold,
            "10000",
            hash_including(value_type: "integer", category: "tokenomics")
          )
        end
      end

      context "when an on-chain value is outside the safety bounds" do
        before do
          stub_all_parameters_unset
          # dynamic_tax_rate = 2.0 (200%!) — the 18-decimals mis-scale class; max is 0.10
          stub_parameter_set(:dynamic_tax_rate, 2_000_000_000_000_000_000)
        end

        it "rejects the value and keeps no record" do
          allow(Rails.logger).to receive(:error)
          allow(Rails.logger).to receive(:info)

          worker.perform

          expect(Rails.logger).to have_received(:error).with(/REJECTED dynamic_tax_rate/)
          expect(SystemParameter.find_by(key: "dynamic_tax_rate")).to be_nil
          expect(Rails.logger).to have_received(:info).with(/1 rejected/)
        end

        it "keeps the previous value when the record already exists" do
          create(:system_parameter, :dynamic_tax_rate) # value 0.02, bounds 0..0.10

          worker.perform

          expect(SystemParameter.find_by(key: "dynamic_tax_rate").value).to eq("0.02")
        end

        it "increments the rejected-parameters metric" do
          allow(SilkenNet::Metrics::GOVERNANCE_PARAM_REJECTED_TOTAL)
            .to receive(:increment).with(labels: { parameter: "dynamic_tax_rate" })

          worker.perform

          expect(SilkenNet::Metrics::GOVERNANCE_PARAM_REJECTED_TOTAL)
            .to have_received(:increment).with(labels: { parameter: "dynamic_tax_rate" })
        end
      end

      context "when a DCI-locked Lorenz key is voted on-chain" do
        before do
          stub_all_parameters_unset
          stub_parameter_set(:lorenz_sigma, 12_000_000_000_000_000_000)
        end

        it "does NOT sync it into SystemParameter (tripwire only)" do
          allow(Rails.logger).to receive(:warn)
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).not_to have_received(:set)

          expect(Rails.logger).to have_received(:warn).with(/DCI-locked lorenz_sigma/)
        end
      end

      context "when multiple parameters change" do
        before do
          stub_all_parameters_unset
          stub_parameter_set(:slash_gamma, 1_500_000_000_000_000_000)
          stub_parameter_set(:slash_threshold, 250_000_000_000_000_000) # 0.25
        end

        it "updates all changed parameters" do
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).to have_received(:set).twice
        end

        it "reports correct sync count" do
          allow(SystemParameter).to receive(:set)
          allow(Rails.logger).to receive(:info)

          worker.perform

          expect(Rails.logger).to have_received(:info).with(/2 updated, 7 skipped, 0 rejected/)
        end
      end

      context "when system_bot user exists" do
        let!(:oracle_user) do
          create(:user, :super_admin,
                 email_address: "oracle.executioner@system.silken.net",
                 first_name: "Oracle", last_name: "Executioner")
        end

        before do
          stub_all_parameters_unset
          stub_parameter_set(:slash_gamma, 1_500_000_000_000_000_000)
        end

        it "passes User.oracle_executioner as updated_by" do
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).to have_received(:set).with(
            :slash_gamma,
            anything,
            hash_including(updated_by: oracle_user)
          )
        end
      end

      context "when system_bot user does not exist" do
        before do
          stub_all_parameters_unset
          stub_parameter_set(:slash_gamma, 1_500_000_000_000_000_000)
        end

        it "passes nil as updated_by" do
          allow(SystemParameter).to receive(:set)

          worker.perform

          expect(SystemParameter).to have_received(:set).with(
            :slash_gamma,
            anything,
            hash_including(updated_by: nil)
          )
        end
      end
    end

    context "when handling RPC errors" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("PROTOCOL_PARAMETERS_CONTRACT_ADDRESS").and_return(contract_address)
        allow(ENV).to receive(:fetch).and_call_original
      end

      it "re-raises HTTPX::TimeoutError for Sidekiq retry" do
        allow(Web3::RpcConnectionPool).to receive(:client_for)
          .and_raise(HTTPX::TimeoutError.new(nil, "RPC timeout"))

        expect {
          worker.perform
        }.to raise_error(HTTPX::TimeoutError)
      end

      it "re-raises connection errors for Sidekiq retry" do
        allow(Web3::RpcConnectionPool).to receive(:client_for)
          .and_raise(Errno::ECONNREFUSED, "RPC node unreachable")

        expect {
          worker.perform
        }.to raise_error(Errno::ECONNREFUSED)
      end

      it "re-raises Errno::ECONNRESET for Sidekiq retry" do
        allow(Web3::RpcConnectionPool).to receive(:client_for)
          .and_raise(Errno::ECONNRESET, "Connection reset")

        expect {
          worker.perform
        }.to raise_error(Errno::ECONNRESET)
      end
    end
  end

  # ─── Private Method Unit Tests (via send) ─────────────────────────

  describe "#convert_from_fixed_point" do
    let(:worker) { described_class.new }

    it "converts integer type: 2000e18 → 2000" do
      result = worker.send(:convert_from_fixed_point, 2_000_000_000_000_000_000_000, "integer")
      expect(result).to eq(2000)
      expect(result).to be_a(Integer)
    end

    it "converts integer type: 10000e18 → 10000" do
      result = worker.send(:convert_from_fixed_point, 10_000_000_000_000_000_000_000, "integer")
      expect(result).to eq(10_000)
    end

    it "converts float type: 10e18 → 10.0 (BigDecimal)" do
      result = worker.send(:convert_from_fixed_point, 10_000_000_000_000_000_000, "float")
      expect(result).to eq(BigDecimal("10.0"))
      expect(result).to be_a(BigDecimal)
    end

    it "converts fractional value: 0.02e18 → 0.02" do
      result = worker.send(:convert_from_fixed_point, 20_000_000_000_000_000, "float")
      expect(result).to eq(BigDecimal("0.02"))
    end

    it "preserves 18-decimal precision on repeating fractions (8/3)" do
      raw = 2_666_666_666_666_666_667
      result = worker.send(:convert_from_fixed_point, raw, "float")
      expect(result).to be_within(BigDecimal("1e-18")).of(BigDecimal("2.666666666666666667"))
    end

    it "handles zero value" do
      result = worker.send(:convert_from_fixed_point, 0, "float")
      expect(result).to eq(BigDecimal("0"))
    end

    it "handles zero integer value" do
      result = worker.send(:convert_from_fixed_point, 0, "integer")
      expect(result).to eq(0)
    end
  end

  describe "#values_equal?" do
    let(:worker) { described_class.new }

    context "when comparing integers" do
      it "treats 10 and 10 as equal" do
        expect(worker.send(:values_equal?, 10, 10, "integer")).to be true
      end

      it "treats 10.0 and 10 as equal" do
        expect(worker.send(:values_equal?, 10.0, 10, "integer")).to be true
      end

      it "treats 10 and 11 as not equal" do
        expect(worker.send(:values_equal?, 10, 11, "integer")).to be false
      end
    end

    context "when comparing floats" do
      it "treats identical floats as equal" do
        expect(worker.send(:values_equal?, 10.0, BigDecimal("10.0"), "float")).to be true
      end

      it "treats very close floats as equal (within epsilon)" do
        expect(worker.send(:values_equal?, 2.6666666666666665, BigDecimal("2.6666666666666667"), "float")).to be true
      end

      it "treats different floats as not equal" do
        expect(worker.send(:values_equal?, 10.0, BigDecimal("12.0"), "float")).to be false
      end
    end

    context "when comparing strings" do
      it "treats identical strings as equal" do
        expect(worker.send(:values_equal?, "hello", "hello", "string")).to be true
      end

      it "treats different strings as not equal" do
        expect(worker.send(:values_equal?, "hello", "world", "string")).to be false
      end
    end
  end

  describe "#solidity_keccak256" do
    let(:worker) { described_class.new }

    it "produces consistent hashes for the same input" do
      hash1 = worker.send(:solidity_keccak256, "slash_gamma")
      hash2 = worker.send(:solidity_keccak256, "slash_gamma")
      expect(hash1).to eq(hash2)
    end

    it "produces different hashes for different inputs" do
      hash1 = worker.send(:solidity_keccak256, "slash_gamma")
      hash2 = worker.send(:solidity_keccak256, "slash_threshold")
      expect(hash1).not_to eq(hash2)
    end
  end

  describe "#system_bot" do
    let(:worker) { described_class.new }

    # User.oracle_executioner uses find_by (returns nil, never raises) today, but
    # system_bot guards against RecordNotFound so a future find_by! / lookup change
    # degrades gracefully (updated_by: nil) instead of crashing the daily sync.
    it "returns nil when oracle_executioner raises RecordNotFound (fail-safe)" do
      allow(User).to receive(:oracle_executioner).and_raise(ActiveRecord::RecordNotFound)
      expect(worker.send(:system_bot)).to be_nil
    end
  end

  # ─── Helpers ──────────────────────────────────────────────────────

  private

  # Stub every parameter (economic map + DCI tripwire keys) as "not set" on-chain.
  def stub_all_parameters_unset
    allow(mock_client).to receive(:call).with(mock_contract, "isParameterSet", anything).and_return(false)
  end

  # Override a specific parameter to be "set" with a given raw uint256 value.
  def stub_parameter_set(param_key, raw_uint256_value)
    on_chain_key = Eth::Util.keccak256(param_key.to_s)

    allow(mock_client).to receive(:call)
      .with(mock_contract, "isParameterSet", on_chain_key)
      .and_return(true)

    allow(mock_client).to receive(:call)
      .with(mock_contract, "getParameter", on_chain_key)
      .and_return(raw_uint256_value)
  end
end
