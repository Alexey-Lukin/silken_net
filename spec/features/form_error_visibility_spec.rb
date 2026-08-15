# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [SEC.25] Приклади, які НЕ доказовні нижче — і критерій шару тут той самий,
# що в браузерному прикладі PRG-класу (`04_06 §B.1.4`), лише вісь інша.
# ⚠️ Живого другого зразка в дереві зараз немає — це оголошено в `04_06`.
#
# Дефект цієї осі — «людина не бачить причини», а не «сервер не віддав тіла».
# Request-спека міряє ВІДПОВІДЬ, тоді як викидає її КЛІЄНТ: Turbo рендерить
# сабміт-відповідь лише поза 2xx, і саме тому вся ця вісь відкрилась 200-ками,
# які він ковтав мовчки. Тобто пін на тіло відповіді лишається зеленим і тоді,
# коли на екрані не змінюється НІЧОГО.
#
# ⚠️ Тому тут рівно два приклади — по одному на МЕХАНІЗМ сабміту, а не по одному
# на форму. Їх у дереві два, і вони ламаються незалежно:
#   * `form_with` — Rails будує форму й CSRF сам (`TreeFamilies::Form`);
#   * рукописна `form(...)` з hidden `_method` + рукописним токеном
#     (`Settings::Show`) — форма, чий клас уже стріляв в UI.7, коли токена
#     забули зовсім.
# Решта чотири поверхні доказовні на дешевшому шарі й сюди не дублюються.
RSpec.describe "Причина відмови видима у справжньому браузері", :js do
  let(:organization) { create(:organization, name: "Boreal Trust") }
  let(:password)     { "form-error-visible-1" }
  let!(:admin)       { create(:user, :admin, organization: organization, password: password) }

  # ⚠️ Ролі різні НЕ для повноти покриття, а тому що гарди різні: створення родини
  # сидить під `authorize_super_admin!, only: [:new, :create, …]`, тоді як
  # налаштування організації відкриті адмінові. Взяти одного актора на обидва
  # приклади означало б або 403 у першому, або нереалістичного актора в другому.
  let!(:super_admin) { create(:user, :super_admin, organization: organization, password: password) }

  # `form_with`-механізм. До фіксу форма перемальовувалась із порожнім `name`,
  # і єдиним сигналом відмови був заголовок сторінки.
  it "показує причину після сабміту form_with-форми" do
    sign_in_as(super_admin, password: password)
    visit_ok "/tree_families/new"

    fill_in "tree_family[name]", with: ""
    click_button(type: "submit")

    # ⚠️ Роль і текст — ОДНЕ твердження, не два. `FlashMessages` тримає порожній
    # `role="alert"` у кожному дашборді за a11y-контрактом, тож окремий
    # `have_css('[role="alert"]')` був би істинний на будь-якій сторінці й не
    # падав би ніколи.
    expect(page).to have_css('[role="alert"]', text: "Name can't be blank")
  end

  # Рукописна `form(...)` + hidden `_method=patch`. Той самий доказ, інший тракт:
  # тут Rails форму не будує, тож і сабміт, і CSRF, і рендер 422 їдуть шляхом,
  # який попередній приклад не проходить.
  it "показує причину після сабміту рукописної форми з hidden _method" do
    sign_in_as(admin, password: password)
    visit_ok "/settings"

    fill_in "organization[billing_email]", with: "not-an-email"
    click_button(type: "submit")

    expect(page).to have_css('[role="alert"]', text: "Billing email is invalid")
  end
end
