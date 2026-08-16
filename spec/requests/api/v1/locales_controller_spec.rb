# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::LocalesController, type: :request do
  describe "POST /locale" do
    it "persists a valid locale into a permanent cookie" do
      post "/locale", params: { locale: "en" }
      expect(response).to have_http_status(:see_other)
      expect(cookies[:locale]).to eq("en")
    end

    it "accepts the secondary locale (uk → en switch)" do
      post "/locale", params: { locale: "uk" }
      expect(cookies[:locale]).to eq("uk")
    end

    # 🔴 Строк життя cookie тут — ЗАЯВА, яку ми вже дали публічно: обидва носії
    # наміру (`protocols/legal/b2c_tos_privacy.md` §Cookies + його таблиця Cookie
    # Policy, тобто майбутній клієнтський документ) кажуть «1 рік». Доти код
    # кликав `cookies.permanent`, а це **20 років** — тобто retention обирав
    # дефолт фреймворку, і документ розходився з реальністю у 20 разів.
    # Без цього піна повернення до `permanent` знову зробило б публічну обіцянку
    # хибною, і жоден гейт не почервонів би — правило без носія.
    it "expires the locale cookie in about a year, per the published retention claim" do
      post "/locale", params: { locale: "uk" }

      expires_at = Time.zone.parse(response.headers["Set-Cookie"].to_s[/expires=([^;]+)/i, 1])
      expect(expires_at).to be_between(11.months.from_now, 13.months.from_now)
    end

    it "rejects an unknown locale and does not write a cookie" do
      post "/locale", params: { locale: "ru" }
      expect(cookies[:locale]).to be_blank
      expect(flash[:error]).to be_present
    end

    # [I18N.1] Cookie тримає вибір для БРАУЗЕРА; колонка — для того, що з браузера
    # не видно. Пошта йде з Sidekiq, де ані cookie, ані сесії немає, тож без цього
    # запису `users.locale` лишався б NULL назавжди, а `in_locale_of` у мейлері —
    # декоративним. Саме цей клас («колонка є, заповнювати нікому») тут і пінимо.
    describe "persisting the choice for a signed-in user" do
      let(:user) { create(:user, locale: nil) }

      def sign_in!
        post "/login", params: { email: user.email_address, password: "password12345" }
      end

      it "stores the chosen locale on the user record" do
        sign_in!

        expect { post "/locale", params: { locale: "uk" } }
          .to change { user.reload.locale }.from(nil).to("uk")
      end

      it "leaves an anonymous visitor's switch working without persisting anything" do
        expect { post "/locale", params: { locale: "uk" } }
          .not_to change(User, :count)

        expect(cookies[:locale]).to eq("uk")
        expect(user.reload.locale).to be_nil
      end

      # Guard дзеркалить [SEC.16]: сам по собі `session[:user_id]` не є доказом —
      # salt-stamp гасне при зміні пароля. Без цієї перевірки запис у БД став би
      # тихим обходом salt-прив'язки.
      it "does not persist when the session salt-stamp no longer matches" do
        sign_in!
        user.update!(password: "brand-new-password-123", password_confirmation: "brand-new-password-123")

        expect { post "/locale", params: { locale: "lv" } }
          .not_to change { user.reload.locale }
      end

      it "does not write when the choice already matches the stored one" do
        user.update!(locale: "uk")
        sign_in!

        expect { post "/locale", params: { locale: "uk" } }
          .not_to change { user.reload.updated_at }
      end
    end

    it "redirects back to the referer when same-host" do
      post "/locale",
           params: { locale: "en" },
           headers: { "HTTP_REFERER" => "http://www.example.com/dashboard" }
      expect(response).to redirect_to("http://www.example.com/dashboard")
    end

    it "falls back to root_path for missing referer" do
      post "/locale", params: { locale: "en" }
      expect(response).to redirect_to(root_path)
    end

    it "ignores cross-host referers (open-redirect guard)" do
      post "/locale",
           params: { locale: "en" },
           headers: { "HTTP_REFERER" => "http://attacker.example.com/phish" }
      expect(response).to redirect_to(root_path)
    end

    it "handles array locale param without crashing" do
      post "/locale", params: { locale: %w[en uk] }
      expect(response).not_to have_http_status(:internal_server_error)
      expect(cookies[:locale]).to be_blank
    end

    it "handles hash locale param without crashing" do
      post "/locale", params: { locale: { foo: "bar" } }
      expect(response).not_to have_http_status(:internal_server_error)
      expect(cookies[:locale]).to be_blank
    end

    it "rejects javascript: scheme referer (open-redirect guard)" do
      post "/locale",
           params: { locale: "en" },
           headers: { "HTTP_REFERER" => "javascript:alert(1)" }
      expect(response).to redirect_to(root_path)
    end
  end

  # [I18N.3] 🔴 Ці приклади свідомо ходять ЗАПИТАМИ, а не через стаб концерну — і
  # це не стильова примха, а прямий висновок з того, як цей дефект вижив.
  #
  # Доти тут стояли два юніт-приклади, які будували голий клас, підмішували в нього
  # `LocaleSettable` і `define_singleton_method(:preferred_language)` на фейковому
  # `request`. Обидва були ЗЕЛЕНІ сім місяців — і саме тому щабель `Accept-Language`
  # ніхто не переміряв: мок ВИГОТОВЛЯВ метод, якого не існує ні в `actionpack`, ні в
  # `rack`, тобто спека доводила поведінку API, що в проді не викликається ніколи.
  # Сусідній приклад («swallows StandardError») цементував мовчазний `rescue`, тобто
  # другу половину тієї ж невидимості. Клас — [`TEST.12`], лише тут фікстура вигадала
  # не ТИП, а МЕТОД; назва першої з них («when available») тихо визнавала умовність,
  # яку ніхто не пішов перевіряти.
  #
  # Тому носієм тепер є справжній стек: заголовок → Rack → концерн → рендер.
  describe "LocaleSettable concern (resolution priority)" do
    def unauthorized_text(locale) = I18n.t("errors.api.unauthorized", locale: locale)
    def vitality_text(locale) = I18n.t("dashboard.home.stats.forest_vitality", locale: locale)

    it "ships with :en as the application default locale" do
      expect(I18n.default_locale).to eq(:en)
    end

    it "ships with :uk, :en, :lv and :lt in available_locales" do
      expect(I18n.available_locales).to include(:uk, :en, :lv, :lt)
    end

    it "honours an explicit ?locale= param over the cookie" do
      cookies[:locale] = "uk"
      post "/locale", params: { locale: "en" }
      expect(cookies[:locale]).to eq("en")
    end

    describe "tier 4 — Accept-Language" do
      it "resolves an anonymous visitor's language from the header" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "uk-UA,uk;q=0.9,en;q=0.8" }

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include(unauthorized_text(:uk))
        # Негативна половина: без неї приклад лишався б зеленим і тоді, коли
        # сторінка несе ОБИДВІ мови (шапка англійська, тіло українське).
        expect(response.body).not_to include(unauthorized_text(:en))
      end

      it "honours q-values rather than the order the header lists" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "en;q=0.1,lv;q=0.9" }

        expect(response.body).to include(unauthorized_text(:lv))
      end

      # 🔴 Дискримінатор тут НЕ довільний, і перша редакція цього прикладу була
      # брехлива: вона слала `en;q=0,lt;q=0.5` і зеленіла тому, що `0.5 > 0.0`,
      # а не тому, що `q=0` поважається — тобто пінила спроможність, якої в коді
      # тоді не було (рівно клас, проти якого стоїть увесь цей блок).
      # Єдина форма, що РОЗРІЗНЯЄ: відхилити мову, яка інакше виграла б сама.
      it "treats q=0 as «not acceptable», not as a candidate" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "uk;q=0" }

        expect(response.body).to include(unauthorized_text(I18n.default_locale))
        expect(response.body).not_to include(unauthorized_text(:uk))
      end

      it "keeps a lower-q language once the higher one is rejected" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "en;q=0,lt;q=0.5" }

        expect(response.body).to include(unauthorized_text(:lt))
      end

      # 🔴 Найдорожча вісь із усіх: `Accept-Language: uk,en` не має ЖОДНОЇ ваги,
      # і RFC 9110 §12.5.4 каже, що тоді перевагу задає ПОРЯДОК. Готовий
      # `Rack::Utils.best_q_match` віддавав тут «en» (він розвʼязує рівність
      # останнім елементом) — тобто українець із типовим заголовком діставав
      # англійську, і фікс щабля виглядав би зробленим.
      it "prefers the FIRST tag when no weights are given" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "uk,en" }

        expect(response.body).to include(unauthorized_text(:uk))
        expect(response.body).not_to include(unauthorized_text(:en))
      end

      # Форма, яку реально шле Chrome: регіональний тег ПЕРШИМ.
      it "falls back from a regional tag to its base language" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "lv-LV" }

        expect(response.body).to include(unauthorized_text(:lv))
      end

      it "survives empty segments without losing the valid tag beside them" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "uk,,en" }

        expect(response.body).to include(unauthorized_text(:uk))
      end

      it "reads a bare wildcard as «any», i.e. the application default" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "*" }

        expect(response.body).to include(unauthorized_text(I18n.default_locale))
      end

      # BCP-47 оголошує мовні теги регістро-НЕЧУТЛИВИМИ, а `Rack::Utils.best_q_match`
      # порівнює рядки буквально — виміряно, `UK-ua` проти `uk` дає `nil`. Нормалізація
      # живе в концерні; цей приклад стереже саме її.
      it "matches a language tag regardless of case" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "UK-UA,UK;q=0.9" }

        expect(response.body).to include(unauthorized_text(:uk))
      end

      it "falls through to the default for a language we do not ship" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "de-DE,de;q=0.9,fr;q=0.8" }

        expect(response.body).to include(unauthorized_text(I18n.default_locale))
      end

      # ⚠️ Пін на СТАТУС тут був би слабший, ніж здається: він зеленів би й тоді,
      # коли валідний `uk` тихо гине разом із битим сусідом (саме так поводився
      # `best_q_match` — кидав, і `rescue` ховав втрату). Тому пінимо РЕЗУЛЬТАТ.
      it "survives a malformed header AND still honours the valid tag inside it" do
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => ";;;q=,,uk;q=абв" }

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include(unauthorized_text(:uk))
      end

      # 🔴 Ця гілка НЕ досяжна жодним заголовком — і саме тому потребує піна, а не
      # видалення: після переходу з `best_q_match` на власний вибір парсер більше
      # не кидає на битому вході (порожні сегменти обробляються явно), тож
      # `rescue` лишається межею довіри до ЧУЖОГО гема, а не мертвим кодом.
      # Пін тримає обидві половини властивості: запит виживає І відмова ГУЧНА —
      # саме мовчазний `rescue` поверх мовчазного `respond_to?` робив попередній
      # дефект невидимим на двох рівнях одразу.
      it "degrades softly AND loudly if the parser itself ever raises" do
        allow(Rack::Utils).to receive(:q_values).and_raise(ArgumentError, "boom")
        allow(Rails.logger).to receive(:warn)

        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "uk" }

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include(unauthorized_text(I18n.default_locale))
        expect(Rails.logger).to have_received(:warn).with(/\[I18N\] Accept-Language parse failed: ArgumentError/)
      end

      it "loses to an explicit cookie choice" do
        cookies[:locale] = "lv"
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "uk,en;q=0.8" }

        expect(response.body).to include(unauthorized_text(:lv))
      end
    end

    describe "tier 3 — persisted users.locale" do
      let(:user) { create(:user, locale: "lv") }

      def sign_in!
        post "/login", params: { email: user.email_address, password: "password12345" }
      end

      it "renders the dashboard in the account language when no cookie is present" do
        sign_in!
        get "/dashboard"

        expect(response.body).to include(vitality_text(:lv))
        expect(response.body).not_to include(vitality_text(:en))
      end

      it "wins over Accept-Language" do
        sign_in!
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "uk,en;q=0.8" }

        expect(response.body).to include(vitality_text(:lv))
      end

      it "loses to the cookie — «обрав У ЦЬОМУ браузері» лишається сильнішим" do
        sign_in!
        cookies[:locale] = "uk"
        get "/dashboard"

        expect(response.body).to include(vitality_text(:uk))
      end

      # 🔴 Другий корінь дерева контролерів, і без власного hook'а щабель 3 був би
      # мертвий саме тут — у контролері, який ВОЛОДІЄ перемиканням мови.
      # `Api::V1::LocalesController` успадковує `ApplicationController`, у якої
      # `current_user` немає за побудовою, тож дефолтний `nil` з'їдав би
      # акаунт-вподобу мовчки. Дискримінатор: людина з `users.locale` і БЕЗ cookie
      # шле невалідну локаль — повідомлення про відмову мусить прийти її мовою.
      it "resolves the account locale on the switcher's own root (ApplicationController)" do
        user.update_column(:locale, "uk")
        sign_in!

        post "/locale", params: { locale: "ru" }

        expect(flash[:error]).to eq(I18n.t("flash.unsupported_locale", locale: :uk))
        expect(flash[:error]).not_to eq(I18n.t("flash.unsupported_locale", locale: :en))
      end

      it "falls through when the column is empty" do
        user.update_column(:locale, nil)
        sign_in!
        get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "lt" }

        expect(response.body).to include(vitality_text(:lt))
      end
    end

    # ⛔ [I18N.3] `organizations.locale` щаблем НЕ Є — і це присуд, а не пропуск.
    # Симетрія напрошується (колонка є, валідується проти того самого дому,
    # читається `AlertMailer`'ом), тож без носія наступний прохід допише щабель
    # «за симетрією». Підстава — на моделі: та колонка каже, якою мовою
    # організація отримує ПОШТУ на `billing_email`, тобто адресу, за якою може не
    # стояти жоден User; мовою ЕКРАНА вона робила б так, що латвійська філія
    # нав'язує інтерфейс українцеві, приписаному до неї, — і саме на першому
    # візиті, доки людина перемикача ще не торкалась.
    describe "⊥ organizations.locale is deliberately NOT a tier" do
      it "keeps the screen on the default when only the ORGANIZATION has a language" do
        organization = create(:organization, locale: "lv")
        user = create(:user, locale: nil, organization: organization)

        # Ліхтар: без нього приклад зелений і на порожній колонці, тобто доводив
        # би відсутність щабля так само, як його наявність (`04_06 §B.2` BP 21).
        expect(organization.reload.locale).to eq("lv")

        post "/login", params: { email: user.email_address, password: "password12345" }
        get "/dashboard"

        expect(response.body).to include(vitality_text(:en))
        expect(response.body).not_to include(vitality_text(:lv))
      end
    end

    # 🔴 Ліхтар на ПЕРШИЙ прохід, і він стереже не поведінку, а ПОРЯДОК колбеків.
    #
    # `set_locale` реєструється разом із концерном, тобто ДО `authenticate_user!`;
    # акаунт-щабель доганяє окремим `set_locale_from_account` уже після. Природна
    # «оптимізація» — злити їх в один `before_action :set_locale`, зареєстрований
    # після автентифікації, — тиха: Rails дедуплікує колбеки за іменем фільтра, тож
    # рання фаза не подвоїлась би, а ЗНИКЛА, і 401 віддавалась би базовою мовою
    # незалежно від того, що просив браузер. Приклад нижче червоніє рівно на цьому.
    it "resolves the locale BEFORE authentication, so the login page keeps its language" do
      get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "lt,en;q=0.5" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include(unauthorized_text(:lt))
    end
  end
end
