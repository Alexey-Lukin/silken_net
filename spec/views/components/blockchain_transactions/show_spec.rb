# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransactions::Show do
  let(:transaction) { mock_transaction }
  let(:html) { render_component(transaction: transaction) }

  # Реальний НЕЗБЕРЕЖЕНИЙ запис — дзеркало `wallets/transaction_row_spec.rb` [TEST.12].
  # Старий `OpenStruct` оголошував світ, у якому дефект неможливий (`04_06 §B.2` BP #14):
  # `amount` рядком при колонці `numeric(24,6)`, `blockchain_network: "polygon"` при
  # `validates inclusion: %w[evm solana celo]`, плюс рукописні `solana_network?`/
  # `celo_network?`/`model_name` — тобто спека сама визначала методи, чию поведінку
  # мала перевіряти. Асоціація стабиться ТОЧКОВО: фабрика тягла б цілий ланцюг.
  def mock_transaction(id: 1, amount: "0.005", status: "confirmed", token_type: "carbon_coin",
                       tx_hash: "0xabcdef1234567890abcdef1234567890abcdef12",
                       blockchain_network: "evm", locked_points: 10_000,
                       to_address: "0x1234567890abcdef1234567890abcdef12345678",
                       gas_price: 30, gas_used: 21_000, block_number: 123_456,
                       nonce: 42, sent_at: 1.hour.ago, confirmed_at: 30.minutes.ago,
                       notes: nil, error_message: nil,
                       wallet_tree_did: "SNET-00000042", wallet_balance: 12.5,
                       has_wallet: true, sourceable_type: nil)
    tx = BlockchainTransaction.new(
      amount: amount,
      status: status,
      token_type: token_type,
      tx_hash: tx_hash,
      blockchain_network: blockchain_network,
      locked_points: locked_points,
      to_address: to_address,
      gas_price: gas_price,
      gas_used: gas_used,
      block_number: block_number,
      nonce: nonce,
      sent_at: sent_at,
      confirmed_at: confirmed_at,
      created_at: 2.hours.ago,
      updated_at: 30.minutes.ago,
      notes: notes,
      error_message: error_message,
      sourceable_type: sourceable_type
    )
    tx.id = id

    wallet = has_wallet ? Wallet.new(tree: Tree.new(did: wallet_tree_did), balance: wallet_balance) : nil
    tx.define_singleton_method(:wallet) { wallet }
    tx
  end

  describe "header" do
    it "displays amount with SCC label" do
      expect(html).to include("0.005 SCC")
      expect(html).not_to include("-0.005")
    end

    # [ARCH.101 ⚖️ 08-20] Власний свідок САЙТУ: деривацію знака тримає модель, але
    # без цього піна hero міг би тихо повернутись на сирий `amount`.
    it "prints a burn hero as a NEGATIVE amount" do
      rendered = render_component(transaction: mock_transaction(sourceable_type: "NaasContract"))
      expect(rendered).to include("-0.005 SCC")
    end

    it "displays transaction ID" do
      expect(html).to include("#1")
    end

    it "displays Transaction Record label" do
      expect(html).to include("Transaction Record")
    end
  end

  # Заголовок і рядок деталей ідуть через спільний `StatusBadge` / його
  # `.label` (I18N.1, 2026-08-05) — приватна `status_badge_styles` знесена.
  describe "status badge" do
    it "renders confirmed with the success token" do
      expect(html).to include("confirmed")
      expect(html).to include("bg-status-success")
    end

    it "renders processing with the warning token" do
      tx = mock_transaction(status: "processing")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("processing")
      expect(rendered).to include("bg-status-warning")
    end

    it "renders sent with the info token" do
      tx = mock_transaction(status: "sent")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("sent")
      expect(rendered).to include("bg-status-info")
    end

    it "renders pending with the warning token" do
      tx = mock_transaction(status: "pending")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("pending")
      expect(rendered).to include("bg-status-warning")
    end

    it "renders failed with the danger token" do
      tx = mock_transaction(status: "failed")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("failed")
      expect(rendered).to include("bg-status-danger")
    end
  end

  describe "token badge" do
    # Негативна половина несуча: бейдж доти друкував сире значення, тож пін лише на
    # стиль лишався б зеленим і після повернення сирого enum'а.
    it "renders carbon_coin as its label with the emerald style" do
      expect(html).to include("Silken Carbon Coin")
      expect(html).to include("text-emerald-400")
      expect(html).not_to include("carbon_coin")
    end

    it "renders forest_coin as its label with the forest token style" do
      rendered = render_component(transaction: mock_transaction(token_type: "forest_coin"))
      expect(rendered).to include("Silken Forest Coin")
      expect(rendered).to include("text-token-forest")
    end

    # Реальне `cusd` замість вигаданого `"unknown_coin"` — див. сусідній `index_spec`.
    it "renders cusd as its label with the zinc style" do
      rendered = render_component(transaction: mock_transaction(token_type: "cusd"))
      expect(rendered).to include("Celo Dollar")
      expect(rendered).to include("text-zinc-400")
    end
  end

  describe "transaction details table" do
    it "displays amount field" do
      expect(html).to include("Amount")
      expect(html).to include("0.005 SCC")
    end

    # 🔴 Найгірший підклас, який цей рядок ніс: сире значення всередині ПЕРЕКЛАДЕНОЇ
    # мітки — фраза виглядає локалізованою, тож при вичитці її пропускають
    # (`04_04 §12.14`). Сусідній рядок `Status` ішов через дім міток ще доти.
    it "displays token type as its label, never the raw enum value" do
      expect(html).to include("Token Type")
      expect(html).to include("Silken Carbon Coin")
      expect(html).not_to include("carbon_coin")
    end

    it "displays blockchain network" do
      expect(html).to include("Blockchain Network")
      expect(html).to include("EVM")
    end

    it "displays locked points" do
      expect(html).to include("Locked Points")
      expect(html).to include("10000")
    end

    it "displays to address" do
      expect(html).to include("To Address")
      expect(html).to include("0x1234567890abcdef1234567890abcdef12345678")
    end

    # «30.0», а не «30»: колонка `numeric` віддає BigDecimal, і саме цю розбіжність
    # ховав `OpenStruct` — питання «як тип рендериться в рядок» із сюїти було
    # неможливо поставити [TEST.12].
    it "displays gas price with wei unit" do
      expect(html).to include("Gas Price")
      expect(html).to include("30.0 wei")
    end

    it "displays gas used" do
      expect(html).to include("Gas Used")
      expect(html).to include("21000")
    end

    it "displays block number" do
      expect(html).to include("Block Number")
      expect(html).to include("123456")
    end

    it "displays nonce" do
      expect(html).to include("Nonce")
      expect(html).to include("42")
    end

    it "shows a dash for blockchain network when nil" do
      tx = mock_transaction(blockchain_network: nil)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Blockchain Network")
      expect(rendered).to include("—")
    end

    it "shows a dash for gas price when nil" do
      tx = mock_transaction(gas_price: nil)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Gas Price")
      expect(rendered).not_to include(" wei")
    end

    it "shows a dash for sent_at when nil" do
      tx = mock_transaction(sent_at: nil)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Sent At")
      expect(rendered).to include("—")
    end

    it "shows a dash for confirmed_at when nil" do
      tx = mock_transaction(confirmed_at: nil)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Confirmed At")
      expect(rendered).to include("—")
    end
  end

  describe "notes panel" do
    it "shows 'No notes attached.' when notes are nil" do
      expect(html).to include("No notes attached.")
    end

    it "displays notes when present" do
      tx = mock_transaction(notes: "Batch mint for Carpathian cluster")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Batch mint for Carpathian cluster")
    end
  end

  describe "error message panel" do
    it "does not render error section when no error" do
      expect(html).not_to include("Error Message")
    end

    it "renders error message when present" do
      tx = mock_transaction(error_message: "Gas estimation failed: revert")
      rendered = render_component(transaction: tx)
      expect(rendered).to include("Error Message")
      expect(rendered).to include("Gas estimation failed: revert")
    end
  end

  describe "wallet info" do
    it "displays tree DID" do
      expect(html).to include("Tree DID")
      expect(html).to include("SNET-00000042")
    end

    it "displays wallet balance" do
      expect(html).to include("Wallet Balance")
      expect(html).to include("12.5")
    end

    it "shows 'No wallet linked.' when wallet is nil" do
      tx = mock_transaction(has_wallet: false)
      rendered = render_component(transaction: tx)
      expect(rendered).to include("No wallet linked.")
    end

    # 🔴 [ARCH.101] Джерел грошей ДВА — гаманцеве дерево АБО кластер, — і доти
    # сторінка знала лише перше: cluster-sourced рух (Celo-винагорода кластеру ·
    # слеш «останнього дерева») діставав «No wallet linked.» і не називав джерела
    # взагалі. ARCH.98 зробив такий рядок ДОСЯЖНИМ прямою адресою й не спитав, що
    # сторінка тоді ПОКАЖЕ; блупринт при цьому віддає `cluster_name` в обох в'ю,
    # тобто дві репрезентації одного ендпоінта розходились.
    context "when the row is cluster-sourced (no wallet by construction)" do
      let(:cluster_tx) do
        tx = mock_transaction(has_wallet: false)
        cluster = Cluster.new(name: "Карпати-7")
        tx.define_singleton_method(:cluster) { cluster }
        tx
      end

      it "names the source cluster instead of reporting an absence" do
        rendered = render_component(transaction: cluster_tx)

        expect(rendered).to include("Карпати-7")
        expect(rendered).not_to include("No wallet linked.")
      end

      # Окремим прикладом, не другим ассертом сусіда: це ІНША вісь, і зведені в
      # один приклад вони давали б повідомлення про значення там, де зламався
      # заголовок. Мітка над іменем кластера мусить називати кластер — інакше це
      # «одна мітка, два значення» на рівень вище за саме поле.
      it "switches the section heading to the cluster, not just the value" do
        expect(render_component(transaction: cluster_tx)).to include("Source Cluster")
      end

      # Позитивний контроль: без нього «називає кластер» не відрізняється від
      # «називає кластер завжди», а заголовок — від «заголовок завжди кластерний».
      it "keeps the wallet heading for a wallet-backed row" do
        expect(html).to include("Linked Wallet")
        expect(html).not_to include("Source Cluster")
      end
    end
  end

  # [UI.4] Підписку знято: голий `wallet`-стрім лишився без продюсерів, а цілі на
  # цій сторінці не було ніколи. Пін інвертовано — він тепер стереже, щоб хтось не
  # повернув підписку-в-нікуди, не давши сторінці спершу ціль.
  describe "turbo stream subscription" do
    it "does not subscribe to a stream it has no target for" do
      expect(html).not_to include("turbo-cable-stream-source")
    end
  end

  describe "lazy-loaded on-chain frame" do
    it "renders turbo frame with correct ID" do
      expect(html).to include("tx_onchain_frame_1")
    end

    it "uses lazy loading" do
      expect(html).to include('loading="lazy"')
    end
  end

  # 🔴 Цей блок раніше називав `manual_review` «unknown status» і стверджував,
  # що він дістає zinc-фолбек — тобто СПЕКА ЦЕМЕНТУВАЛА ДЕФЕКТ. Насправді це
  # реальний AASM-стан грошового шляху (double-spend guard: tx_hash є, кошти
  # заблоковані, стан невідомий), і він малювався тьмянішим за доброякісний
  # `pending`. Приклад мусить пінити ВИДИМІСТЬ, а не факт існування гілки.
  describe "manual_review — double-spend guard" do
    it "renders more prominently than a benign pending transaction" do
      rendered = render_component(transaction: mock_transaction(status: "manual_review"))

      expect(rendered).to include("bg-status-warning")
      expect(rendered).to include("animate-pulse")
      expect(rendered).not_to include("bg-zinc-900")
    end
  end

  # Гейт на КЛАС: ітеруємо реальні стани AASM, а не власний перелік — саме
  # розрив між ними й пропустив `manual_review` у дефолтну гілку. Новий стан
  # у моделі зробить цей приклад червоним, а не тихо тьмяним.
  # ⚠️ Після переходу на спільний бейдж фолбек — `StatusBadge::DEFAULT_STYLE`
  # (`bg-status-neutral`), і він же легітимний стиль для `idle`/`draft`/`offline`/
  # `cancelled`/`removed`. Для BlockchainTransaction це безпечно: ЖОДЕН із її
  # шести станів не мапиться в neutral — тож попадання в цей клас і далі
  # означає рівно «стан провалився у дефолт». Для родини, яка МАЄ neutral-стан,
  # цей гейт довелось би будувати на іншому детекторі.
  describe "status style coverage" do
    it "gives every BlockchainTransaction state a style of its own" do
      # Реальний enum відкидає невалідне значення ще в конструкторі, тож недосяжну
      # гілку відкриває стаб РИДЕРА, а не підсунутий запис.
      bogus = mock_transaction
      bogus.define_singleton_method(:status) { "__not_a_state__" }
      fallback = render_component(transaction: bogus)
      fallback_style = fallback[/bg-status-neutral[^"]*/]
      # Без цього приклад був би вакуумним: якби фолбек не знайшовся,
      # `not_to include(nil)` не перевіряло б нічого.
      expect(fallback_style).to be_present

      BlockchainTransaction.aasm.states.map(&:name).each do |state|
        rendered = render_component(transaction: mock_transaction(status: state.to_s))
        expect(rendered).not_to include(fallback_style),
                                "стан #{state} падає в дефолтну гілку — його не видно як окремий"
      end
    end
  end
end
