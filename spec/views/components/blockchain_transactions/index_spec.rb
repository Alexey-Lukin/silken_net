# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainTransactions::Index do
  let(:transactions) { [ mock_transaction ] }
  let(:pagy) { mock_pagy(count: 1, last: 1) }
  let(:html) { render_index(transactions: transactions, pagy: pagy) }

  # Проводка підписки й вікна підставляється ТУТ, а не в компоненті: у компоненті
  # дефолт зробив би забуту проводку тихою (див. коментар над його `initialize`),
  # тоді як спеці потрібні саме нейтральні значення, щоб кожен приклад лишався про
  # СВІЙ предмет. `organization: nil` — fail-closed бік: підписка не рендериться.
  def render_index(**kwargs)
    render_component(organization: nil, window_start: nil, **kwargs)
  end


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
                       has_wallet: true, cluster_name: nil, sourceable_type: nil)
    tx = BlockchainTransaction.new(
      amount: amount,
      status: status,
      token_type: token_type,
      tx_hash: tx_hash,
      blockchain_network: blockchain_network,
      cluster: cluster_name && Cluster.new(name: cluster_name),
      sourceable_type: sourceable_type,
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

    # 🔴 [I18N.1] Свідок мусить жити в НЕ-БАЗОВІЙ локалі: en-мітка дорівнює старому
    # хардкоду побайтово (мінус емодзі), тож англійський пін лишається зеленим і на
    # сирому рядку — тобто саме там, де дефект і був. Негативна половина несуча з
    # тієї ж причини: без неї приклад не відрізняє «резолвлено» від «зашито».
    it "resolves the heading through the locale, not a hardcoded English string" do
      rendered = I18n.with_locale(:uk) { render_index(transactions: transactions, pagy: pagy) }

      expect(rendered).to include("Реєстр блокчейну — глобальний аудит")
      expect(rendered).not_to include("Blockchain Ledger — Global Audit")
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
      expect(html).not_to include("-0.005")
    end

    # [ARCH.101 ⚖️ 08-20] Знак деривується з `#burn?`; колір на цій чорній панелі
    # свідомо чекає UI.1-міграції домену (світла тема: accent на чорному 3.9 < 4.5).
    it "prints a burn as a NEGATIVE amount [ARCH.101]" do
      txs = [ mock_transaction(sourceable_type: "NaasContract") ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(rendered).to include("-0.005 SCC")
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
    it "renders carbon_coin with the token-carbon surface/border pair" do
      # [UI.1] Токен у ролі ФОН/РАМКА при нейтральному тексті — форма wallets.
      expect(html).to include("bg-token-carbon/20")
    end

    it "renders forest_coin with forest token style" do
      txs = [ mock_transaction(token_type: "forest_coin") ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(rendered).to include("text-token-forest")
    end

    # `cusd` — третє РЕАЛЬНЕ значення enum'а, якому стилю не заведено. Доти тут
    # стояв вигаданий `"other_token"`: фолбек перевірявся входом, неможливим у
    # проді, а єдиний вхід, яким він досяжний насправді, — ніяк.
    it "renders cusd — the styleless enum value — with the surface fallback" do
      txs = [ mock_transaction(token_type: "cusd") ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-gaia-surface text-gaia-text-subtle")
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

    it "renders processing with the warning token and a STATIC discriminator" do
      txs = [ mock_transaction(status: "processing") ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-warning")
      expect(rendered).to include("italic")
      expect(rendered).not_to include("animate-pulse")
    end

    it "renders sent with the info token" do
      txs = [ mock_transaction(status: "sent") ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-info")
    end

    it "renders pending with the warning token" do
      txs = [ mock_transaction(status: "pending") ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-warning")
    end

    it "renders failed with the danger token" do
      txs = [ mock_transaction(status: "failed") ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(rendered).to include("bg-status-danger")
    end
  end

  describe "PENDING_BLOCK" do
    it "shows PENDING_BLOCK when tx_hash is nil" do
      txs = [ mock_transaction(tx_hash: nil) ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(rendered).to include("PENDING_BLOCK")
    end

    # [I18N.1] Той самий пристрій, що на заголовку: en-значення ключа дорівнює
    # токену побайтово, тож дискримінує лише не-базова локаль. Дім перекладів не
    # новий — `contracts/show` резолвить це саме значення в усіх чотирьох каталогах
    # ще доти; тут була не відсутність дому, а сайт, що проїхав повз нього.
    it "resolves the pending-block label through the locale" do
      txs = [ mock_transaction(tx_hash: nil) ]
      rendered = I18n.with_locale(:uk) { render_index(transactions: txs, pagy: pagy) }

      expect(rendered).to include("ОЧІКУЄ_БЛОК")
      expect(rendered).not_to include("PENDING_BLOCK")
    end
  end

  describe "empty state" do
    it "shows empty message when no transactions" do
      rendered = render_index(transactions: [], pagy: mock_pagy(count: 0, last: 1))
      expect(rendered).to include("No blockchain transactions recorded.")
    end

    # 🔴 [UI.4] Пін на ЗГОДУ двох чисел, а не на кожне окремо — саме тому дефект
    # і прожив: `colspan` був `7` при ВОСЬМИ `<th>`, тобто порожній стан не
    # перекривав останню колонку. Кожен бік окремо самоузгоджений, суперечність
    # існує лише МІЖ ними, тож жоден однобічний приклад її не бачить.
    # Число дрейфувало двічі незалежно (`source` від ARCH.98, `audit` від UI.8).
    it "порожній стан перекриває РІВНО стільки колонок, скільки їх у шапці" do
      rendered = render_index(transactions: [], pagy: mock_pagy(count: 0, last: 1))

      headers = rendered.scan(/<th\b/).size
      colspan = rendered[/colspan="(\d+)"/, 1]&.to_i

      # Ліхтарі: без них приклад був би зелений на розмітці, що не має ні того, ні того.
      expect(headers).to be > 0, "у шапці нуль <th> — приклад безпредметний"
      expect(colspan).not_to be_nil, "порожній стан не вивів colspan — приклад безпредметний"

      expect(colspan).to eq(headers),
                         "colspan=#{colspan} при #{headers} колонках — порожній стан не перекриває таблицю"
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
    def provenance_cell(rendered) = rendered[%r{<td class="p-4 text-gaia-primary-strong">([^<]*)</td>}, 1]

    it "names the tree when the row is wallet-sourced" do
      rendered = render_index(transactions: [ mock_transaction ], pagy: pagy)
      expect(provenance_cell(rendered)).to eq("SNET-00000042")
    end

    it "names the cluster when the row carries no wallet" do
      txs = [ mock_transaction(has_wallet: false, cluster_name: "Карпати-7") ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(provenance_cell(rendered)).to eq("Карпати-7")
    end

    # ⚠️ Fail-open: рядок без ОБОХ координат `for_organization` не бачить, тож на цю
    # сторінку він не потрапляє — пін стереже форму фолбеку, не живий стан.
    it "falls back to a dash when neither wallet nor cluster is present" do
      txs = [ mock_transaction(has_wallet: false) ]
      rendered = render_index(transactions: txs, pagy: pagy)
      expect(provenance_cell(rendered)).to eq("—")
    end
  end

  describe "multiple transactions" do
    it "renders all transaction rows" do
      txs = [
        mock_transaction(id: 1, amount: "1.0"),
        mock_transaction(id: 2, amount: "2.0")
      ]
      rendered = render_index(transactions: txs, pagy: mock_pagy(count: 2, last: 1))
      expect(rendered).to include("1.0 SCC")
      expect(rendered).to include("2.0 SCC")
    end
  end

  # Раніше цей приклад називав `manual_review` «unknown status» і пінив сірий
  # фолбек — тобто фіксував дефект як норму. Це реальний AASM-стан грошового
  # шляху, і він був тьмянішим за доброякісний `pending`.
  describe "manual_review — double-spend guard" do
    # 🔴 [UI.3, 2026-08-19] ТРЕТЯ редакція цього приклада, і перші дві цементували
    # дефект: спершу він пінив сірий фолбек, потім `animate-pulse` — а пульс знімає
    # глобальне правило `prefers-reduced-motion`, тож для цілої когорти
    # `manual_review` знову виглядав як `pending`. ⊕ Заразом виправлено розходження
    # імені й твердження: приклад називався «prominently THAN pending», а pending
    # не рендерив ЖОДНОГО разу — тобто порівняння, за яке він названий, не робилось.
    it "renders more prominently than a benign pending transaction" do
      guarded = render_index(transactions: [ mock_transaction(status: "manual_review") ], pagy: pagy)
      benign  = render_index(transactions: [ mock_transaction(status: "pending") ], pagy: pagy)

      expect(guarded).to include("text-status-warning-text")
      # ⚠️ Детектор — `outline-current`, а не `outline-2`: широка форма ловила б
      # ще й `focus-visible:`-утиліти, тобто прилад ПЕРЕбирав би й негативна
      # половина падала б на здоровому коді. (Носій переїхав із `ring` на
      # `outline` 2026-08-19: `ring` це `box-shadow`, а `forced-colors` його гасить.)
      expect(guarded).to include("outline-current")
      expect(benign).not_to include("outline-current")
      expect(guarded).not_to include("animate-pulse")
    end
  end

  # 🔴 Пін цілить у САМ вузол, і це не охайність: `include("—")` по документу був
  # ВАКУУМНИЙ рівно так само, як у сусіда `provenance cell` — заголовок сторінки
  # несе тире («Blockchain Ledger — Global Audit»), тож приклад лишався зеленим і
  # зі знятою коміркою. Сусідній блок цю вакуумність у себе виправив і НАЗВАВ, а
  # тут вона лишилась стояти: клас закрили для одного прикладу, не для файлу.
  describe "blockchain_network fallback" do
    def network_cell(rendered)
      rendered[%r{<td class="p-4 text-gaia-text-muted text-mini uppercase">([^<]*)</td>}, 1]
    end

    it "shows a dash when blockchain_network is nil" do
      txs = [ mock_transaction(blockchain_network: nil) ]

      expect(network_cell(render_index(transactions: txs, pagy: pagy))).to eq("—")
    end

    # Позитивний контроль: без нього «комірка дорівнює тире» не відрізняється від
    # «комірка завжди тире» — рівно та пара, якої бракувало бейджу `action_type`.
    it "names the network when it is present" do
      expect(network_cell(html)).to eq("EVM")
    end
  end

  # 🔴 [UI.4] Вікно — це ВІДБІР записів на аудит-поверхні, тож пін стереже не саме
  # звуження (воно в контролері), а його ОГОЛОШЕННЯ: підпис плюс вихід. Мовчазне
  # вікно було б тихим фільтром, тобто «підмножина, подана як вимір цілого».
  describe "window notice" do
    let(:window_start) { Time.utc(2026, 5, 20) }

    it "declares the active window and offers the way out of it" do
      rendered = render_index(transactions: transactions, pagy: pagy, window_start: window_start)

      expect(rendered).to include("May 20, 2026")
      expect(rendered).to include("window=all")
    end

    # Друга половина: коли вікна немає, оголошувати нічого — інакше підпис брехав би
    # про приховане там, де не приховано нічого.
    it "says nothing when the full history is on screen" do
      expect(html).not_to include("window=all")
    end

    # Дім значення один. Без цього піна лінк і предикат контролера могли б розійтися
    # ТИХО: кнопка лишалась би на місці, а клік не виводив би з вікна.
    it "builds the escape link from the home of the value" do
      rendered = render_index(transactions: transactions, pagy: pagy, window_start: window_start)

      expect(rendered).to include("window=#{described_class::WINDOW_ALL}")
    end
  end

  # [UI.4] Підписка. Її ЗМІСТ (чи адреса та сама, що в продюсера, і чи вона різна
  # для двох тенантів) пінить request-приклад — компонентна спека рендерить повз
  # маршрутизатор і повз викликача, тож тут стережеться лише fail-closed бік:
  # без організації підписки нема взагалі.
  describe "live subscription" do
    it "renders no stream subscription without an organization" do
      expect(html).not_to include("turbo-cable-stream-source")
    end
  end

  describe "pagination url_helper" do
    it "renders pagination links with correct path" do
      multi_pagy = mock_pagy(count: 50, page: 1, last: 3)
      rendered = render_index(transactions: [ mock_transaction ], pagy: multi_pagy)
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
      fallback = render_index(transactions: [ bogus ], pagy: pagy)
      fallback_style = fallback[/bg-status-neutral[^"]*/]
      expect(fallback_style).to be_present

      BlockchainTransaction.aasm.states.map(&:name).each do |state|
        rendered = render_index(transactions: [ mock_transaction(status: state.to_s) ], pagy: pagy)
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
      html = render_index(transactions: [ tx ], pagy: pagy)

      expect(html).to include("/blockchain_transactions/77?created_at=")
    end
  end
end
