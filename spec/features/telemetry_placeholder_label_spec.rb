# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 Носій регресу, знайденого adversarial-проходом 2026-08-14 і НЕ спійманого
# жодним наявним прикладом.
#
# `gaia-labels-published` (I18N.2) дав правило `td:nth-child(N)::before` з
# підстановкою `--gaia-col-N`. Рядок-плейсхолдер телеметрії — це один
# `<td colspan="4">` зі спінером і БЕЗ `data-label`, тобто формально
# `nth-child(1)`: він успадковував мітку першої колонки й на кожному мобільному
# завантаженні друкував «Timestamp» над написом «очікуємо аплінк», ще й фліпав
# розкладку з центрованого блоку на label/value-рядок.
#
# ⚠️ Чому синтетичного прикладу (`responsive_table_broadcast_label_spec`) не
# вистачило: його рядок МАЄ `data-label`, тобто комірка-без-мітки лежала поза
# його світом за побудовою. Цей приклад міряє РЕАЛЬНУ сторінку в реальному
# Chrome і на мобільній ширині — там, де card-flip узагалі вмикається.
RSpec.describe "Телеметрія: плейсхолдер на мобільному", :js do
  let(:organization) { create(:organization, name: "Placeholder Probe Org") }
  let(:password)     { "placeholder-probe-1" }
  let!(:admin)       { create(:user, :admin, organization: organization, password: password) }

  # Нижче 768px — саме там живе `@media (max-width: 767px)` з card-flip.
  def mobile_width = 390

  it "не малює мітки колонки над спінером, і лишає його центрованим блоком" do
    page.driver.resize(mobile_width, 800)
    sign_in_as(admin, password: password)
    visit_ok "/telemetry/live"

    expect(page).to have_css("#feed_placeholder", wait: 5)

    measured = page.driver.browser.evaluate(<<~JS)
      (() => {
        const td = document.querySelector('#feed_placeholder td');
        const before = getComputedStyle(td, '::before');
        return JSON.stringify({
          content: before.content,
          justify: getComputedStyle(td).justifyContent,
          colspan: td.getAttribute('colspan'),
          width: window.innerWidth
        });
      })()
    JS

    parsed = JSON.parse(measured)

    # Ліхтарі: без них приклад був би зелений і на десктопній ширині, де
    # card-flip не вмикається взагалі, і на розмітці без colspan.
    expect(parsed["width"]).to be < 768
    expect(parsed["colspan"]).to eq("4")

    expect(parsed["content"]).not_to include("Timestamp")
    expect(parsed["justify"]).to eq("center")
  end
end
