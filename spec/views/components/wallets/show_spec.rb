# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Show do
  let(:wallet) { mock_wallet }
  let(:transactions) { [ mock_tx ] }
  let(:html) { render_component(wallet: wallet, transactions: transactions) }

  # 🔴 [TEST.12] Реальний незбережений `Wallet` замість `OpenStruct`. Цей мок
  # пережив конверсію транзакції в цьому ж файлі — надгробок нижче описує ОДИН
  # обʼєкт, і читався як звіт про весь файл (`00_07` UI.17: «надгробок на обʼєкт
  # у багатообʼєктному файлі»).
  # Дві речі, які підміняв саме він: метадані фреймворку (`model_name`/`to_key`/
  # `to_param` рукописні — а компонент будує з них і маршрути, і ПІДПИСАНЕ імʼя
  # стріму `turbo_stream_from @wallet, :transactions`), і **тип балансу**:
  # `scc_balance` це `alias_attribute` на `balance`, тобто `numeric(24,6)` →
  # BigDecimal, тоді як фікстура подавала Float.
  def mock_wallet(id: 1, scc_balance: 42.5)
    Wallet.new(id: id, balance: scc_balance)
  end

  # [TEST.12] Реальний НЕЗБЕРЕЖЕНИЙ запис замість `OpenStruct`. Мок тут був того
  # самого класу, який пункт і описує: він **вигадував метадані фреймворку**
  # (`model_name`/`to_key` рукописні) і мовчки не мав полів, яких компонент іще не
  # питав. Щойно рядок почав рендерити `#ticker`, мок віддав `nil` — тобто спека
  # моделювала світ, у якому дефект неможливий. Реальний запис віддає і `ticker`,
  # і `explorer_url`, і `dom_id` сам; БД не потрібна, бо нічого не зберігаємо.
  def mock_tx(id: 1, token_type: "carbon_coin", status: "confirmed", amount: "0.005",
              tx_hash: "0xabcdef1234567890abcdef")
    tx = BlockchainTransaction.new(
      token_type: token_type, status: status, amount: amount,
      tx_hash: tx_hash, blockchain_network: "evm", created_at: Time.current
    )
    tx.id = id
    tx
  end

  describe "turbo stream subscription" do
    it "includes turbo-cable-stream-source for wallet transactions" do
      expect(html).to include("turbo-cable-stream-source")
    end
  end

  describe "transaction ledger" do
    it "displays transaction table headers" do
      expect(html).to include("Type")
      expect(html).to include("Amount")
      expect(html).to include("Status")
      expect(html).to include("TX Hash")
      expect(html).to include("Timestamp")
    end

    # [I18N.2] Рядок несе ТІКЕР, а не сире значення enum'а — деномінація в леджері
    # стоїть один раз (⚖️ founder 2026-08-06). Негативна половина ловить рецидив
    # у бік «повернути сире значення поруч».
    it "renders transaction rows" do
      expect(html).to include("SCC")
      expect(html).to include("0.005")
      expect(html).not_to include("carbon_coin")
    end

    it "uses dom_id for transaction rows" do
      expect(html).to include("blockchain_transaction_1")
    end

    it "includes transactions_ledger tbody ID" do
      expect(html).to include('id="transactions_ledger"')
    end

    # [UI.4] Продюсер робить `prepend`, тож стабільна адреса легальна лише там,
    # де рендериться ПОЧАТОК списку. Поза першою сторінкою вона мусить зникнути,
    # інакше свіжа транзакція сідає в чужий зріз пагінації.
    it "keeps the stable ledger target on the first page" do
      html = render_component(wallet: wallet, transactions: transactions,
                              pagy: mock_pagy(count: 120, page: 1, last: 3))

      expect(html).to include('id="transactions_ledger"')
    end

    # Поза першою сторінкою адреси немає ВЗАГАЛІ — не власне ім'я для сторінки:
    # те друге було б ціллю, якої не кличе жоден продюсер, тобто новим членом
    # саме того класу мертвих target-id, що [UI.4] інвентаризує.
    it "drops the ledger target entirely beyond the first page" do
      html = render_component(wallet: wallet, transactions: transactions,
                              pagy: mock_pagy(count: 120, page: 2, last: 3))

      expect(html).not_to include("transactions_ledger")
    end
  end

  describe "empty ledger" do
    let(:transactions) { [] }

    it "shows empty state message" do
      expect(html).to include("No transactions detected")
    end

    # Ціль, яку знімає `BlockchainTransaction#broadcast_new_transaction`. Доти
    # цей id не пінила жодна спека, хоча продюсер тепер на нього адресує.
    it "marks the placeholder row with the id the producer removes" do
      expect(html).to include('id="empty_ledger"')
    end
  end

  describe "pagination" do
    it "renders pagination when pagy is present" do
      html = render_component(wallet: wallet, transactions: transactions, pagy: mock_pagy(count: 50, page: 1, last: 3))
      expect(html).to be_present
    end

    it "does not render pagination when pagy is nil" do
      html = render_component(wallet: wallet, transactions: transactions)
      expect(html).not_to include("pagination")
    end
  end

  describe "lazy loading frames" do
    it "includes balance frame with lazy loading" do
      expect(html).to include("wallet_balance_frame_1")
    end

    it "includes metadata frame with lazy loading" do
      expect(html).to include("wallet_metadata_frame_1")
    end
  end
end
