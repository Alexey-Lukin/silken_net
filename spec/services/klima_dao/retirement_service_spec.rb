# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe KlimaDao::RetirementService do
  let(:fake_approve_hash) { "0x#{'a' * 64}" }
  let(:fake_retire_hash)  { "0x#{'b' * 64}" }
  let(:mock_client)       { instance_double(Eth::Client) }
  let(:mock_key)          { instance_double(Eth::Key, address: "0x#{'d' * 40}") }
  let(:mock_scc_contract) { instance_double(Eth::Contract) }
  let(:mock_klima_contract) { instance_double(Eth::Contract) }

  let(:organization) { create(:organization, crypto_public_address: "0x#{'b' * 40}") }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:tree)         { create(:tree, cluster: cluster) }
  let(:wallet)       { tree.wallet }

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_KLIMA_PRIVATE_KEY"] = "0x#{'a' * 64}"
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x#{'0' * 40}"
    ENV["KLIMA_RETIREMENT_CONTRACT"] = "0x#{'1' * 40}"

    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_scc_contract, mock_klima_contract)
    allow(mock_client).to receive(:transact).and_return(fake_approve_hash, fake_retire_hash)

    silence_broadcasts!(:wallet_balance, :tree_map)

    # [ARCH.95] Бали НЕ є запасом для погашення й свідомо лишаються великими: якби
    # гард знову з'їхав на балову шкалу, ця цифра пропустила б усе підряд, і саме
    # тому вона тут стоїть — як пастка для регресії, не як передумова.
    wallet.update!(balance: 5_000_000)

    # Реальний запас МОНЕТ: підтверджена емісія 1000 SCC. Вона ж проходить
    # `InvalidTokenTypeError`-гард (він питає про наявність carbon_coin-рядка).
    wallet.blockchain_transactions.create!(
      amount: 1000,
      token_type: :carbon_coin,
      status: :confirmed,
      direction: :mint,
      to_address: organization.crypto_public_address,
      tx_hash: "0x#{'c' * 64}"
    )
  end

  describe "#retire_carbon!" do
    context "when the wallet holds enough minted SCC" do
      # [ARCH.95 вісь 3] Балансові колонки НЕ рухаються. Раніше цей приклад звався
      # «deducts balance» і пінив `balance == initial − amount`, тобто ЦЕМЕНТУВАВ
      # рівно те балове списання, яке присуд зняв.
      it "moves only the retired-coin counter and leaves the gross ledger untouched" do
        scc = BigDecimal("100")

        described_class.new(wallet, scc: scc).retire_carbon!

        wallet.reload
        expect(wallet.balance).to eq(5_000_000)
        expect(wallet.locked_balance).to eq(0)
        expect(wallet.esg_retired_balance).to eq(scc)
      end

      it "creates a blockchain_transaction with correct attributes" do
        expect {
          described_class.new(wallet, scc: BigDecimal("50")).retire_carbon!
        }.to change(BlockchainTransaction, :count).by(1)

        tx = BlockchainTransaction.last
        expect(tx.amount).to eq(50)
        expect(tx.token_type).to eq("carbon_coin")
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq(fake_retire_hash)
        expect(tx.to_address).to eq(ENV["KLIMA_RETIREMENT_CONTRACT"])
        expect(tx.notes).to include("ESG Retirement via KlimaDAO")
      end

      # [ARCH.95 вісь 2] Без цього піна погашення читалось би ЕМІСІЄЮ в One-Home,
      # що годує L1-якір і базу слешингу.
      it "records the row as a burn, and the supply aggregate falls by exactly that" do
        before_supply = wallet.blockchain_transactions.net_minted_supply(:carbon_coin)

        described_class.new(wallet, scc: BigDecimal("50")).retire_carbon!

        tx = BlockchainTransaction.last
        expect(tx.direction).to eq("burn")
        expect(tx).to be_burn
        # ⚠️ Свіжий рядок ще `:sent`, тож агрегат (`:confirmed`-only) не зрушив —
        # пін цілиться в ОЗНАКУ, а не в мить розрахунку.
        tx.update_columns(status: BlockchainTransaction.statuses[:confirmed])
        expect(wallet.blockchain_transactions.net_minted_supply(:carbon_coin))
          .to eq(before_supply - 50)
      end

      # 🔴 [ARCH.95] Пін, якого просив трекер: on-chain АРГУМЕНТ і БД-облік в ОДНОМУ
      # прикладі. Доти їх не порівнювало НІЩО — саме тому розходження на чотири
      # порядки могло жити всередині одного методу.
      it "sends on-chain exactly the amount it books in the DB, in the same unit" do
        scc = BigDecimal("42")

        described_class.new(wallet, scc: scc).retire_carbon!

        expected_wei = (scc * 10**18).to_i
        expect(mock_client).to have_received(:transact)
          .with(mock_scc_contract, "approve", anything, expected_wei, any_args)
        expect(mock_client).to have_received(:transact)
          .with(mock_klima_contract, "retire", expected_wei, any_args)

        expect(wallet.reload.esg_retired_balance).to eq(scc)
        expect(BlockchainTransaction.last.amount).to eq(scc)
      end

      it "logs success message" do
        allow(Rails.logger).to receive(:info)

        described_class.new(wallet, scc: BigDecimal("10")).retire_carbon!

        expect(Rails.logger).to have_received(:info).with(/KlimaDAO.*Погашено/)
      end
    end

    context "when the wallet has not minted that many SCC" do
      it "raises InsufficientBalanceError" do
        expect {
          described_class.new(wallet, scc: BigDecimal("1001")).retire_carbon!
        }.to raise_error(KlimaDao::RetirementService::InsufficientBalanceError, /Недостатньо SCC/)
      end

      # 🔴 [ARCH.95 вісь 4] Мутаційний свідок ПРОТИ повернення гарда на балову шкалу.
      # `available_balance` тут = 5 000 000, тобто стара форма пропустила б це
      # необоротне спалення 5000 SCC, яких гаманець не має. Запас монет — 1000.
      it "refuses a burn the points-scale guard would have allowed" do
        expect(wallet.available_balance).to be > 5000

        expect {
          described_class.new(wallet, scc: BigDecimal("5000")).retire_carbon!
        }.to raise_error(KlimaDao::RetirementService::InsufficientBalanceError)

        expect(mock_client).not_to have_received(:transact)
      end

      # 🔴 Дзеркальна половина тієї ж осі: гаманець, що сконвертував УСІ бали, має
      # монети — і стара форма (`available_balance == 0`) відмовила б йому в
      # погашенні того, що він реально тримає.
      it "allows a burn the points-scale guard would have refused" do
        wallet.update!(locked_balance: wallet.balance)
        expect(wallet.available_balance).to eq(0)

        expect { described_class.new(wallet, scc: BigDecimal("100")).retire_carbon! }
          .not_to raise_error

        expect(wallet.reload.esg_retired_balance).to eq(100)
      end
    end

    context "when wallet has no carbon_coin transactions" do
      it "raises InvalidTokenTypeError" do
        wallet.blockchain_transactions.destroy_all

        expect {
          described_class.new(wallet, scc: BigDecimal("10")).retire_carbon!
        }.to raise_error(KlimaDao::RetirementService::InvalidTokenTypeError, /carbon_coin/)
      end
    end

    context "when the coin supply changes during the transaction (race condition)" do
      it "raises InsufficientBalanceError on re-check after lock" do
        # Емісію відкликано (напр. reorg → `:failed`) між Web3-викликом і DB-блоком.
        allow(wallet).to receive(:lock!).and_wrap_original do |method|
          method.call
          wallet.blockchain_transactions.update_all(status: BlockchainTransaction.statuses[:failed])
        end

        expect {
          described_class.new(wallet, scc: BigDecimal("1000")).retire_carbon!
        }.to raise_error(KlimaDao::RetirementService::InsufficientBalanceError, /Запас змінився/)
      end
    end

    context "when blockchain call fails" do
      it "does not modify wallet balances" do
        allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")

        initial_balance = wallet.balance
        initial_esg = wallet.esg_retired_balance

        expect {
          described_class.new(wallet, scc: BigDecimal("10")).retire_carbon!
        }.to raise_error(StandardError, "RPC timeout")

        wallet.reload
        expect(wallet.balance).to eq(initial_balance)
        expect(wallet.esg_retired_balance).to eq(initial_esg)
      end

      it "does not create a blockchain_transaction" do
        allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")

        initial_count = wallet.blockchain_transactions.count

        begin
          described_class.new(wallet, scc: BigDecimal("10")).retire_carbon!
        rescue StandardError
          # expected
        end

        expect(wallet.blockchain_transactions.count).to eq(initial_count)
      end
    end

    context "with the amount given as a string" do
      it "converts to BigDecimal correctly" do
        described_class.new(wallet, scc: "50.5").retire_carbon!

        wallet.reload
        expect(wallet.esg_retired_balance).to eq(BigDecimal("50.5"))
      end
    end

    # [ARCH.95] Одиниця не має бути представною в хибному вигляді — позиційний
    # виклик, яким жив старий дефект, більше не існує як форма.
    it "refuses a positional amount, so points cannot be passed silently" do
      expect { described_class.new(wallet, BigDecimal("100")) }.to raise_error(ArgumentError)
    end
  end
end
