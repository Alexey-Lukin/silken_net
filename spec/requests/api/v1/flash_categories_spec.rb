# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.25 Ф3] Наскрізний доказ, що КОЖНА з чотирьох flash-категорій доїжджає від
# контролера до сторінки — і саме в свій live-region.
#
# 🔴 Чому цей файл існує замість статичного сторожа, і це вимір, а не смак.
# Приписана форма («AST-спека, що проходить усі `flash:`-сайти й червоніє на
# невідомій категорії») діагностує НЕ ТОЙ ШАР. Категорія гине на два шари вище за
# компонент: `ActionController::Flash#redirect_to` перебирає лише `_flash_types` і
# мовчки лишає незареєстрований kwarg їхати туди, де читають самий `:status`. У
# такому сценарії статичний сторож ЗЕЛЕНИЙ (усі імена «відомі»), гучний `raise` у
# компоненті теж ЗЕЛЕНИЙ (хеш приїжджає порожнім — дропати нема чого), а спеки на
# редирект зелені, бо 302 таки відбувається. Тобто обидві приписані мітигації
# сліпі рівно до тієї події, від якої мали захищати.
#
# ⚠️ Другий вимір, що вбив AST-форму остаточно: греп за іменем категорії дає хибні
# позитиви на JSON-ключах — `alert: @alert`, `security: {` у dashboard, `pending:`
# у reports. Сторож червонів би на рядках, яких чіпати не можна.
#
# ⚠️ Cookie-логін тут обов'язковий, не стильовий: `follow_redirect!` НЕ переносить
# заголовок `Authorization`, тож Bearer-приклад після редиректу віддав би сторінку
# логіну — і всі асерти лишились би чесно зеленими про іншу сторінку.
RSpec.describe "flash-категорії", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, :forester, organization: organization) }

  # [TEST.16] Ліхтар успіху — сам файл нижче й пояснює клас: «всі асерти
  # лишились би чесно зеленими про іншу сторінку».
  before { sign_in_via_form(user, password: "password12345") }

  # Обидва регіони рендеряться завжди, навіть порожні, тож сама лише наявність id
  # нічого не доводить — доводить ПОЗИЦІЯ тексту відносно межі між регіонами
  # (assertive іде в DOM першим).
  def boundary = response.body.index('id="flash_polite"')

  describe "polite-регіон" do
    let(:cluster) { create(:cluster, organization: organization) }
    let!(:alert) { create(:ews_alert, :drought, cluster: cluster) }

    before do
      allow(AlertNotificationWorker).to receive(:perform_async)
      silence_broadcasts!(:alert_notify)
      allow_any_instance_of(EwsAlert).to receive(:close_associated_maintenance!)
      silence_broadcasts!(:alert_update)
    end

    it "success доїжджає до сторінки й сідає в polite" do
      patch resolve_alert_path(alert), headers: { "Accept" => "text/html" }
      follow_redirect!

      text = I18n.t("flash.alerts.resolved")
      expect(response.body).to include(text)
      expect(response.body.index(text)).to be > boundary
    end

    it "pending доїжджає до сторінки й сідає в polite" do
      patch resolve_alert_path(alert), headers: { "Accept" => "text/html" }
      patch resolve_alert_path(alert), headers: { "Accept" => "text/html" }
      follow_redirect!

      text = I18n.t("flash.alerts.already_resolved", id: alert.id)
      expect(response.body).to include(text)
      expect(response.body.index(text)).to be > boundary
    end
  end

  describe "assertive-регіон" do
    # ⚠️ Носій категорії тут змінено 2026-08-03 разом із предметом: доти приклад
    # їздив через невдалу зміну пароля, але та відмова — ВАЛІДАЦІЯ поточного
    # сабміту, і вона більше не редиректить, а лишає людину у формі з 422
    # (inline-помилка, `account_security_controller_spec`). Категорію `error`
    # тепер демонструє відмова, яка редиректом і є за суттю: протермінований
    # токен скидання — виправити його вводом неможливо, тож людину відправляють
    # на іншу сторінку.
    it "error доїжджає до сторінки й сідає в assertive" do
      patch "/reset_password",
            headers: { "Accept" => "text/html" },
            params: { token: "expired-or-forged", password: "irrelevant-1", password_confirmation: "irrelevant-1" }
      follow_redirect!

      text = I18n.t("passwords.reset.invalid_token_flash")
      expect(response.body).to include(text)
      expect(response.body.index(text)).to be < boundary
    end

    it "security доїжджає до сторінки й сідає в assertive" do
      patch "/account_security/password",
            headers: { "Accept" => "text/html" },
            params: {
              current_password: "password12345",
              new_password: "new_secure_pass_1",
              new_password_confirmation: "new_secure_pass_1"
            }

      # 🔴 Цей асерт мусить стояти ДО `follow_redirect!`, і він не про стиль.
      # `follow_redirect!` на 302 **завжди** робить GET (`integration.rb`), тож усе
      # нижче лишалось би зеленим і при 302 — тобто наскрізний доказ був би сліпий
      # до єдиної реальної поломки цього шляху. А поломка є: Turbo читає `_method` і
      # шле СПРАВЖНІЙ PATCH, для якого fetch метод зберігає, — тож на 302 браузер
      # перевидав би `PATCH /account_security`, де оголошено лише `get` → 404 після
      # успішної зміни пароля. Rails 303 сам НЕ ставить (виміряно) [UI.7].
      expect(response).to have_http_status(:see_other)
      follow_redirect!

      text = I18n.t("account_security.password.updated_flash")
      expect(response.body).to include(text)
      expect(response.body.index(text)).to be < boundary
    end
  end
end
