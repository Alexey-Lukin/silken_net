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
              tx_hash: "0xabcdef1234567890abcdef", sourceable_type: nil)
    tx = BlockchainTransaction.new(
      token_type: token_type,
      status: status,
      amount: amount,
      tx_hash: tx_hash,
      sourceable_type: sourceable_type,
      created_at: Time.current
    )
    tx.id = 42
    tx
  end

  # [ARCH.101 ⚖️ 08-20] Напрямок входить у число І в колір; пара пінів взаємно
  # мутаційна: зняти деривацію знака → червоніє burn-приклад, безумовний акцент →
  # червоніє mint-приклад. «-0.005» унікальний у рядку (хеш і час мінуса не несуть),
  # тож include не проходить через сусідній вузол.
  describe "direction sign and loudness [ARCH.101]" do
    it "prints a burn as a NEGATIVE amount with the danger accent" do
      html = render_component(tx: mock_tx(sourceable_type: "NaasContract"))
      expect(html).to include("-0.005")
      expect(html).to include("text-status-danger-accent")
    end

    it "keeps a mint positive and quiet" do
      html = render_component(tx: mock_tx)
      expect(html).to include("0.005")
      expect(html).not_to include("-0.005")
      expect(html).not_to include("text-status-danger-accent")
    end
  end

  describe "token type styling" do
    # [UI.1] Токен у ролі фон/рамка (дзеркало forest-гілки); негатив — свідок
    # міграції: регрес до сирого emerald має власне імʼя в падінні.
    it "renders carbon_coin with the token-carbon chip" do
      html = render_component(tx: mock_tx(token_type: "carbon_coin"))
      expect(html).to include("bg-token-carbon/20")
      expect(html).to include("border-token-carbon/30")
      expect(html).not_to include("bg-emerald-900/20")
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
      expect(html).to include("bg-gaia-surface")
      expect(html).to include("text-gaia-text-subtle")
    end
  end

  # [I18N.2 · клас 2] Приватної кольор-мапи статусу тут БІЛЬШЕ НЕМАЄ — комірка
  # віддає `TransactionStatusFrame` (сторінка) або `TransactionStatusFrameStub`
  # (броадкаст). Тому й піни інші: не «який клас у спана», а «куди делеговано».
  #
  # 🔴 Заразом знято приклад, який був вакуумним ЩЕ ДО цієї правки: «renders
  # confirmed status in emerald» пінив `text-emerald-500`, а той самий клас
  # носить `hover:` посилання на хеш у сусідній комірці — тобто приклад проходив
  # через сусідній елемент і лишався б зеленим, навіть якби статус не рендерився
  # взагалі (`ssot-maintenance` §Guard-craft #17). Виявилось це тим, що при
  # переході на бейдж він НЕ впав разом із рештою блоку.
  describe "status cell" do
    it "renders the status frame, not a private colour map" do
      html = render_component(tx: mock_tx)
      expect(html).to include(%(id="#{Wallets::TransactionStatusFrame.dom_id(42)}"))
    end

    # Пін на ДЕЛЕГАЦІЮ, і він же — гейт на КЛАС. Очікування береться з іншого
    # боку контракту (рендер самого бейджа), а не перераховується тут руками:
    # саме розрив між рукописним переліком і реальним AASM колись лишив
    # `manual_review` — стан, де кошти заблоковані, — тьмянішим за доброякісний
    # `pending`. Тепер будь-який стан, що втратить власний стиль, червонить тут.
    it "delegates every AASM state's style to the shared badge" do
      BlockchainTransaction.aasm.states.map(&:name).each do |state|
        badge = Views::Shared::UI::StatusBadge.new(status: state.to_s).call

        expect(render_component(tx: mock_tx(status: state.to_s))).to include(badge),
                                                                     "стан #{state} не проходить через спільний бейдж"
      end
    end

    # Броадкастна гілка тієї ж комірки. Негативна половина несуча: саме вона
    # відрізняє «стаб відрендерився» від «стаб відрендерився ЗАМІСТЬ бейджа».
    it "swaps the badge for a locale-free stub when a broadcast src is given" do
      html = render_component(tx: mock_tx(status: "confirmed"), status_src: "/wallets/1/transactions/42/status")

      expect(html).to include('src="/wallets/1/transactions/42/status"')
      expect(html).to include("animate-pulse")
      expect(html).not_to include(Views::Shared::UI::StatusBadge.new(status: "confirmed").call)
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

    # Чіп несе ТІКЕР, а не сире значення enum'а. Негативна половина несуча: без неї
    # пін лишався б зеленим і на старій, сирій формі (`carbon_coin` містить «coin»,
    # але не «SCC», тож позитив сам по собі відрізняє їх лише випадково).
    it "renders the ticker in the chip, not the raw enum value" do
      expect(html).to include("SCC")
      expect(html).not_to include("carbon_coin")
    end

    # [I18N.2 ⚖️ founder 2026-08-06] Деномінація стоїть у рядку РІВНО ОДИН раз —
    # у чіпі. Доти вона стояла двічі (сирий `carbon_coin` + «0.005 SCC»), тобто
    # один факт двома мовами, і саме та пара робила переклад чіпа безглуздим:
    # «Вуглецева монета» поруч із «SCC» читається гірше за сиру пару.
    it "renders the amount as a bare number — the unit lives in the chip" do
      expect(html).to include(">0.005<")
      expect(html).not_to include("0.005 SCC")
    end

    # Регресійний гард на живий дефект: тікер був ЗАШИТИЙ як «SCC» при трьох
    # значеннях `token_type`, тож страхова виплата в лісовій монеті (тип береться
    # з контракту — `insurance_payout_worker.rb`) підписувалась чужою монетою.
    # Негативна половина несуча: без неї пін проходив би й на зашитому рядку.
    it "does not sign a forest_coin transaction with the carbon ticker" do
      forest = render_component(tx: mock_tx(token_type: "forest_coin", amount: "5"))
      expect(forest).to include("SFC")
      expect(forest).not_to include("SCC")
    end

    it "uses extracted row_classes method" do
      expect(html).to include("hover:bg-gaia-surface-sunken")
      expect(html).to include("transition-colors")
    end
  end

  # ⚠️ Тут стояв гейт «кожен стан має власний стиль», побудований на ПРИВАТНІЙ
  # мапі цього компонента (зонд через стаб ридера + детектор `text-micro`). Мапи
  # більше немає — статус іде через спільний бейдж, — тож гейт переїхав у
  # `describe "status cell"` вище й змінив форму: він пінить ДЕЛЕГАЦІЮ, звіряючи
  # рендер із рендером самого бейджа. Це строго сильніше за старий: старий довів
  # би «стилі різні» навіть якби всі вони були чужого домену.
end
