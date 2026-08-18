# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module BlockchainTransactions
  class Index < ApplicationComponent
    # 🔴 [UI.4, 2026-08-17] Колонки — ОДИН дім, і це не косметика: `colspan`
    # порожнього стану був числом, яке дрейфувало ДВІЧІ незалежно. Колонок
    # стало вісім двома окремими проходами (`source` від ARCH.98, `audit` від
    # UI.8), а `colspan` підняв лише один із них — тож порожній стан не
    # перекривав останню колонку. Симптому в тестах не було, бо жоден приклад
    # не звіряв ці два числа між собою: кожне окремо самоузгоджене, суперечність
    # існує лише МІЖ ними.
    # Найстійкіший лік — не «підняти 7 до 8», а зняти число: те, чого не існує
    # окремим фактом, не розходиться. Пара `[ключ, додаткові класи]`.
    COLUMNS = [
      [ :type, "" ], [ :amount, "" ], [ :status, "" ], [ :network, "" ],
      [ :source, "" ], [ :tx_hash, "" ],
      [ :timestamp, "text-right" ], [ :audit, "text-right" ]
    ].freeze

    # Дім значення, яким глядач виходить із вікна. Рендерер і є дім — та сама форма,
    # що `Wallets::Show::LEDGER_TARGET` (його читає модель) і `StatusBadge.label`:
    # інакше літерал жив би і в лінку, і в предикаті контролера, а розходження було б
    # ТИХИМ — кнопка «показати всю історію» просто перестала б виходити з вікна.
    WINDOW_ALL = "all"

    # `organization` і `window_start` — БЕЗ дефолтів свідомо (прецеденти: PERF.1
    # `latest_logs`, ARCH.84 `health_measured`, UI.4 `map_node_total`). Дефолт `nil`
    # зробив би забуту проводку невідрізнимою від законних станів: «підписки немає»
    # виглядало б як «організації немає», а «вікно не звужене» — як «параметр не
    # доїхав». Тут обидва мовчазні стани правдоподібні, тож гучне падіння дешевше.
    def initialize(transactions:, pagy:, organization:, window_start:)
      @transactions = transactions
      @pagy = pagy
      @organization = organization
      @window_start = window_start
    end

    def view_template
      # ⚡ [UI.4] Підписка на сигнал org-леджера. Продюсер — `BlockchainTransaction#
      # broadcast_ledger_signal`, і він адресує org ВЛАСНИКА рядка; тут адреса — org
      # ГЛЯДАЧА (acting-organization). Обидві сторони кличуть ОДИН дім імен.
      # `refresh`, а не `prepend`: сторінка має фільтри, пагінацію й вікно — сліпа
      # вставка нагору суперечила б усім трьом (`04_04 §8.1б`).
      turbo_stream_from TurboStreams::Name.org(:ledger, @organization) if @organization

      div(class: "space-y-6") do
        header_section
        transactions_table
        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { blockchain_transactions_path(page: page) }
        )
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          # Емодзі лишається в розмітці, а не в YAML: це гліф, а не слово мови —
          # у чотирьох каталогах він був би чотирма побайтовими копіями, які гейт
          # парності мусив би тримати в синхроні заради нуля перекладу.
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "📒 #{t('.heading')}" }
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
          render_window_notice
        end
        div(class: "flex gap-2") do
          # Список бере enum, а не рукопис: раніше тут стояло `%w[carbon_coin
          # forest_coin]`, і `cusd` (третє значення) з легенди мовчки випав.
          # Стиль береться з тієї самої мапи, що й рядки таблиці — інакше це не
          # легенда, а перелік: усі три чіпи були однаково зелені й нічого не
          # пояснювали. `role="status"` знято — це статична розмітка, а не жива
          # область (`04_04 §9`).
          BlockchainTransaction.token_types.keys.each do |token_type|
            span(class: tokens("px-2 py-0.5 text-mini font-bold border", token_type_styles(token_type))) do
              BlockchainTransaction.token_type_label(token_type)
            end
          end
        end
      end
    end

    # 🔴 Оголошення видошукача — половина, без якої вікно було б тихим фільтром на
    # аудит-поверхні. Друкується БЕЗУМОВНО, доки вікно чинне, і саме тут воно
    # розходиться з `measurement_coverage`, який мовчить на повному покритті: там
    # «повне» обчислюване й безкоштовне, тут «чи є щось поза вікном» коштувало б
    # окремого запиту на КОЖЕН показ, а мовчання читалось би як «сховано нічого».
    # ⚠️ Спільний ключ `ui.measurement.coverage` тут НЕ береться: він каже «виміряно
    # X з Y» — про підмножину ВИМІРУ, не про часовий зріз. Збіг слова тут і був би
    # дефектом (той самий клас, що `ui.status.maintenance` у хроніці дерева).
    # ⚠️ Класи сирі, як і решта файлу, СВІДОМО: сторінка ще у фракції SECTOR, і
    # токен-текст на сирій поверхні дає гібрид, у якого лік протилежний (UI.1).
    # ⚠️ Межа називається ДАТОЮ, а не тривалістю («останні %{days} днів»), і це не
    # стиль: число з іменником після нього завело б ВОСЬМИЙ плюральний борг у мовах
    # із трьома формами (`I18N.1` тримає сім), а на аудит-поверхні межа й так
    # інформативніша за тривалість — її можна звірити з випискою, тривалість треба
    # рахувати. `I18n.l` бере формат із `rails-i18n`, тож нових ключів дати нуль.
    def render_window_notice
      return if @window_start.nil?

      p(class: "text-mini text-gray-600 mt-1") do
        plain t(".window.showing", since: I18n.l(@window_start.to_date, format: :long))
        whitespace
        a(href: blockchain_transactions_path(window: WINDOW_ALL),
          class: "underline decoration-emerald-900 text-emerald-600 hover:text-white transition-all " \
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500") { t(".window.show_all") }
      end
    end

    def transactions_table
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        table(class: "w-full text-left font-mono text-compact min-w-[640px]", role: "table") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
            tr do
              COLUMNS.each { |key, extra| th(scope: "col", class: "p-4 #{extra}".rstrip) { t(".table.#{key}") } }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            if @transactions.any?
              @transactions.each { |tx| render_transaction_row(tx) }
            else
              render Views::Shared::UI::EmptyState.new(
                title: t(".table.empty"),
                icon: "⬢",
                colspan: COLUMNS.size
              )
            end
          end
        end
      end
    end

    def render_transaction_row(tx)
      tr(class: "hover:bg-emerald-950/10 transition-colors") do
        td(class: "p-4") do
          # `uppercase` знято разом із сирим значенням: воно робило машинний токен
          # навмисним, а власну назву — криком, ще й ламало рядок у вузькій комірці.
          span(class: tokens("px-2 py-0.5 text-mini font-bold border", token_type_styles(tx.token_type))) { tx.token_type_label }
        end
        td(class: "p-4 text-white font-bold") { "#{tx.amount} #{tx.ticker}" }
        td(class: "p-4") do
          render Views::Shared::UI::StatusBadge.new(status: tx.status)
        end
        td(class: "p-4 text-gaia-text-muted text-mini uppercase") { tx.blockchain_network&.upcase || "—" }
        # [ARCH.98] Провенанс, а не дерево: cluster-sourced рухи (Celo-винагорода,
        # слеш останнього дерева) гаманця не мають ЗА ПОБУДОВОЮ, тож під міткою
        # «Дерево» вони показували тире — тобто мітка обіцяла координату, якої в
        # цього роду рядків не буває. Пара та сама, якою `for_organization`
        # резолвить приналежність; прецедент форми — `Alerts::Row`.
        td(class: "p-4 text-emerald-500") { tx.wallet&.tree&.did || tx.cluster&.name || "—" }
        td(class: "p-4 text-gray-600 truncate max-w-[150px] font-mono text-tiny") do
          if tx.tx_hash.present?
            # Тут aria_label НЕСУЧИЙ (на відміну від OnChainFrame): видимий текст —
            # обрізаний hex, скрінрідеру він нічого не каже. Тому перекладаємо, а не знімаємо.
            a(href: tx.explorer_url, target: "_blank", rel: "noopener noreferrer", aria_label: t(".explorer_aria"), class: "hover:text-emerald-500 underline decoration-emerald-900") { tx.tx_hash.first(16) + "..." }
          else
            # Прецедент і переклади вже стояли — `contracts/show` резолвить те саме
            # значення через `t(".ledger.pending_block")` у всіх чотирьох локалях.
            # Тобто тут була не відсутність дому, а сайт, що повз нього проїхав.
            # ⊥ Двійник у `wallets/transaction_row` лишається СИРИМ свідомо: він
            # рендериться всередині броадкасту, тож `t()` там замінив би чесний
            # англійський токен на локаль ПРОДЮСЕРА (`04_04 §8.1а`).
            span(class: "italic text-zinc-800") { t(".table.pending_block") }
          end
        end
        td(class: "p-4 text-right text-gray-500") { tx.created_at.strftime("%H:%M:%S // %d.%m.%y") }
        # [UI.8] Двері в deep-audit: `BlockchainTransactions::Show` був повністю
        # побудований, а зі списку на нього не вело НІЧОГО — єдиний лінк рядка йшов
        # у зовнішній експлорер. 🔴 `created_at` у параметрі НЕСУЧИЙ, не косметика:
        # таблиця RANGE-партиційна, і `find_with_partition_pruning` без нього падає
        # у degraded-path (`where(id:)` по ВСІХ партиціях + лічильник
        # `unpruned_lookups_total`) — тобто промах був би ТИХИЙ.
        td(class: "p-4 text-right") do
          a(href: blockchain_transaction_path(tx, created_at: tx.created_at.iso8601),
            aria_label: t(".audit_aria", id: tx.id),
            class: "text-emerald-600 hover:text-white transition-all focus-visible:outline-none " \
                   "focus-visible:ring-2 focus-visible:ring-emerald-500") { t(".audit_details") }
        end
      end
    end

    # `cusd` названий ЯВНО, а не лишений у `else`: третє значення enum'а, що живе
    # в мовчазному фолбеку, невідрізнимо від значення, якого ніхто не передбачив —
    # рівно так `manual_review` колись діставав стиль тьмяніший за `pending`.
    # `else` лишається fail-open для майбутнього члена (його поява червонить
    # `token_ticker_parity_spec`, тож німою вона не буде).
    def token_type_styles(type)
      case type
      when "carbon_coin" then "bg-emerald-900/20 text-emerald-400 border-emerald-500/30"
      when "forest_coin" then "bg-token-forest/20 text-token-forest border-token-forest/30"
      when "cusd" then "bg-zinc-900 text-zinc-400 border-zinc-700"
      else "bg-zinc-900 text-zinc-400 border-zinc-700"
      end
    end
  end
end
