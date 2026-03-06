# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainBurningService do
  let(:fake_tx_hash) { "0x#{'f' * 64}" }
  let(:mock_client)  { instance_double(Eth::Client) }
  let(:mock_key)     { instance_double(Eth::Key, address: "0x#{'d' * 40}") }
  let(:mock_contract) { double("contract") }

  let(:organization) { create(:organization, crypto_public_address: "0x#{'b' * 40}") }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster) }

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_PRIVATE_KEY"] ||= "0x#{'a' * 64}"
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x#{'0' * 40}"

    # Kredis може бути відсутнім у тестовому середовищі
    unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
    end

    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
    allow(Kredis).to receive(:lock).and_yield
    allow(mock_client).to receive(:transact_and_wait).and_return(fake_tx_hash)

    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
  end

  describe ".call" do
    context "when no confirmed transactions exist" do
      it "returns early when no confirmed transactions exist" do
        result = described_class.call(organization.id, naas_contract.id)

        expect(result).to be_nil
        expect(Eth::Client).not_to have_received(:create)
      end
    end

    context "when confirmed minted tokens exist" do
      let!(:tree) { create(:tree, cluster: cluster) }

      before do
        tree.wallet.blockchain_transactions.create!(
          amount: 1000,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )
      end

      it "calculates damage ratio from AiInsight data" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'c' * 64}"
        )

        # 1 of 2 trees is critically stressed → damage_ratio = 0.5
        create(:ai_insight,
               analyzable: tree,
               insight_type: :daily_health_summary,
               target_date: cluster.local_yesterday,
               stress_index: 1.0)

        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact_and_wait) do |_contract, _method, _addr, amount_in_wei, **_opts|
          burn_amount = (2000 * 0.5).ceil
          expected_wei = (burn_amount.to_f * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end

      it "falls back to full burn when no AiInsight data and no source_tree" do
        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact_and_wait) do |_contract, _method, _addr, amount_in_wei, **_opts|
          expected_wei = (1000.0 * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end

      it "creates audit BlockchainTransaction on success" do
        expect {
          described_class.call(organization.id, naas_contract.id)
        }.to change(BlockchainTransaction, :count).by(1)

        audit_tx = BlockchainTransaction.last
        expect(audit_tx.tx_hash).to eq(fake_tx_hash)
        expect(audit_tx.status).to eq("confirmed")
        expect(audit_tx.to_address).to eq(organization.crypto_public_address)
        expect(audit_tx.sourceable).to eq(naas_contract)
      end

      it "sets contract to breached and creates EwsAlert on blockchain failure" do
        allow(mock_client).to receive(:transact_and_wait).and_raise(StandardError, "RPC timeout")

        expect {
          described_class.call(organization.id, naas_contract.id)
        }.to raise_error(StandardError, "RPC timeout")
                .and change(EwsAlert, :count).by(1)

        expect(naas_contract.reload.status).to eq("breached")

        alert = EwsAlert.last
        expect(alert.severity).to eq("critical")
        expect(alert.alert_type).to eq("system_fault")
        expect(alert.cluster).to eq(cluster)
      end

      it "uses proportional damage ratio for single source_tree death" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 500,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'e' * 64}"
        )

        # 2 trees total, source_tree specified → damage_ratio = 1/2 = 0.5
        described_class.call(organization.id, naas_contract.id, source_tree: tree)

        expect(mock_client).to have_received(:transact_and_wait) do |_contract, _method, _addr, amount_in_wei, **_opts|
          total_minted = 1500
          burn_amount = (total_minted * (1.0 / 2)).ceil
          expected_wei = (burn_amount.to_f * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end
    end
  end
end
