# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 Носій виміряного механізму: НЕ-GET сабміт Turbo-форми виходить на дріт як
# **POST**, а справжнє дієслово їде в тілі як `_method`.
#
# Чому це має власний приклад, а не рядок у каноні. Твердження про дротове
# дієслово вже двічі записували з ЧИТАННЯ джерела, і обидва рази хибно:
# `04_03 §2.2а` і скіл `backend` #22 посилались на `determineFetchMethod` як на
# доказ, що Turbo шле справжній PATCH/DELETE — тоді як ця функція викликається
# ВСЕРЕДИНІ `encodeMethodIntoRequestBody` (`turbo-rails` 2.0.23,
# підписаний глобально на `turbo:before-fetch-request`) рівно щоб
# покласти метод у `_method` і виставити `fetchOptions.method = "post"`.
#
# На цій хибній підставі стояло правило «редирект із не-POST мутації мусить
# бути 303, інакше браузер перевидасть PATCH на GET-only маршрут». Симптом,
# який те правило описує, у цьому застосунку НЕДОСЯЖНИЙ: для POST специфікація
# Fetch зобовʼязує конвертувати 3xx у GET.
#
# ⚠️ Приклад міряє ПОВЕДІНКУ, а не код, — саме тому, що читання коду вже двічі
# дало протилежну відповідь. Дієслова він не розрізняє свідомо: гілка
# `!/get/i.test(method)` накриває PATCH і DELETE однаково, тож доведення її
# виконання на PATCH доводить механізм, а не окремий випадок.
RSpec.describe "Дротове дієслово не-GET сабміту", :js do
  let(:organization) { create(:organization, name: "Wire Method Org") }
  let(:password)     { "wire-method-probe-1" }
  let!(:admin)       { create(:user, :admin, organization: organization, password: password) }

  it "виходить на дріт як POST, а не як PATCH" do
    sign_in_as(admin, password: password)
    visit_ok "/settings"

    browser = page.driver.browser
    browser.network.clear(:traffic)

    fill_in "organization[billing_email]", with: "ops@example.com"
    click_button(type: "submit")

    # Спершу дочекатись DOM-зміни, інакше трафік читається ДО відповіді
    # (стеля #2 у `feature_helper`).
    expect(page).to have_css('[role="status"]', wait: 5)

    settings_mutations = browser.network.traffic.filter_map do |exchange|
      req = exchange.request
      next if req.nil? || req.method == "GET"
      next unless req.url.end_with?("/settings")

      req.method
    end

    # Позитивний бік: множина НЕ порожня — інакше приклад був би зелений на
    # нулі запитів і не доводив би нічого.
    expect(settings_mutations).not_to be_empty,
      "жодного не-GET запиту на /settings — сабміт не відбувся, приклад безпредметний"

    # Несучий бік: жодного справжнього PATCH на дроті.
    expect(settings_mutations).to all(eq("POST"))
  end
end
