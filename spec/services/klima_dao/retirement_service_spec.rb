# frozen_string_literal: true

require "rails_helper"

RSpec.describe KlimaDao::RetirementService do
  let(:fake_approve_hash) { "0x#{'a' * 64}" }
  let(:fake_retire_hash)  { "0x#{'b' * 64}" }
  let(:mock_client)       { instance_double(Eth::Client) }
  let(:mock_key)          { instance_double(Eth::Key, address: "0x#{'d' * 40}") }
  let(:mock_scc_contract) { double("scc_contract") }
  let(:mock_klima_contract) { double("klima_contract") }

  let(:organization) { create(:organization, crypto_public_address: "0x#{'b' * 40}") }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:tree)         { create(:tree, cluster: cluster) }
  let(:wallet)       { tree.wallet }

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_PRIVATE_KEY"] ||= "0x#{'a' * 64}"
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x#{'0' * 40}"
    ENV["KLIMA_RETIREMENT_CONTRACT"] ||= "0x#{'1' * 40}"

    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_scc_contract, mock_klima_contract)
    allow(mock_client).to receive(:transact).and_return(fake_approve_hash, fake_retire_hash)

    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)

    # Встановлюємо баланс гаманця (auto-created wallet має balance: 0)
    wallet.update!(balance: 5000)

    # Створюємо підтверджену carbon_coin транзакцію, щоб пройти Guard Clause
    wallet.blockchain_transactions.create!(
      amount: 100,
      token_type: :carbon_coin,
      status: :confirmed,
      to_address: organization.crypto_public_address,
      tx_hash: "0x#{'c' * 64}"
    )
  end

  describe "#retire_carbon!" do
    context "when wallet has sufficient balance and carbon_coin transactions" do
      it "deducts balance and increases esg_retired_balance" do
        amount = BigDecimal("100")
        initial_balance = wallet.balance

        described_class.new(wallet, amount).retire_carbon!

        wallet.reload
        expect(wallet.balance).to eq(initial_balance - amount)
        expect(wallet.esg_retired_balance).to eq(amount)
      end

      it "creates a blockchain_transaction with correct attributes" do
        amount = BigDecimal("50")

        expect {
          described_class.new(wallet, amount).retire_carbon!
        }.to change(BlockchainTransaction, :count).by(1)

        tx = BlockchainTransaction.last
        expect(tx.amount).to eq(50)
        expect(tx.token_type).to eq("carbon_coin")
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq(fake_retire_hash)
        expect(tx.to_address).to eq(ENV["KLIMA_RETIREMENT_CONTRACT"])
        expect(tx.notes).to include("ESG Retirement via KlimaDAO")
      end

      it "calls approve and then retire on blockchain contracts" do
        described_class.new(wallet, BigDecimal("100")).retire_carbon!

        expect(mock_client).to have_received(:transact).twice
      end

      it "logs success message" do
        allow(Rails.logger).to receive(:info)

        described_class.new(wallet, BigDecimal("10")).retire_carbon!

        expect(Rails.logger).to have_received(:info).with(/KlimaDAO.*Погашено/)
      end
    end

    context "when wallet has insufficient balance" do
      it "raises InsufficientBalanceError" do
        amount = wallet.balance + 1

        expect {
          described_class.new(wallet, amount).retire_carbon!
        }.to raise_error(KlimaDao::RetirementService::InsufficientBalanceError, /Недостатньо коштів/)
      end
    end

    context "when wallet has no carbon_coin transactions" do
      it "raises InvalidTokenTypeError" do
        wallet.blockchain_transactions.destroy_all

        expect {
          described_class.new(wallet, BigDecimal("10")).retire_carbon!
        }.to raise_error(KlimaDao::RetirementService::InvalidTokenTypeError, /carbon_coin/)
      end
    end

    context "when balance changes during transaction (race condition)" do
      it "raises InsufficientBalanceError on re-check after lock" do
        amount = wallet.balance

        # Симулюємо ситуацію, коли баланс зменшується між Web3-викликом та DB-транзакцією
        allow(wallet).to receive(:lock!).and_wrap_original do |method|
          method.call
          wallet.update_column(:balance, 0)
        end

        expect {
          described_class.new(wallet, amount).retire_carbon!
        }.to raise_error(KlimaDao::RetirementService::InsufficientBalanceError, /Баланс змінився/)
      end
    end

    context "when blockchain call fails" do
      it "does not modify wallet balances" do
        allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")

        initial_balance = wallet.balance
        initial_esg = wallet.esg_retired_balance

        expect {
          described_class.new(wallet, BigDecimal("10")).retire_carbon!
        }.to raise_error(StandardError, "RPC timeout")

        wallet.reload
        expect(wallet.balance).to eq(initial_balance)
        expect(wallet.esg_retired_balance).to eq(initial_esg)
      end

      it "does not create a blockchain_transaction" do
        allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")

        initial_count = wallet.blockchain_transactions.count

        begin
          described_class.new(wallet, BigDecimal("10")).retire_carbon!
        rescue StandardError
          # expected
        end

        expect(wallet.blockchain_transactions.count).to eq(initial_count)
      end
    end

    context "with amount as string" do
      it "converts to BigDecimal correctly" do
        described_class.new(wallet, "50.5").retire_carbon!

        wallet.reload
        expect(wallet.esg_retired_balance).to eq(BigDecimal("50.5"))
      end
    end
  end
end
