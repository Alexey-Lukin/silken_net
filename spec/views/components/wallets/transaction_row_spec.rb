# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::TransactionRow do
  # Реальний НЕЗБЕРЕЖЕНИЙ запис, а не `OpenStruct`. Попередній мок брехав двічі, і
  # обидві брехні — того класу, що описує `04_06 §B.2` BP #14 (фікстура оголошує
  # світ, у якому дефект неможливий): `amount` подавався РЯДКОМ, тоді як колонка
  # `numeric(24,6)` віддає BigDecimal, а `token_type` приймав `"mystery_coin"` —
  # значення, на якому справжній enum кидає `ArgumentError`. Саме тому «0.005»
  # пінилось БЕЗ одиниці, і зашитий тікер «SCC» прожив непоміченим при трьох
  # типах токена. Голий `.new` замість фабрики свідомо: фабрика тягне
  # `wallet → tree → cluster → organization`, чого рядку таблиці не треба.
  def mock_tx(token_type: "carbon_coin", status: "confirmed", amount: "0.005",
              tx_hash: "0xabcdef1234567890abcdef")
    tx = BlockchainTransaction.new(
      token_type: token_type,
      status: status,
      amount: amount,
      tx_hash: tx_hash,
      created_at: Time.current
    )
    tx.id = 42
    tx
  end

  describe "token type styling" do
    it "renders carbon_coin with emerald style" do
      html = render_component(tx: mock_tx(token_type: "carbon_coin"))
      expect(html).to include("bg-emerald-900/20")
      expect(html).to include("text-emerald-400")
    end

    it "renders forest_coin with token-forest style" do
      html = render_component(tx: mock_tx(token_type: "forest_coin"))
      expect(html).to include("bg-token-forest/20")
      expect(html).to include("text-token-forest")
    end

    # `cusd` — третє РЕАЛЬНЕ значення enum'а, для якого стилю не заведено; доти тут
    # стояв вигаданий `"mystery_coin"`, на якому справжній enum кидає `ArgumentError`.
    # Тобто фолбек перевірявся входом, неможливим у проді, а єдиний вхід, яким він
    # досяжний насправді, не перевірявся ніяк.
    it "renders cusd — the enum value with no dedicated style — with the zinc fallback" do
      html = render_component(tx: mock_tx(token_type: "cusd"))
      expect(html).to include("bg-zinc-900")
      expect(html).to include("text-zinc-400")
    end
  end

  describe "status color" do
    it "renders confirmed status in emerald" do
      html = render_component(tx: mock_tx(status: "confirmed"))
      expect(html).to include("text-emerald-500")
    end

    it "renders processing status with warning pulse" do
      html = render_component(tx: mock_tx(status: "processing"))
      expect(html).to include("text-status-warning-text")
      expect(html).to include("animate-pulse")
    end

    it "renders sent status with warning pulse" do
      html = render_component(tx: mock_tx(status: "sent"))
      expect(html).to include("text-status-warning-text")
      expect(html).to include("animate-pulse")
    end

    it "renders pending status in gray" do
      html = render_component(tx: mock_tx(status: "pending"))
      expect(html).to include("text-gray-400")
    end

    it "renders failed status in red" do
      html = render_component(tx: mock_tx(status: "failed"))
      expect(html).to include("text-red-500")
    end

    # Раніше цей приклад називав `manual_review` «unrecognized» і пінив сірий
    # фолбек — тобто фіксував дефект як норму. Це реальний AASM-стан
    # грошового шляху, і він був тьмянішим за доброякісний `pending`.
    # ⚠️ Негативної половини на `text-gray-600` тут бути НЕ може: цей клас
    # носить ще й комірка хеша (`transaction_row.rb`), тож приклад проходив
    # би через сусідній елемент — та сама вада, яку цей блок виправляє.
    it "renders manual_review more prominently than a benign pending row" do
      html = render_component(tx: mock_tx(status: "manual_review"))
      pending_html = render_component(tx: mock_tx(status: "pending"))

      expect(html).to include("text-status-warning-text")
      expect(html).to include("animate-pulse")
      # Порівняння з доброякісним станом — те, що робить пін не-вакуумним:
      # обидва рендери проходять той самий шлях, різнитись мусить лише стиль.
      expect(pending_html).not_to include("animate-pulse")
    end
  end

  describe "transaction hash display" do
    it "truncates long tx hashes to 16 chars" do
      html = render_component(tx: mock_tx(tx_hash: "0xabcdef1234567890abcdef"))
      expect(html).to include("0xabcdef12345678…")
    end

    # URL більше не ІН'ЄКТУЄТЬСЯ у фікстуру — його виводить сама модель із `tx_hash`
    # і мережі. Ін'єкція означала, що приклад пінив власну константу, а не поведінку.
    it "links to the explorer URL derived by the model" do
      html = render_component(tx: mock_tx(tx_hash: "0xabc123"))
      expect(html).to include("https://polygonscan.com/tx/0xabc123")
    end

    it "shows PENDING_BLOCK when hash is nil" do
      html = render_component(tx: mock_tx(tx_hash: nil))
      expect(html).to include("PENDING_BLOCK")
    end

    it "shows the full hash untruncated when it is 16 characters or fewer" do
      html = render_component(tx: mock_tx(tx_hash: "0xshort123"))
      expect(html).to include("0xshort123")
      expect(html).not_to include("…")
    end
  end

  describe "rendering" do
    let(:html) { render_component(tx: mock_tx) }

    it "includes the dom_id of the transaction in the row id" do
      expect(html).to include("blockchain_transaction_42")
    end

    it "displays the token type" do
      expect(html).to include("carbon_coin")
    end

    it "displays the amount with the ticker of its own token type" do
      expect(html).to include("0.005 SCC")
    end

    # Регресійний гард на живий дефект: тікер був ЗАШИТИЙ як «SCC» при трьох
    # значеннях `token_type`, тож страхова виплата в лісовій монеті (тип береться
    # з контракту — `insurance_payout_worker.rb`) підписувалась чужою монетою.
    # Негативна половина несуча: без неї пін проходив би й на зашитому рядку.
    it "does not sign a forest_coin transaction with the carbon ticker" do
      forest = render_component(tx: mock_tx(token_type: "forest_coin", amount: "5"))
      expect(forest).to include("5.0 SFC")
      expect(forest).not_to include("SCC")
    end

    it "uses text-micro for status instead of arbitrary sizes" do
      expect(html).to include("text-micro")
      expect(html).not_to include("text-[")
    end

    it "uses extracted row_classes method" do
      expect(html).to include("hover:bg-emerald-950/10")
      expect(html).to include("transition-colors")
    end
  end

  # Гейт на КЛАС — дзеркало `blockchain_transactions/show_spec`, якого на цій
  # поверхні не було. Перелічувати стани руками тут не можна: саме розрив між
  # рукописним переліком і реальним AASM колись лишив `manual_review` у дефолтній
  # гілці, тобто найгучніший стан грошового шляху малювався найтихіше.
  #
  # Два уточнення проти дослівного копіювання зразка. (1) Мапа тут ПРИВАТНА, тож
  # фолбек — не `bg-status-neutral` спільного бейджа, а `text-gray-600`; брати
  # його літералом не можна — той самий клас носить комірка хеша, і пін був би
  # вакуумним, тому детектор бере ВЕСЬ клас статус-спана (`text-micro` у цьому
  # компоненті рівно один). (2) Запис тут РЕАЛЬНИЙ, тож фолбек треба ДІСТАВАТИ:
  # неіснуюче значення enum кидає `ArgumentError`, а `status: nil` мовчки дає
  # `pending` — AASM ставить `initial: true` уже в конструкторі, тож такий «зонд»
  # рендерив би звичайний стан і робив приклад тавтологією (спіймано падінням).
  # Єдиний чесний шлях до гілки — стабнути сам ридер на реальному записі.
  describe "status style coverage" do
    it "gives every BlockchainTransaction state a style of its own" do
      probe = mock_tx
      allow(probe).to receive(:status).and_return("__not_a_state__")
      fallback_style = render_component(tx: probe)[/text-micro[^"]*/]
      expect(fallback_style).to be_present

      BlockchainTransaction.aasm.states.map(&:name).each do |state|
        rendered = render_component(tx: mock_tx(status: state.to_s))
        expect(rendered).not_to include(fallback_style),
                                "стан #{state} падає в дефолтну гілку — його не видно як окремий"
      end
    end
  end
end
