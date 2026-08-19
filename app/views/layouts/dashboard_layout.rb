# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class DashboardLayout < ApplicationComponent
  include Phlex::Rails::Layout

  # @param title [String] page title
  # @param current_user [User] authenticated user (passed from controller)
  # @param current_path [String] request path for nav highlighting + breadcrumbs
  # @param ews_alert_count [Integer] pre-computed unresolved alert count (eager-load in controller)
  # @param acting_organization [Organization, nil] організація, в контексті якої
  #   виконується запит [UI.6]
  # @param content [Phlex::HTML, nil] page content component to render inside layout
  #
  # 🔴 Індикатор контексту тут — не оздоба, але причина ВУЖЧА, ніж тут стояла.
  # Доти писалось «`organizations#switch` flash не ставить, тож індикатор —
  # ЄДИНИЙ канал»: знято [SEC.25 Ф3], перемикач ставить `success`. Індикатор
  # лишається несучим тому, що показує контекст ПОСТІЙНО, тоді як повідомлення
  # живе один запит — тобто super_admin, який відкрив сторінку пізніше, з flash
  # уже нічого не дізнався б. ⚠️ Тут доти стояло ще й «цей layout не рендерить
  # `flash` УЗАГАЛІ» — правда до [SEC.25]; тепер рендерить, і саме тому flash-
  # сайти контролерів перестали бути німими (число не фіксуємо — дрейфує).
  # @param flash [Hash] повідомлення поточного запиту — див. `Shared::UI::FlashMessages`
  def initialize(title:, current_user:, current_path: "/", ews_alert_count: 0,
                 acting_organization: nil, flash: {}, content: nil)
    @title = title
    @current_user = current_user
    @current_path = current_path
    @ews_alert_count = ews_alert_count
    @acting_organization = acting_organization
    @flash = flash
    @content = content
  end

  # [I18N.1] Дім мітки СЕГМЕНТА шляху — одна деривація ключа на застосунок
  # (`04_04 §12.14`). Форма — class-метод рендерера, бо дім мапи і є цей layout:
  # крихти більше ніхто не малює.
  #
  # 🔴 `navigation.items.*` тут НЕ реюзиться, і це вимір, не смак: ті ключі
  # називають пункт МЕНЮ семантично (`soldier_fleet` → `/clusters`,
  # `treasury_matrix` → `/wallets`), а крихта показує імʼя РЕСУРСУ в URL —
  # збігів 4 з 21, ще й регістр інший (Title Case проти `.humanize`). Джерело
  # істини для МНОЖИНИ сегментів — `Rails.application.routes`, не модель.
  BREADCRUMB_SEGMENT_SCOPE = "navigation.breadcrumb.segments"

  # Fail-open (`04_04 §12.14`): невідомий сегмент рендериться `.humanize`, як
  # доти — нова сторінка зʼявляється, не чекаючи на переклад. Повноту множини
  # стереже `spec/i18n/breadcrumb_segment_parity_spec.rb`, а не цей `default:`.
  #
  # 🔴 Числовий сегмент — це ID, а не слово: він виходить ДО пошуку. Інакше
  # кожен перегляд картки робив би промах по каталогу заради рядка, що й так
  # повернеться собою.
  def self.breadcrumb_segment_label(segment)
    value = segment.to_s
    return value if value.match?(/\A\d+\z/)

    I18n.t("#{BREADCRUMB_SEGMENT_SCOPE}.#{value}", default: value.humanize)
  end

  def view_template
    doctype
    html(class: "h-full", lang: I18n.locale.to_s) do
      render_head
      body(class: "h-full font-mono antialiased bg-gaia-surface-base text-gaia-text overflow-hidden transition-colors duration-300") do
        div(class: "flex h-full overflow-hidden", data: { controller: "mobile-nav" }) do
          render Views::Shared::UI::FlashMessages.new(messages: @flash)
          render_desktop_sidebar
          render_mobile_drawer

          # ГОЛОВНИЙ ТЕРМІНАЛ
          main(class: "flex-1 flex flex-col min-w-0 bg-gaia-surface-base relative transition-colors duration-300", role: "main") do
            # Фоновий шум (текстура Цитаделі) — лише в dark, тонко.
            div(class: "absolute inset-0 opacity-5 pointer-events-none dark:bg-[url('https://www.transparenttextures.com/patterns/carbon-fibre.png')]", aria_hidden: "true")

            render_top_bar

            div(class: "flex-1 overflow-y-auto p-4 md:p-8 custom-scrollbar relative z-10") do
              div(class: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8") do
                render @content if @content
              end
            end
          end
        end
      end
    end
  end

  private

  def render_head
    head do
      title { "Silken Net // #{@title}" }
      meta(name: "viewport", content: "width=device-width,initial-scale=1")
      # Turbo page-refresh = morph, а не reload. Це умова, за якої
      # `broadcast_refresh_to` придатний як транспорт живих оновлень:
      # інакше сторінка кластера перезавантажувалась би цілком і скидала
      # скрол на кожну тривогу (тротл — 5 с). ⚠️ `data-turbo-permanent` для
      # клієнтського стану тут НЕ вживається: на Leaflet-полотні його пробували
      # й зняли (`dashboard/map.rb` — атрибут спрацьовує на БУДЬ-якому Turbo-
      # рендері, не лише morph, і зносить серверний контент, вкладений усередину
      # позначеного вузла). Периметр наслідків morph — `00_07` UI.4.
      meta(name: "turbo-refresh-method", content: "morph")
      meta(name: "turbo-refresh-scroll", content: "preserve")
      link(rel: "icon", href: "/icon.png", type: "image/png")
      link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
      link(rel: "apple-touch-icon", href: "/icon.png")
      csp_meta_tag
      csrf_meta_tags
      stylesheet_link_tag "application", "tailwind", "data-turbo-track": "reload"
      javascript_importmap_tags
    end
  end

  def render_top_bar
    header(class: top_bar_classes, role: "banner") do
      div(class: "flex items-center gap-3 min-w-0") do
        # Mobile-only burger toggle (drawer trigger).
        render Views::Shared::UI::MobileNavToggle.new
        div(class: "flex flex-col min-w-0") do
          render_breadcrumbs
          h1(class: "text-base md:text-display-sm font-light tracking-[0.2em] uppercase text-gaia-text-strong mt-1 truncate leading-tight") { @title }
        end
      end

      div(class: "flex items-center gap-3 md:gap-6") do
        render_acting_context
        render Views::Shared::UI::LocaleSwitcher.new
        render_system_telemetry
        render_user_avatar
      end
    end
  end

  def top_bar_classes
    "h-14 md:h-20 border-b border-gaia-border flex items-center justify-between " \
      "px-4 md:px-8 bg-gaia-surface/80 backdrop-blur-md z-20 transition-colors duration-300"
  end

  def render_breadcrumbs
    nav(aria_label: t("navigation.breadcrumb.root"), class: "flex text-mini uppercase tracking-widest text-gaia-text-subtle font-bold") do
      ol(class: "flex items-center gap-2") do
        li do
          a(
            href: dashboard_index_path,
            class: "hover:text-gaia-primary-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-colors duration-200"
          ) { t("navigation.breadcrumb.root") }
        end

        # Парсинг шляху для крихт — використовуємо @current_path замість request.path.
        # ⚠️ Жодного зрізання [ARCH.77]: браузерний контур живе на кореневих шляхах,
        # тож КОЖЕН сегмент змістовний. Історія тут несуча — доти стояв `drop(2)`
        # («виключаємо api/v1»), який на шляху без того префікса мовчки зʼїдав би
        # голову крихт: без помилки й без червоного тесту, бо спека передає
        # `current_path` літералом. Якщо префікс колись повернеться — зрізати його
        # треба ІМЕНЕМ, а не позицією.
        path_segments = @current_path.split("/").reject(&:empty?)

        path_segments.each_with_index do |segment, index|
          li(class: "flex items-center gap-2") do
            span(aria_hidden: "true") { "//" }
            span(class: index == path_segments.size - 1 ? "text-gaia-text-muted" : "") do
              self.class.breadcrumb_segment_label(segment)
            end
          end
        end
      end
    end
  end

  # [UI.6] Індикатор рендериться ЛИШЕ super_admin'у, і це не роле-гейт заради
  # приховування: для решти ролей контекст неможливо відрізнити від членства —
  # `resolve_acting_organization` ігнорує сесію для всіх, крім super_admin, тож
  # індикатор говорив би їм те, що вони й так знають.
  #
  # ⚠️ Станів свідомо ДВА («обрано X» / «не обрано»), а не три — і підстава тут
  # НЕ «формула розходження вже має дім»: виклик наявного дому не є другим домом,
  # тож той аргумент доводив би протилежне. Чинних дві. (1) Дім цієї формули —
  # `Current#switched_context?` — амбієнтний, а шапка `current.rb` прямо забороняє
  # читати `Current` як джерело даних у в'ю. (2) Третій стан («своя проти чужої»)
  # має сенс лише для super_admin, що МАЄ домашню організацію; коли такий
  # зʼявиться, порівняння додається одним рядком із двох уже переданих величин.
  # Тобто це відкладене YAGNI, а не архітектурна відмова.
  def render_acting_context
    # `super_admin?`, а не `role_super_admin?`: [UI.5] канонізував саме делегат як
    # «вказівник на предикат `User`, той самий, що читають гарди», і сайдбар за
    # сорок рядків нижче вживає його. Дві форми одного питання в одному layout —
    # рівно те розходження, яке UI.5 робив неможливим.
    return unless @current_user&.super_admin?

    current = @acting_organization&.name || t("navigation.top_bar.context_none")

    a(
      href: organizations_path,
      # 🔴 Назва ВСЕРЕДИНІ мітки, бо `aria-label` на `<a>` замінює доступне імʼя
      # цілком і глушить дітей — рівно дефект, який [UI.3] полагодив у сайдбарі
      # (там aria_label з'їдав EWS-badge). Без інтерполяції незрячий чув би
      # «змінити організацію» й НІКОЛИ — яку саме.
      aria_label: t("navigation.top_bar.context_aria", name: current),
      class: "flex flex-col px-2 md:px-4 py-1.5 border border-gaia-border bg-gaia-surface-sunken " \
             "hover:border-gaia-primary transition-colors duration-300 " \
             "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
    ) do
      # Ховається лише ПІДПИС: сам контекст мусить лишатись видимим і на телефоні,
      # інакше «єдиний канал підтвердження» зникає рівно там, де кнопка
      # перемикання доступна (таблиця реєстру скролиться горизонтально).
      span(class: "hidden md:block text-micro text-gaia-text-subtle uppercase tracking-widest") do
        t("navigation.top_bar.context_label")
      end
      span(class: "text-tiny text-gaia-text-strong truncate max-w-[8rem] md:max-w-[12rem]") { current }
    end
  end

  def render_system_telemetry
    div(class: "hidden md:flex items-center gap-4 px-4 py-1.5 border border-gaia-border bg-gaia-surface-sunken transition-colors duration-300") do
      div(class: "flex flex-col text-right") do
        span(class: "text-micro text-gaia-text-subtle uppercase tracking-widest") { t("navigation.top_bar.core_sync_label") }
        span(class: "text-tiny text-gaia-text-strong") { t("navigation.top_bar.core_sync_value") }
      end
      div(class: "h-1 w-1 rounded-full bg-gaia-primary animate-pulse", aria_hidden: "true")
    end
  end

  # [UI.8] Аватар — ЄДИНИЙ вхід у власний профіль: `Users::Profile` (168 рядків,
  # 17 i18n-ключів, лічильник обслуговувань і активні ідентичності) був повністю
  # побудований і недосяжний — `users_me_path` не згадувався в `app/` жодного разу.
  # Класика «право без переходу»: робота зроблена, дверей немає.
  def render_user_avatar
    a(href: users_me_path,
      aria_label: t("navigation.top_bar.profile_aria", name: @current_user&.full_name),
      class: "flex items-center gap-3 focus-visible:outline-none focus-visible:ring-2 " \
             "focus-visible:ring-gaia-primary-strong focus-visible:ring-offset-2 focus-visible:ring-offset-gaia-surface") do
      div(class: "text-right hidden lg:block") do
        p(class: "text-tiny text-gaia-text-strong leading-none") { @current_user&.full_name }
        p(class: "text-micro text-gaia-text-subtle uppercase tracking-widest mt-1") { @current_user&.role_label }
      end
      div(class: "h-10 w-10 border border-gaia-primary flex items-center justify-center text-gaia-primary bg-gaia-surface-sunken transition-colors duration-300") do
        @current_user&.first_name&.first || "A"
      end
    end
  end

  # ── Sidebar slots ──────────────────────────────────────────────────────────

  # Static sidebar for `md+` viewports.
  #
  # 🔴 [UI.11] `data-turbo-permanent` ЗНЯТО 2026-08-01 — він був не оптимізацією, а
  # тим самим дефектом, що вже вбив Leaflet: permanent на вузлі, у який СЕРВЕР
  # рендерить дані. Turbo пересаджує старий вузол (Bardo) і викидає свіжу розмітку,
  # morph такі вузли пропускає взагалі — тож бейдж `ews_alert_count` і `aria-current`
  # замерзали на першому завантаженні, і на десктопі лічильник ТРИВОГ показував
  # застаріле число до повного перезавантаження. Мобільний drawer рендерить той
  # самий компонент без атрибута й лишався свіжим — саме ця розбіжність між
  # viewport'ами й довела, що атрибут тут успадкований, а не обраний (єдиний
  # коментар був «so it survives navigations»).
  #
  # ⚠️ Що це НЕ лікує: бейдж кешується на 1 хвилину (`ews_alert_count_cached`) при
  # тротлі броадкасту 5 с, тож «живим» він від цього не став — звʼязуюче обмеження
  # тепер TTL кешу, і це окремий пункт `00_07` UI.11.
  def render_desktop_sidebar
    div(class: "hidden md:block", id: "sidebar-navigation") do
      render Navigation::Sidebar.new(
        current_path: @current_path,
        ews_alert_count: @ews_alert_count,
        current_user: @current_user
      )
    end
  end

  # Off-canvas mobile drawer built on the native `<dialog>` element.
  # Browser handles focus-trap, Escape-to-close, top-layer stacking and the
  # `::backdrop` pseudo-element. The Stimulus `mobile-nav` controller is a
  # thin shim that calls `.showModal()` and bridges backdrop-click + Turbo
  # navigation cleanup. See app/javascript/controllers/mobile_nav_controller.js.
  def render_mobile_drawer
    dialog(
      id: "mobile-nav-drawer",
      data: {
        mobile_nav_target: "dialog",
        action: "click->mobile-nav#backdropClick close->mobile-nav#onClose"
      },
      aria_label: t("accessibility.open_navigation"),
      # Reset UA dialog defaults (centered + max-content) and slide it in
      # from the left. `open:` variants animate the slide once the browser
      # promotes the dialog to the top layer; `@starting-style` (in
      # application.css) handles the off-screen → on-screen entrance frame
      # without a JS-flushed forced reflow.
      class: "md:hidden p-0 m-0 h-full max-h-none w-72 max-w-[85vw] " \
             "fixed inset-y-0 left-0 right-auto bg-transparent " \
             "open:translate-x-0 -translate-x-full " \
             "transition-transform duration-[var(--motion-base)] " \
             "ease-[var(--ease-out-soft)] backdrop:bg-black/60 " \
             "backdrop:backdrop-blur-sm"
    ) do
      render Navigation::Sidebar.new(
        current_path: @current_path,
        ews_alert_count: @ews_alert_count,
        current_user: @current_user
      )
    end
  end
end
