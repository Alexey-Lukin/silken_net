# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Asset-resolving stubs are applied globally via spec/support/layout_asset_stubs.rb.

RSpec.describe DashboardLayout do
  def mock_user(first_name: "Olena", last_name: "Kovalenko",
                role: "admin", email_address: "olena@example.org",
                super_admin: false)
    u = OpenStruct.new(
      first_name: first_name,
      last_name: last_name,
      role: role,
      email_address: email_address
    )
    u.define_singleton_method(:full_name) { "#{first_name} #{last_name}" }
    # [I18N.1] Мітку бере ДІМ (`User.role_label`), а не сама фікстура: інакше мок став би
    # другою деривацією й показував би мітку там, де застосунок показав би сире значення.
    u.define_singleton_method(:role_label) { User.role_label(role) }
    # ОБИДВА предикати, і це не надмірність: `super_admin?` читає індикатор
    # контексту, `role_super_admin?` — делегат під ним, а сайдбар питає перший.
    # Визначити лише один означало б змоделювати актора, який одночасно
    # super_admin і ні — стан, неможливий у застосунку, крізь який пін тихо
    # проходить.
    u.define_singleton_method(:role_super_admin?) { super_admin }
    u.define_singleton_method(:super_admin?) { super_admin }
    u
  end

  # Minimal content component for testing layout rendering.
  let(:content_stub) do
    Class.new(ApplicationComponent) do
      def view_template
        div(id: "test-content") { "Layout Content Rendered" }
      end
    end.new
  end
  let(:html) { render_layout(content: content_stub) }

  def render_layout(title: "Dashboard", current_path: "/dashboard",
                    ews_alert_count: 0, user: nil, acting_organization: nil, content: nil)
    current_user = user || mock_user
    ApplicationController.renderer.render(
      component_class.new(
        title: title,
        current_user: current_user,
        current_path: current_path,
        ews_alert_count: ews_alert_count,
        acting_organization: acting_organization,
        content: content
      ),
      layout: false
    )
  end


  # [UI.6] Індикатор робочого контексту. Він же — єдиний канал підтвердження
  # перемикання: цей layout `flash` не рендерить, і `switch` його не ставить.
  describe "індикатор робочого контексту" do
    let(:acting_org) { OpenStruct.new(id: 7, name: "GreenFund Ltd") }

    it "показує super_admin, у чиєму контексті він працює" do
      html = render_layout(user: mock_user(super_admin: true), acting_organization: acting_org)

      expect(html).to include("GreenFund Ltd")
      # 🔴 Пінимо `context_label`, а НЕ `href` реєстру: той самий href віддає пункт
      # сайдбара `clan_hierarchy` (super_admin-only), тож пін на нього був би
      # задоволений сусіднім елементом — класика «пін проходить через сусіда».
      expect(html).to include("Context")
    end

    it "несе назву організації в доступному імені, а не глушить її" do
      html = render_layout(user: mock_user(super_admin: true), acting_organization: acting_org)

      # [UI.3] `aria-label` на `<a>` замінює доступне імʼя цілком. Якщо назва не
      # інтерпольована в мітку, SR-користувач ніколи не почує, В ЯКІЙ організації
      # він працює — тобто «єдиний канал підтвердження» для нього мовчить.
      expect(html).to include(%(aria-label="Acting context: GreenFund Ltd. Change organization"))
    end

    it "каже «не обрано», коли контексту ще немає — це типовий перший вхід" do
      html = render_layout(user: mock_user(super_admin: true))

      expect(html).to include("NOT_SELECTED")
    end

    it "не показує індикатора іншим ролям — контекст для них незмінний" do
      html = render_layout(user: mock_user, acting_organization: acting_org)

      expect(html).not_to include("NOT_SELECTED")
      expect(html).not_to include("Acting context:")
    end
  end

  describe "page title in head" do
    it "renders the title with Silken Net prefix" do
      html = render_layout(title: "Forest Matrix")
      expect(html).to include("Silken Net // Forest Matrix")
    end

    it "includes the title in a <title> tag" do
      html = render_layout(title: "Alerts")
      expect(html).to include("<title>")
      expect(html).to include("Alerts")
    end
  end

  # 🔴 [UI.1] Тему ставить CSS і тільки CSS — inline-скрипта теми в `<head>` уже
  # немає, клієнтського стану немає теж. Піни на ВІДСУТНІСТЬ, бо рецидив тут
  # приходить під виглядом полагодження («поверну FOUC-скрипт, щоб не блимало»)
  # і повертає одразу дві хвороби: недетермінований рендер (скріншот залежить
  # від того, чи виконався JS) і залежність від CSP — той скрипт не ніс nonce,
  # тож під `CSP_ENFORCE=true` він блокується й тема не застосовується взагалі.
  #
  # ⚠️ Тут доти стояв пін `include("dark")`. Він був хибно-зеленим за
  # побудовою: слово «dark» живе в розмітці незалежно від скрипта, тож приклад
  # не міг упасти й атестував наявність механізму, якого не перевіряв.
  describe "theme has no client-side shaft" do
    it "carries no client-side theme state" do
      expect(html).not_to include("localStorage")
    end

    it "carries no inline theme script" do
      expect(html).not_to include("classList.add")
    end
  end

  describe "breadcrumb from path" do
    it "renders the localized root breadcrumb (Цитадель under :uk locale)" do
      I18n.with_locale(:uk) { expect(render_layout).to include("Цитадель") }
    end

    it "renders the English root breadcrumb under :en locale" do
      I18n.with_locale(:en) { expect(render_layout).to include("Citadel") }
    end

    it "renders path segments from current_path" do
      html = render_layout(current_path: "/trees")
      expect(html).to include("Trees")
    end

    # 🔴 [ARCH.77] НЕГАТИВНА половина, без якої всі приклади цього блоку вічно
    # зелені: вони перевіряють, що змістовний сегмент Є, і задовольнились би
    # хвостом `Api // V1 // Trees`. Саме цю половину зрізав перехід із `drop(2)`
    # на `delete_prefix` — мутація префікса на порожній рядок червонить рівно тут.
    it "не показує службовий префікс контуру серед крихт" do
      html = render_layout(current_path: "/trees")

      expect(html).not_to include(">Api<")
      expect(html).not_to include(">V1<")
    end

    it "renders nested path segments" do
      html = render_layout(current_path: "/maintenance_records")
      expect(html).to include("Maintenance records")
    end

    # 🔴 [I18N.1] Свідок механізму мусить жити в НЕ-базовій локалі: в `en` мітка
    # `navigation.breadcrumb.segments.trees` дорівнює `"trees".humanize`
    # ПОБАЙТОВО, тож приклад вище зелений і з домом мітки, і з сирим `.humanize`
    # — про сам механізм він не свідчить нічого (`04_06 §B.2` BP #16-клас).
    # Негативна половина обовʼязкова: без неї регресія на `.humanize` пройшла б
    # непоміченою, бо українська сторінка й далі містила б слово «Дерева» з
    # інших вузлів.
    it "resolves a path segment through the label home, not .humanize (uk)" do
      html = I18n.with_locale(:uk) { render_layout(current_path: "/trees") }

      expect(html).to include("Дерева")
      expect(html).not_to include(">Trees<")
    end

    # Числовий сегмент — це ID, а не слово: він мусить пройти НАСКРІЗЬ, не
    # шукаючи мітки. Пін живе в не-базовій локалі свідомо — саме там видно, що
    # гард за типом спрацював, а не фолбек `.humanize`.
    it "passes a numeric id segment through untranslated (uk)" do
      html = I18n.with_locale(:uk) { render_layout(current_path: "/trees/42") }

      expect(html).to include('class="text-gaia-text-muted">42<')
    end

    it "only styles the last of several path segments as muted (breadcrumb tail)" do
      html = render_layout(current_path: "/trees/42")
      expect(html).to include("Trees")
      expect(html).to include("42")
      # Only the trailing segment ("42") gets the muted "last-crumb" class.
      expect(html).to include('class="text-gaia-text-muted">42<')
    end
  end

  describe "user avatar letter" do
    it "renders the first letter of the user's first name" do
      html = render_layout(user: mock_user(first_name: "Ivan"))
      # Avatar displays the first letter
      expect(html).to include("I")
    end

    it "renders the user full name in top bar" do
      html = render_layout(user: mock_user(first_name: "Olena", last_name: "Kovalenko"))
      expect(html).to include("Olena Kovalenko")
    end

    # [I18N.1] Не-базова локаль: «admin» є підрядком «Administrator», тож у en цей пін
    # не розрізняв би сирий enum від людської мітки. Напис видно на КОЖНІЙ сторінці.
    it "renders the user role as a human label" do
      I18n.with_locale(:uk) do
        html = render_layout(user: mock_user(role: "admin"))

        expect(html).to include("Адміністратор")
        expect(html).not_to include(">admin<")
      end
    end
  end

  describe "sidebar rendering" do
    it "renders the sidebar navigation" do
      expect(html).to include("sidebar-navigation")
    end

    # [UI.11] 🔴 Пін на ЗВʼЯЗКУ id+атрибут, а не на щось із двох окремо — і це не
    # педантизм: наявний пін вище стереже лише `id`, тож повернення
    # `data-turbo-permanent` завтра лишилось би зеленим, а зняття сьогодні не дало
    # б жодного сигналу. Тобто без цього рядка зміна невидима для CI В ОБИДВА БОКИ.
    #
    # Чому атрибута тут бути не може: Turbo при кожному Drive-візиті пересаджує
    # permanent-вузол (Bardo) і викидає свіжу серверну розмітку, а morph такі вузли
    # пропускає взагалі. Всередині сайдбара — ДВА серверні значення: бейдж
    # `ews_alert_count` і `aria-current` із `current_path`. Тобто на десктопі
    # лічильник ТРИВОГ і підсвітка меню замерзали на першому завантаженні, тоді як
    # мобільний drawer (той самий компонент без атрибута) лишався свіжим.
    #
    # ⚠️ Виміряно перед зняттям (браузерна проба, ворота пункту): `scrollTop`
    # сайдбара Turbo-візит НЕ переживає навіть із permanent (150 → 0), тож
    # єдиний кандидат на втрату виявився вже втраченим. Клієнтського стану в
    # сайдбарі нема — нуль Stimulus-контролерів.
    it "не позначає сайдбар permanent — інакше серверні дані в ньому замерзають" do
      expect(html).not_to match(/id="sidebar-navigation"[^>]*data-turbo-permanent/)
    end
  end

  describe "main layout structure" do
    it "renders the main role element" do
      expect(html).to include('role="main"')
    end

    it "renders as a full HTML document" do
      expect(html).to match(/<!doctype html>/i)
    end

    it "renders the html element with h-full class" do
      expect(html).to include("h-full")
    end
  end

  describe "content rendering" do
    it "renders the content component inside the main area" do
      expect(html).to include("Layout Content Rendered")
    end

    it "renders content inside test-content div" do
      expect(html).to include("test-content")
    end

    it "renders without errors when content is nil" do
      html = render_layout(content: nil)
      expect(html).to include("Citadel")
    end
  end

  describe "ews_alert_count" do
    it "does not render an alert badge when ews_alert_count is 0" do
      html = render_layout(ews_alert_count: 0, content: content_stub)
      # Badge is only rendered when badge&.positive? — so zero means no bg-status-danger span
      expect(html).not_to include("bg-status-danger text-status-danger-text text-micro px-1.5")
    end

    it "renders a visible alert badge with the count when ews_alert_count is positive" do
      html = render_layout(ews_alert_count: 7, content: content_stub)
      # The sidebar nav_item renders a <span> badge when badge.positive?
      expect(html).to include("bg-status-danger")
      expect(html).to include(">7<")
    end
  end

  describe "top bar" do
    it "renders top-bar fallbacks when current_user is nil" do
      html = ApplicationController.renderer.render(
        component_class.new(
          title: "Dashboard", current_user: nil, current_path: "/dashboard",
          ews_alert_count: 0, content: content_stub
        ),
        layout: false
      )

      expect(html).to include("Layout Content Rendered")
      expect(html).to include(">A<") # avatar fallback when first_name is unavailable
    end

    # 🔴 [UI.17] `render_system_telemetry` друкував тут «Core Sync: 1.12 THz» із
    # пульсуючою крапкою — ТУ САМУ вигадану величину, що й сайдбар. Пін на
    # відсутність стоїть В ОБОХ домах свідомо: сайдбарний приклад бачить лише
    # свій компонент, тож без цього половина класу лишилась би без носія, а
    # повернення топбар-сайту читалось би як відновлення симетрії.
    it "не друкує вигаданої частоти ядра (UI.17)" do
      expect(html).not_to include("1.12")
      expect(html).not_to include("THz")
      expect(html).not_to include("ТГц")
      expect(html).to include("Layout Content Rendered") # ліхтар: рендер справді відбувся
    end
  end
end
