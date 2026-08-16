# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransactions::Index do
  let(:transactions) { [ mock_transaction ] }
  let(:pagy) { mock_pagy(count: 1, last: 1) }
  let(:html) { render_component(transactions: transactions, pagy: pagy) }


  # Реальний НЕЗБЕРЕЖЕНИЙ запис, а не `OpenStruct` — дзеркало
  # `wallets/transaction_row_spec.rb` [TEST.12]. Старий мок оголошував світ, у якому
  # дефект неможливий (`04_06 §B.2` BP #14): `amount` подавався РЯДКОМ при колонці
  # `numeric(24,6)`, а `blockchain_network: "polygon"` — значення, яке
  # `validates inclusion: %w[evm solana celo]` відкидає, тобто спека моделювала
  # мережу, якої модель не приймає. Разом із ним зникають рукописні `model_name`/
  # `to_key`/`to_param`: реальний запис віддає їх сам, і саме їхня вигаданість
  # дозволяла `dom_id` розійтися з тим, що рендериться. Асоціації стабляться
  # ТОЧКОВО — фабрика тягла б `wallet → tree → cluster → organization`.
  def mock_transaction(id: 1, amount: "0.005", status: "confirmed", token_type: "carbon_coin",
                       tx_hash: "0xabcdef1234567890abcdef1234567890abcdef12",
                       blockchain_network: "evm", wallet_tree_did: "SNET-00000042",
                       has_wallet: true, cluster_name: nil)
    tx = BlockchainTransaction.new(
      amount: amount,
      status: status,
      token_type: token_type,
      tx_hash: tx_hash,
      blockchain_network: blockchain_network,
      cluster: cluster_name && Cluster.new(name: cluster_name),
      created_at: Time.current
    )
    tx.id = id

    wallet = has_wallet ? Wallet.new(tree: Tree.new(did: wallet_tree_did)) : nil
    tx.define_singleton_method(:wallet) { wallet }
    tx
  end

  describe "header" do
    it "displays Blockchain Ledger title" do
      expect(html).to include("Blockchain Ledger")
    end

    # Легенда рендерить МІТКИ, і негативна половина тут несуча: доти вона друкувала
    # сирий `carbon_coin`, тож пін на саму присутність слова лишався б зеленим і
    # після регресії.
    it "renders the legend as labels, never the raw enum value" do
      expect(html).to include("Silken Carbon Coin", "Silken Forest Coin", "Celo Dollar")
      expect(html).not_to include("carbon_coin")
    end
  end

  describe "table headers" do
    it "renders all column headers" do
      expect(html).to include("Type")
      expect(html).to include("Amount")
      expect(html).to include("Status")
      expect(html).to include("Network")
      # Мітка питає ПРОВЕНАНС, а не дерево: під «Tree» cluster-sourced рядок
      # показував тире, тобто колонка обіцяла координату, якої в нього не буває.
      expect(html).to include("Source")
      expect(html).not_to include("Tree")
      expect(html).to include("TX Hash")
      expect(html).to include("Timestamp")
    end
  end

  describe "transaction rows" do
    it "displays amount with SCC" do
      expect(html).to include("0.005 SCC")
    end

    it "displays status" do
      expect(html).to include("confirmed")
    end

    it "displays network in uppercase" do
      expect(html).to include("EVM")
    end

    it "displays tree DID from wallet" do
      expect(html).to include("SNET-00000042")
    end

    it "displays truncated tx_hash with link" do
      expect(html).to include("0xabcdef12345678...")
    end

    it "links to explorer URL" do
      expect(html).to include("https://polygonscan.com/tx/0xabc")
    end

    it "includes aria-label on explorer link" do
      expect(html).to include("aria-label")
    end

    it "displays timestamp" do
      expect(html).to include("//")
    end
  end

  describe "token type badge styles" do
    it "renders carbon_coin with emerald style" do
      expect(html).to include("text-emerald-400")
    end

    it "renders forest_coin with forest token style" do
      txs = [ mock_transaction(token_type: "forest_coin") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-token-forest")
    end

    # `cusd` — третє РЕАЛЬНЕ значення enum'а, якому стилю не заведено. Доти тут
    # стояв вигаданий `"other_token"`: фолбек перевірявся входом, неможливим у
    # проді, а єдиний вхід, яким він досяжний насправді, — ніяк.
    it "renders cusd — the styleless enum value — with the zinc fallback" do
      txs = [ mock_transaction(token_type: "cusd") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-zinc-400")
    end
  end

  # Статус іде через спільний `Views::Shared::UI::StatusBadge` (I18N.1, 2026-08-05):
  # приватна кольор-мапа цього компонента була побайтовою копією тієї, що в
  # `Wallets::TransactionRow`, і обидві дублювали централізовану. Піни тепер на
  # СЕМАНТИЧНІ токени бейджа, а не на сирі `text-gray-400`/`text-red-500`.
  describe "status colors" do
    # ⚠️ Доти цей приклад пінив `text-emerald-500` і був ЗЕЛЕНИЙ через сусідню
    # колонку DID, яка носить той самий клас — тобто ловив правильну сторінку,
    # але не той елемент. Пін на токен бейджа цього повторити не може.
    it "renders confirmed with the success token" do
      expect(html).to include("bg-status-success")
    end

    it "renders processing with the warning token and pulse" do
      txs = [ mock_transaction(status: "processing") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-warning")
      expect(rendered).to include("animate-pulse")
    end

    it "renders sent with the info token" do
      txs = [ mock_transaction(status: "sent") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-info")
    end

    it "renders pending with the warning token" do
      txs = [ mock_transaction(status: "pending") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-warning")
    end

    it "renders failed with the danger token" do
      txs = [ mock_transaction(status: "failed") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-danger")
    end
  end

  describe "PENDING_BLOCK" do
    it "shows PENDING_BLOCK when tx_hash is nil" do
      txs = [ mock_transaction(tx_hash: nil) ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("PENDING_BLOCK")
    end
  end

  describe "empty state" do
    it "shows empty message when no transactions" do
      rendered = render_component(transactions: [], pagy: mock_pagy(count: 0, last: 1))
      expect(rendered).to include("No blockchain transactions recorded.")
    end
  end

  describe "pagination" do
    it "renders pagination component" do
      expect(html).to be_present
    end
  end

  # [ARCH.98] Обидві координати провенансу, і саме ПАРА тут несуча: гілку кластера
  # додано тому, що cluster-sourced рухи (Celo-винагорода, слеш останнього дерева)
  # гаманця не мають ЗА ПОБУДОВОЮ — і доти вони були єдиним родом рядків, чиє
  # джерело екран не вмів назвати взагалі.
  # 🔴 Піни цілять у САМ вузол, і це куплено падінням: `include("—")` по документу
  # був ВАКУУМНИЙ — заголовок сторінки містить «Blockchain Ledger — Global Audit»,
  # тож приклад лишався зеленим і зі знятою коміркою.
  describe "provenance cell" do
    def provenance_cell(rendered) = rendered[%r{<td class="p-4 text-emerald-500">([^<]*)</td>}, 1]

    it "names the tree when the row is wallet-sourced" do
      rendered = render_component(transactions: [ mock_transaction ], pagy: pagy)
      expect(provenance_cell(rendered)).to eq("SNET-00000042")
    end

    it "names the cluster when the row carries no wallet" do
      txs = [ mock_transaction(has_wallet: false, cluster_name: "Карпати-7") ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(provenance_cell(rendered)).to eq("Карпати-7")
    end

    # ⚠️ Fail-open: рядок без ОБОХ координат `for_organization` не бачить, тож на цю
    # сторінку він не потрапляє — пін стереже форму фолбеку, не живий стан.
    it "falls back to a dash when neither wallet nor cluster is present" do
      txs = [ mock_transaction(has_wallet: false) ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(provenance_cell(rendered)).to eq("—")
    end
  end

  describe "multiple transactions" do
    it "renders all transaction rows" do
      txs = [
        mock_transaction(id: 1, amount: "1.0"),
        mock_transaction(id: 2, amount: "2.0")
      ]
      rendered = render_component(transactions: txs, pagy: mock_pagy(count: 2, last: 1))
      expect(rendered).to include("1.0 SCC")
      expect(rendered).to include("2.0 SCC")
    end
  end

  # Раніше цей приклад називав `manual_review` «unknown status» і пінив сірий
  # фолбек — тобто фіксував дефект як норму. Це реальний AASM-стан грошового
  # шляху, і він був тьмянішим за доброякісний `pending`.
  describe "manual_review — double-spend guard" do
    it "renders more prominently than a benign pending transaction" do
      rendered = render_component(transactions: [ mock_transaction(status: "manual_review") ], pagy: pagy)

      expect(rendered).to include("text-status-warning-text")
      expect(rendered).to include("animate-pulse")
    end
  end

  describe "blockchain_network fallback" do
    it "shows a dash when blockchain_network is nil" do
      txs = [ mock_transaction(blockchain_network: nil) ]
      rendered = render_component(transactions: txs, pagy: pagy)
      expect(rendered).to include("—")
    end
  end

  describe "pagination url_helper" do
    it "renders pagination links with correct path" do
      multi_pagy = mock_pagy(count: 50, page: 1, last: 3)
      rendered = render_component(transactions: [ mock_transaction ], pagy: multi_pagy)
      expect(rendered).to include("page=2")
    end
  end

  # Гейт на КЛАС — дзеркало `blockchain_transactions/show_spec`, якого на цій
  # поверхні не було: статуси стерегли рукописним переліком, а саме розрив між
  # ним і реальним AASM колись лишив `manual_review` у дефолтній гілці. Рядок
  # тут іде через спільний `StatusBadge`, тож фолбек той самий, що в зразку.
  describe "status style coverage" do
    it "gives every BlockchainTransaction state a style of its own" do
      # Реальний enum відкидає невалідне значення ще в конструкторі, тож недосяжну
      # гілку відкриває стаб РИДЕРА, а не підсунутий запис: інакше зонд валить сам
      # себе замість того, щоб виміряти фолбек.
      bogus = mock_transaction
      bogus.define_singleton_method(:status) { "__not_a_state__" }
      fallback = render_component(transactions: [ bogus ], pagy: pagy)
      fallback_style = fallback[/bg-status-neutral[^"]*/]
      expect(fallback_style).to be_present

      BlockchainTransaction.aasm.states.map(&:name).each do |state|
        rendered = render_component(transactions: [ mock_transaction(status: state.to_s) ], pagy: pagy)
        expect(rendered).not_to include(fallback_style),
                                "стан #{state} падає в дефолтну гілку — його не видно як окремий"
      end
    end

    # [UI.8] Двері в deep-audit. Пін тримає ДВІ осі, і друга несуча: `created_at`
    # у query — не косметика, а ключ партиції. Без нього `find_with_partition_pruning`
    # мовчки падає в degraded-path (скан усіх партицій + лічильник unpruned_lookups),
    # тобто промах був би ТИХИЙ і на екрані невидимий.
    it "links each row to its own audit page, carrying the partition key" do
      tx = mock_transaction(id: 77)
      html = render_component(transactions: [ tx ], pagy: pagy)

      expect(html).to include("/blockchain_transactions/77?created_at=")
    end
  end
end
