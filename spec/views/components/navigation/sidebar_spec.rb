# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Navigation::Sidebar do
  # English copy lives in `config/locales/navigation/en.yml`. `:en` is already the
  # application default (04_04 §12.2), so this wrapper is belt-and-braces — it keeps
  # the assertions true even if a leaked locale or a future default change moves the
  # ambient one. Assert on a non-base locale only inside an explicit `with_locale`.
  # [UI.5] Пункти меню роле-гейтовані, тож дефолтний актор цих прикладів —
  # super_admin: вони пінять ПОВНОТУ меню (всі мітки, всі іконки, aria), а не
  # «що видно будь-кому». Сам фільтр пінить окрема група «роле-фільтр» нижче —
  # інакше ці приклади мовчки перетворились би на пін звуженого меню.
  let(:full_access_actor) { build_stubbed(:user, :super_admin) }

  def render_en(**kwargs)
    I18n.with_locale(:en) { render_component(current_user: full_access_actor, **kwargs) }
  end

  describe "logo section" do
    let(:html) { render_en }

    it "renders the Silken Net logo text" do
      expect(html).to include("Silken Net")
    end

    it "renders the subtitle in English when locale is :en" do
      expect(html).to include("Central Command Citadel")
    end

    it "renders the subtitle in Ukrainian when locale is :uk" do
      expect(I18n.with_locale(:uk) { render_component }).to include("Центральна Цитадель Управління")
    end

    it "uses gaia primary color for logo" do
      expect(html).to include("text-gaia-primary")
    end
  end

  describe "status pulse" do
    let(:html) { render_en }

    # [UI.17] Два приклади тут вимагали вигаданої величини («Sync: 1.12 THz») і
    # пульсуючої крапки при ній. Інвертовано, а не знято: та сама величина жила
    # ДВІЧІ — тут і в топбарі (`core_sync_value`), — тож пін на відсутність
    # мусить стерегти обидва написання, інакше повернення одного сайту виглядає
    # як чесне відновлення другого.
    it "не друкує вигаданої частоти синхронізації" do
      expect(html).not_to include("1.12")
      expect(html).not_to include("THz")
      expect(html).not_to include("ТГц")
    end

    it "renders version label" do
      expect(html).to include("v8.0.ocean")
    end

    it "не носить пульсуючої крапки при знятому написі" do
      expect(html).not_to include("animate-pulse")
    end
  end

  describe "section groups" do
    let(:html) { render_en }

    it "renders Strategic Insight section" do
      expect(html).to include("Strategic Insight")
    end

    it "renders Forest Operations section" do
      expect(html).to include("Forest Operations")
    end

    it "renders Neural Network section" do
      expect(html).to include("Neural Network")
    end

    it "renders Administration section" do
      expect(html).to include("Administration")
    end
  end

  describe "navigation items" do
    let(:html) { render_en }

    it "renders Strategic Insight nav items" do
      expect(html).to include("Oracle Visions")
      expect(html).to include("Treasury Matrix")
      expect(html).to include("NaaS Contracts")
      expect(html).to include("Blockchain Ledger")
      expect(html).to include("Reports Archive")
    end

    it "renders Forest Operations nav items" do
      expect(html).to include("Threat Alerts")
      expect(html).to include("Soldier Fleet")
      expect(html).to include("Maintenance Log")
      expect(html).to include("Crew Registry")
      expect(html).to include("Clan Hierarchy")
    end

    it "renders Neural Network nav items" do
      expect(html).to include("Queen Relays")
      expect(html).to include("Species DNA")
      expect(html).to include("Firmware OTA")
      expect(html).to include("Live Telemetry")
      expect(html).to include("Initiate Node")
    end

    it "renders Administration nav items" do
      expect(html).to include("Account Security")
      expect(html).to include("Notifications")
      expect(html).to include("Org Settings")
      expect(html).to include("Audit Log")
      expect(html).to include("System Audits")
      expect(html).to include("System Health")
    end
  end

  # [UI.5] Доти сайдбар не приймав користувача взагалі, тож investor бачив повне меню
  # платформи й на кожен гейтований пункт діставав сирий JSON-блоб (`render_forbidden`).
  # Рівень пункту вказує на предикат `User` — той самий, який читає гард контролера,
  # тож ці приклади стережуть саме ЗБІГ меню з гардом.
  describe "роле-фільтр пунктів [UI.5]" do
    def render_for(actor)
      I18n.with_locale(:en) { render_component(current_user: actor) }
    end

    # Усі 11 пунктів, закритих рольовим гардом контролера (вимір 2026-07-31).
    let(:gated_labels) do
      [ "Oracle Visions", "Maintenance Log", "Crew Registry", "Clan Hierarchy",
        "Species DNA", "Firmware OTA", "Initiate Node", "Org Settings",
        "Audit Log", "System Audits", "System Health" ]
    end

    it "ховає від investor кожен гейтований пункт" do
      html = render_for(build_stubbed(:user, :investor))

      gated_labels.each { |label| expect(html).not_to include(label) }
    end

    it "лишає investor пункти, доступні його ролі" do
      html = render_for(build_stubbed(:user, :investor))

      expect(html).to include("Treasury Matrix", "Threat Alerts", "Account Security")
    end

    it "відкриває forester польові пункти, але не адмінські" do
      html = render_for(build_stubbed(:user, :forester))

      expect(html).to include("Maintenance Log", "Initiate Node", "Oracle Visions")
      expect(html).not_to include("Org Settings", "System Health", "Clan Hierarchy")
    end

    it "відкриває admin адмінські пункти, крім super_admin-ексклюзиву" do
      html = render_for(build_stubbed(:user, :admin))

      expect(html).to include("Org Settings", "System Health", "Species DNA")
      expect(html).not_to include("Clan Hierarchy")
    end

    # Сторож дефолту: без актора компонент мусить звужуватись, а не роздавати
    # гейтоване. Забутий kwarg у шарі вище тоді дає видиме звуження, а не тиху діру.
    it "без актора звужується fail-CLOSED" do
      html = render_for(nil)

      gated_labels.each { |label| expect(html).not_to include(label) }
      expect(html).to include("Treasury Matrix")
    end
  end

  describe "icon rendering" do
    let(:html) { render_en }

    it "renders icon symbols for known icon names" do
      expect(html).to include("⊙")   # eye
      expect(html).to include("⬢")   # bank
      expect(html).to include("⚡")  # zap
      expect(html).to include("◈")   # users
      expect(html).to include("📡")  # radio
      expect(html).to include("⚙")   # cpu
      expect(html).to include("〰")  # activity
      expect(html).to include("🌳")  # tree
      expect(html).to include("▤")   # clipboard
    end
  end

  describe "active nav highlighting" do
    it "sets aria_current='page' on the active item" do
      html = render_en(current_path: "/alerts")
      expect(html).to include('aria-current="page"')
    end

    it "applies the active token classes to the matching nav item" do
      html = render_en(current_path: "/alerts")
      expect(html).to include("bg-gaia-primary-soft")
      expect(html).to include("border-gaia-primary")
    end

    it "does not set aria_current on non-matching items by default" do
      html = render_en(current_path: "/nonexistent")
      expect(html).not_to include('aria-current="page"')
    end

    # 🔴 [ARCH.77] Одиничність, а не присутність. Три приклади вище перевіряють, що
    # `aria-current` десь Є — тобто лишились би зеленими, якби префіксний матч
    # підсвітив ДВА пункти одразу. Саме цю вісь голий `start_with?` і відкривав.
    it "підсвічує рівно ОДИН пункт, а не всі з тим самим префіксом" do
      html = render_en(current_path: alerts_path)

      expect(html.scan('aria-current="page"').size).to eq(1)
    end

    # Шлях глибше за пункт меню лишається його дочірнім — межа сегмента, не рядок.
    it "тримає підсвітку на вкладеній сторінці розділу" do
      html = render_en(current_path: "#{clusters_path}/42")

      expect(html.scan('aria-current="page"').size).to eq(1)
    end

    # 🔴 Саме цей приклад відрізняє сегментний матч від підрядкового: шлях, що
    # ПОЧИНАЄТЬСЯ з адреси пункту, але не є його дочірнім (немає `/` на межі).
    # На голому `start_with?` пункт підсвітився б — тобто без цього приклада
    # обидві реалізації невідрізненні, і пін вище доводив би лише відсутність
    # колізії, а не механізм.
    it "не підсвічує пункт на сусідньому шляху зі спільним префіксом" do
      html = render_en(current_path: "#{clusters_path}-archive")

      expect(html).not_to include('aria-current="page"')
    end
  end

  describe "badge rendering" do
    context "when ews_alert_count is positive" do
      let(:html) { render_en(ews_alert_count: 5) }

      it "renders the badge with the count" do
        expect(html).to include("5")
      end

      it "applies status-danger token classes (theme-aware)" do
        expect(html).to include("bg-status-danger")
        expect(html).to include("text-status-danger-text")
      end
    end

    context "when ews_alert_count is zero" do
      let(:html) { render_en(ews_alert_count: 0) }

      it "does not render a badge" do
        expect(html).not_to include("bg-status-danger")
      end
    end
  end

  describe "live telemetry pulse" do
    let(:html) { render_en }

    it "renders animate-ping for the live telemetry indicator" do
      expect(html).to include("animate-ping")
    end
  end

  describe "aria attributes" do
    let(:html) { render_en }

    it "includes role=navigation on the aside element" do
      expect(html).to include('role="navigation"')
    end

    it "includes aria-label for main navigation" do
      expect(html).to include('aria-label="Silken Net"')
    end

    # [UI.3] aria-label на <a> ПЕРЕКРИВАВ дочірній текст для SR — EWS-badge
    # ставав нечутним. Лінки читаються дочірнім текстом (label + badge).
    it "does not put aria-label on nav items (children must be audible)" do
      expect(html).not_to include('aria-label="Oracle Visions"')
      expect(html).not_to include('aria-label="Threat Alerts"')
      expect(html).to include("Oracle Visions")
      expect(html).to include("Threat Alerts")
    end

    it "includes aria-hidden on icon spans" do
      expect(html).to include('aria-hidden="true"')
    end
  end

  describe "user footer section" do
    let(:html) { render_en }

    it "renders the user avatar placeholder" do
      expect(html).to include("A")
    end

    it "renders the user role label" do
      expect(html).to include("Architect")
    end

    it "renders access level text" do
      expect(html).to include("Full Access Link")
    end

    it "translates the footer role into Ukrainian when locale is :uk" do
      expect(I18n.with_locale(:uk) { render_component }).to include("Архітектор")
    end
  end

  describe "focus-visible accessibility" do
    let(:html) { render_en }

    it "includes focus-visible ring on nav items" do
      expect(html).to include("focus-visible:ring-2")
    end

    it "uses the gaia primary token for the focus ring" do
      expect(html).to include("focus-visible:ring-gaia-primary")
    end
  end

  describe "design system compliance" do
    let(:html) { render_en }

    it "uses gaia surface tokens, not raw Tailwind colors" do
      # Body of the sidebar should not leak raw bg-white/bg-black either.
      expect(html).not_to include("bg-white")
      expect(html).not_to include("bg-black")
      expect(html).not_to include("text-gray-900")
    end

    it "uses gaia border tokens for separators" do
      expect(html).to include("border-gaia-border")
    end
  end
end
