# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trees::Show do
  # Component is i18n-aware and every assertion here references English copy,
  # so the whole file is pinned to the base locale (04_04 §12.2). No non-base
  # locale is exercised in this file — a `:uk` render belongs in its own
  # `I18n.with_locale(:uk)` example, named after the locale it pins.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  let(:tree) { build_tree }
  let(:latest_log) { build_latest_log }
  let(:maintenance_history) { [ build_maintenance_record ] }
  let(:html) do
    render_component(tree: tree, latest_log: latest_log, maintenance_history: maintenance_history)
  end

  def build_tree(did: "SNET-00000042", status: "active", current_stress: 0.35,
                family_name: "Quercus Robur",
                device_uid: "HK-SOLDIER-042", scc_balance: 12.5,
                crypto_address: "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
                wallet_balance: 42.0, cluster_name: "Carpathian-Alpha",
                latitude: 49.4444, longitude: 32.0597,
                supply_voltage_mv: 3800, last_seen_at: 1.minute.ago,
                under_threat: false)
    family = TreeFamily.new(name: family_name)
    # 🔴 [TEST.12] `device_uid` — не окремий ідентифікатор, а САМ зовнішній ключ
    # (`belongs_to :tree, foreign_key: :device_uid, primary_key: :did`), тож на реальному
    # записі він ДОРІВНЮЄ DID власника. Мок вигадував "HK-SOLDIER-042" — значення, якого
    # прод не дає ніколи, і спека пінила саме його.
    hardware_key = device_uid ? HardwareKey.new : nil
    # 🔴 [TEST.12] Доти мок давав гаманцю `scc_balance: 12.5` І `balance: 42.0` як ДВА
    # незалежні поля — а `scc_balance` це `alias_attribute` на `balance`, тобто ОДНА
    # колонка. Фікстура оголошувала світ, неможливий за побудовою, і жоден приклад
    # не міг би цього побачити. Тепер значення одне.
    wallet = Wallet.new(balance: scc_balance, crypto_public_address: crypto_address)
    cluster = Cluster.new(name: cluster_name)

    # 🔴 [TEST.12] Реальний незбережений `Tree`, і головне тут — ТРИЯРУСНА деривація,
    # уже доведена в `trees/index` і `dashboard/map_node`: `supply_voltage_mv` сам НЕ колонка,
    # він виводиться з `latest_voltage_mv`; те саме `current_stress` ⇐ `latest_stress_index`.
    # Тож фікстура годує ПЕРШИЙ ярус, і саме перетворення стає перевірним.
    # ⚠️ `under_threat?` лишається стабом — це запит у БД (`ews_alerts.unresolved.exists?`),
    # а `active?` тепер приходить від справжнього статусу, не від синглтона.
    t = Tree.new(
      id: 1,
      did: did,
      status: status,
      latest_stress_index: current_stress,
      latest_voltage_mv: supply_voltage_mv,
      tree_family: family,
      hardware_key: hardware_key,
      wallet: wallet,
      cluster: cluster,
      latitude: latitude,
      longitude: longitude,
      last_seen_at: last_seen_at
    )
    allow(t).to receive(:under_threat?).and_return(under_threat)
    t
  end

  # 🔴 [TEST.12] Реальний незбережений `TelemetryLog`: усі три поля — колонки
  # `decimal`, тобто прод віддає BigDecimal, а `OpenStruct` віддавав Ruby-`Float`.
  # Доти це ховало живий дефект — Phlex не вмів друкувати BigDecimal узагалі, тож
  # сюїта бачила «28.7» там, де прод малював порожній `text-6xl`. ⚠️ Корінь знято
  # (`ApplicationComponent#format_object`), тому саме ЦЕЙ пін більше не червоніє на
  # знятому `&.to_f` — виміряно мутацією; сьогодні ту вимогу тримає лише
  # `spec/quality/phlex_bigdecimal_render_spec.rb`. Дім класу → `04_04 §2`.
  def build_latest_log(z_value: 28.7, voltage_mv: 3800, temperature_c: 22, created_at: 5.minutes.ago)
    TelemetryLog.new(
      z_value: z_value,
      voltage_mv: voltage_mv,
      temperature_c: temperature_c,
      created_at: created_at
    )
  end

  # [TEST.12] Реальний незбережений `MaintenanceRecord`: `action_type` ходить через
  # справжній enum, тож вигаданих `"sensor_replacement"`/`"calibration"` тут більше
  # немає — модель приймає лише `installation`/`inspection`/`cleaning`/`repair`/
  # `decommissioning`/`biomass_extraction`, і на будь-якому іншому значенні кидає
  # `ArgumentError` просто в конструкторі.
  def build_maintenance_record(technician: "Ivan Koval", action_type: :repair,
                               notes: "Replaced corroded electrode on north-facing anchor point",
                               performed_at: 2.days.ago)
    first, last = technician.to_s.split(" ", 2)
    MaintenanceRecord.new(
      user: User.new(first_name: first, last_name: last),
      action_type: action_type,
      notes: notes,
      performed_at: performed_at
    )
  end

  describe "argument validation" do
    it "raises ArgumentError if tree does not respond to :did" do
      expect {
        component_class.new(tree: Object.new, latest_log: nil, maintenance_history: [])
      }.to raise_error(ArgumentError, /did/)
    end
  end

  describe "header" do
    it "displays tree DID" do
      expect(html).to include("SNET-00000042")
    end

    it "displays the tree status" do
      expect(html).to include("active")
    end

    it "displays family name" do
      expect(html).to include("Quercus Robur")
    end

    it "displays uplink timestamp from latest_log" do
      frozen_time = Time.zone.parse("2025-06-10 14:30:00")
      log = build_latest_log(created_at: frozen_time)
      rendered = render_component(tree: tree, latest_log: log, maintenance_history: maintenance_history)
      expect(rendered).to include("14:30:00 // 10.06.25")
    end

    it "shows SILENT when no latest_log" do
      rendered = render_component(tree: tree, latest_log: nil, maintenance_history: maintenance_history)
      expect(rendered).to include("SILENT")
    end
  end

  # Статус іде через спільний `StatusBadge` (I18N.1, 2026-08-05) — приватна
  # `status_color_class` знесена; вона схлопувала `removed`+`deceased` в одну
  # червону гілку, тоді як централізована мапа їх розрізняє.
  describe "status badge colors" do
    it "renders active with the success token, never danger" do
      expect(html).to include("bg-status-success")
      expect(html).not_to include("bg-status-danger")
    end

    it "renders dormant with the warning token" do
      t = build_tree(status: "dormant")
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      expect(rendered).to include("bg-status-warning")
    end

    it "renders deceased with the danger token" do
      t = build_tree(status: "deceased")
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      expect(rendered).to include("bg-status-danger")
    end
  end

  describe "family name" do
    it "displays 'Unknown' when family is nil" do
      t = build_tree(family_name: nil)
      t.tree_family = TreeFamily.new(name: nil)
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      expect(rendered).to include("Unknown")
    end
  end

  describe "biometric panel" do
    it "displays z_value from latest_log" do
      expect(html).to include("28.7")
    end

    it "displays --- when no latest_log z_value" do
      rendered = render_component(tree: tree, latest_log: nil, maintenance_history: maintenance_history)
      expect(rendered).to include("---")
    end

    it "displays voltage" do
      expect(html).to include("3800")
      expect(html).to include("mV")
    end

    it "displays temperature" do
      expect(html).to include("22")
      expect(html).to include("°C")
    end

    it "displays stress index percentage" do
      expect(html).to include("35.0%")
    end

    # [ARCH.84] 🔴 Жодна фікстура файлу не доходила до nil (`build_latest_log` подає
    # 3800/22), тож дефект «виміряний нуль на місці невиміряного» був невидимий ЗА
    # ПОБУДОВОЮ — фікс не червонив жодного наявного прикладу. Негативна половина
    # несуча: без неї пін пройшов би і на `|| 0`, бо «0 mV» теж містить «mV».
    it "says NOT MEASURED for an absent sensor reading, never a fabricated zero" do
      rendered = render_component(tree: tree,
                                  latest_log: build_latest_log(voltage_mv: nil, temperature_c: nil), maintenance_history: maintenance_history)

      expect(rendered).to include(I18n.t("ui.measurement.not_measured"))
      expect(rendered).not_to include("0 mV")
      expect(rendered).not_to include("0 °C")
    end

    # [ARCH.86] Підпис під `text-6xl`-числом називає безрозмірну ВЕЛИЧИНУ,
    # а не одиницю: «kΩ Impedance» стояло на координаті атрактора Лоренца.
    it "labels the big number as the dimensionless Lorenz Z" do
      expect(html).to include("Lorenz Z (dimensionless)")
      expect(html).not_to include("Impedance")
    end
  end

  describe "radial SVG" do
    it "renders SVG element" do
      expect(html).to include("<svg")
    end

    it "calculates correct stroke-dashoffset" do
      # offset = 552 * (1 - 0.35) = 552 * 0.65 = 358.8
      expect(html).to include("stroke-dashoffset: 358.8")
    end

    it "uses emerald stroke when not under threat" do
      expect(html).to include("stroke-emerald-500")
    end

    it "uses red pulse stroke when under threat" do
      t = build_tree(under_threat: true)
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      expect(rendered).to include("stroke-red-600")
      expect(rendered).to include("animate-pulse")
    end
  end

  describe "maintenance ledger" do
    it "displays table headers" do
      expect(html).to include("Technician")
      expect(html).to include("Action")
      expect(html).to include("Observations")
      expect(html).to include("Timestamp")
    end

    it "displays technician name" do
      expect(html).to include("Ivan Koval")
    end

    # [I18N.1] Мітка, не сирий токен — і в не-базовій локалі, де вони не збігаються.
    # ⚠️ Очікуємо «Ремонт», а не «РЕМОНТ»: великі літери тут дає CSS (`uppercase`), а він
    # НЕ міняє текст у розмітці — оракул береться з реального виводу, не з вигляду.
    it "displays a human action-type label" do
      expect(I18n.with_locale(:uk) do
        render_component(tree: tree, latest_log: latest_log, maintenance_history: maintenance_history)
      end).to include("Ремонт")
    end

    it "truncates long notes to 50 characters" do
      long_notes = "A" * 100
      record = build_maintenance_record(notes: long_notes)
      rendered = render_component(tree: tree, latest_log: latest_log, maintenance_history: [ record ])
      expect(rendered).to include("A" * 47 + "...")
    end

    it "shows empty state when no maintenance records" do
      rendered = render_component(tree: tree, latest_log: latest_log, maintenance_history: [])
      expect(rendered).to include("No physical interventions recorded")
    end
  end

  describe "economic panel" do
    it "displays wallet balance" do
      expect(html).to include("12.5")
    end

    # [ARCH.88] Панель показує БАЛИ росту — і заголовок, і одиниця мусять це
    # називати; тікер монети тут завищував величину в 10 000×.
    it "displays the GP unit label, never the coin ticker" do
      expect(html).to include("GP")
      expect(html).not_to include("SCC")
    end

    it "truncates crypto address" do
      expect(html).to include("0xABCDEF1234...")
    end

    it "shows NOT_PROVISIONED when no wallet address" do
      t = build_tree(crypto_address: nil)
      t.wallet.crypto_public_address = nil
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      expect(rendered).to include("NOT_PROVISIONED")
    end
  end

  # 🔴 [ARCH.84] Носій пінить ЗГОДУ двох сторінок, бо ламалась саме вона:
  # `trees/index` читав `Tree#fresh_signal?` (24 год, ARCH.99), а ця сторінка
  # мала власні 15 хв від `@latest_log.created_at`. Обидві величини
  # штампуються в одній транзакції, тож розходились ПОРОГИ — одне дерево було
  # зеленим у списку й мертвим тут ~23 год 45 хв із кожних 24.
  #
  # ⚠️ Пін на ОДНУ сторінку цього не побачив би за побудовою: кожен рендер
  # окремо самоузгоджений, суперечність існує лише між ними.
  describe "живість дерева — та сама відповідь, що в списку [ARCH.84]" do
    # ⚠️ Цілимось у ВІДБИТОК кожного LED, не в `bg-emerald-500`: на обох
    # сторінках є інші смарагдові вузли, і широкий матч зробив би приклад
    # вакуумним (той самий промах уже коштував у цій сесії). Радіус тіні
    # різний — 12px на сторінці, 5px у списку, — і це надійний дискримінатор.
    def show_led_green?(markup)  = markup.include?("bg-emerald-500 shadow-[0_0_12px_#10b981]")
    def index_led_green?(markup) = markup.include?("bg-emerald-500 shadow-[0_0_5px_#10b981]")

    # 2 години: усередині канонного порога тиші (24 год) і ЗА МЕЖАМИ знятих
    # 15 хв — тобто рівно те вікно, де дві сторінки не сходились.
    let(:seen_two_hours_ago) { build_tree.tap { |t| t.last_seen_at = 2.hours.ago } }

    # ⚠️ Через `renderer`, а не `.call`: список будує `tree_path`, тобто
    # потребує view-контексту — прямий виклик падає `default_url_options`.
    def index_markup(tree)
      ApplicationController.renderer.render(
        Trees::Index.new(cluster: tree.cluster, trees: [ tree ]), layout: false
      )
    end

    it "показує ЖИВИМ дерево, яке список теж вважає живим" do
      t = seen_two_hours_ago
      shown = render_component(tree: t, latest_log: nil,
                               maintenance_history: maintenance_history)

      expect(show_led_green?(shown)).to be(true)
      expect(index_led_green?(index_markup(t))).to be(true)
    end

    it "показує МЕРТВИМ дерево, яке список теж вважає мертвим" do
      t = build_tree.tap { |x| x.last_seen_at = 30.hours.ago }
      shown = render_component(tree: t, latest_log: nil,
                               maintenance_history: maintenance_history)

      expect(show_led_green?(shown)).to be(false)
      expect(index_led_green?(index_markup(t))).to be(false)
    end

    # ⊕ Тихіша половина: `@latest_log` — це останній РЯДОК телеметрії, тобто
    # `nil` після retention-зрізу. Доти сторінка називала таке дерево мертвим,
    # хоч його власний `last_seen_at` живий.
    it "не називає мертвим дерево, чиї логи зрізав retention" do
      t = seen_two_hours_ago
      shown = render_component(tree: t, latest_log: nil,
                               maintenance_history: maintenance_history)

      expect(show_led_green?(shown)).to be(true)
    end
  end

  describe "hardware security vault" do
    it "displays device_uid" do
      expect(html).to include("SNET-00000042") # = DID власника, бо `device_uid` і є FK
    end

    it "shows NOT_PROVISIONED when hardware key is nil" do
      t = build_tree(device_uid: nil)
      t.hardware_key = nil
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      expect(rendered).to include("NOT_PROVISIONED")
    end

    # 🔴 [ARCH.84] Доти цей самий рендер ОДНОЧАСНО казав «не провіжінено» і
    # «анкер перевірено» + «канал зашифровано»: три рядки нижче були
    # безумовними літералами поруч із чесним сусідом. Приклад вище цього не
    # бачив — він пінив лише присутність `NOT_PROVISIONED`, а суперечність
    # жила у ВІДСУТНОСТІ решти.
    it "не заявляє шифру й анкера для дерева БЕЗ ключа" do
      t = build_tree(device_uid: nil)
      t.hardware_key = nil
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)

      expect(rendered).to include("NOT_PROVISIONED")
      expect(rendered).not_to include("AES-128-ECB")
      expect(rendered).not_to include("Anchor provisioned")
      expect(rendered).not_to include("Channel Encrypted")
    end

    # ⊥ Дзеркало: доводить, що приклад вище не просто «нічого не рендерить».
    it "показує всі чотири рядки, коли ключ Є" do
      expect(html).to include("AES-128-ECB", "Channel Encrypted", "Anchor provisioned")
    end

    # 🔴 «Verified Hardware Anchor» було твердженням БЕЗ ДЖЕРЕЛА: поля
    # верифікації на `HardwareKey` не існує взагалі. Замінено на реальну
    # колонку `key_version` (`NOT NULL DEFAULT 0`), яка до того ж робить
    # видимою ротацію [FW.17].
    it "друкує РЕАЛЬНУ версію ключа, а не вигадану «верифікацію»" do
      expect(html).to include("key v0")
      expect(html).not_to include("Verified Hardware Anchor")
    end

    it "displays cipher suite info" do
      # Post-ARCH.42: Tree LoRa channel — AES-128-ECB (locale label).
      expect(html).to include("AES-128-ECB")
    end

    # [UI.7] Приклад на кнопку ротації знято разом із самою кнопкою (interim-стаб
    # ARCH.69): вона була голим `<button>` без маршруту й без викликача сервісу.
    # Повертається разом із дротуванням.
  end

  describe "metadata panel" do
    it "displays cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "displays coordinates" do
      expect(html).to include("49.4444")
      expect(html).to include("32.0597")
    end

    it "includes Google Maps link" do
      expect(html).to include("google.com/maps")
      expect(html).to include("49.4444")
    end

    it "includes focus-visible accessibility ring" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "chronicle turbo frame" do
    it "renders a lazy-loaded turbo frame" do
      expect(html).to include("tree_chronicle")
      expect(html).to include('loading="lazy"')
    end
  end

  describe "edge cases — nil-safe rendering of optional fields" do
    it "renders 'Unknown' technician when maintenance record has no user" do
      record = MaintenanceRecord.new(user: nil, action_type: :inspection,
                                     notes: "Quick recalibration", performed_at: 1.day.ago)
      rendered = render_component(tree: tree, latest_log: latest_log, maintenance_history: [ record ])
      expect(rendered).to include("Unknown")
    end

    # 🔴 [TEST.12] Тут доти стояв `OpenStruct` — і сусідній приклад ЦЬОГО Ж блоку
    # вже будував справжній `MaintenanceRecord`, тобто асиметрія лежала в межах
    # одного `describe`. Ціна не гігієнічна: компонент друкує
    # `record.action_type_label` — ПОХІДНИЙ i18n-метод (`I18n.t(scope.action_type)`),
    # якого `OpenStruct` із самим `action_type:` не обчислює, тож віддавав `nil` і
    # комірка дії рендерилась ПОРОЖНЬОЮ в обох прикладах. Жоден пін цього не бачив:
    # обидва пінили `include("—")`, а та риска приходить із СУСІДНЬОЇ комірки.
    # `notes` тут подається через `attributes=` після `.new`, бо валідація
    # `length: { minimum: 10 }` на незбереженому записі не спрацьовує.
    it "renders '—' when maintenance notes are nil" do
      record = MaintenanceRecord.new(user: User.new(first_name: "Olha", last_name: "K"),
                                     action_type: :inspection, notes: nil, performed_at: 1.day.ago)
      rendered = render_component(tree: tree, latest_log: latest_log, maintenance_history: [ record ])
      expect(rendered).to include("—")
    end

    it "renders '—' when maintenance performed_at is nil" do
      record = MaintenanceRecord.new(user: User.new(first_name: "Olha", last_name: "K"),
                                     action_type: :inspection, notes: "Sane enough", performed_at: nil)
      rendered = render_component(tree: tree, latest_log: latest_log, maintenance_history: [ record ])
      expect(rendered).to include("—")
    end

    # 🔴 Пін, який доти був НЕМОЖЛИВИЙ: доки запис підроблявся `OpenStruct`-ом,
    # похідна мітка дорівнювала `nil` при будь-якій поведінці компонента, тож
    # цілий стовпчик «дія» не мав жодного свідка. Цілимось у САМУ комірку, а не
    # в документ: слово «Inspection» трапляється й в інших вузлах сторінки.
    it "prints the derived action label in its own cell" do
      record = MaintenanceRecord.new(user: User.new(first_name: "Olha", last_name: "K"),
                                     action_type: :inspection, notes: "Sane enough", performed_at: 1.day.ago)
      rendered = render_component(tree: tree, latest_log: latest_log, maintenance_history: [ record ])

      cells = Nokogiri::HTML5.fragment(rendered).css("td").map { |td| td.text.strip }
      expect(cells).to include(MaintenanceRecord.action_type_label(:inspection))
    end

    it "renders '0.0' SCC when tree has no wallet" do
      t = build_tree
      t.wallet = nil
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      expect(rendered).to include("0.0")
      expect(rendered).to include("NOT_PROVISIONED")
    end

    it "renders without a cluster when tree.cluster is nil" do
      t = build_tree
      t.cluster = nil
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      # Should still render the metadata panel without crashing
      expect(rendered).to include("Deployment")
    end

    it "falls back to 'Unknown' family when tree.tree_family is nil entirely" do
      t = build_tree(family_name: "ignored")
      t.tree_family = nil
      rendered = render_component(tree: t, latest_log: latest_log, maintenance_history: maintenance_history)
      expect(rendered).to include("Unknown")
    end
  end
end
