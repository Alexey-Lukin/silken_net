# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [UI.3] Носій класу, у якого доти НЕ БУЛО жодного прикладу: розмітка, видима
# рівно ОДНІЙ ролі.
#
# Перемикач контексту (`render_acting_context`) рендериться лише платформеному
# акторові — і саме тому його верстка не мала шансу бути поміченою: кожен
# наявний браузерний приклад ходить org-адміном, тобто сторінка, яку вони
# міряють, ФІЗИЧНО не містить цього вузла. Дефект тут не «рідкісний», він
# недосяжний за побудовою для всієї наявної браузерної смуги.
#
# 🔬 Чому вимір, а не пін на класи. «Чи вміщається смуга» не є властивістю
# розмітки: те саме дерево класів вміщається або ні залежно від ШИРИНИ тексту
# (назва організації, локаль, роль у підписі аватара). Тож єдине чесне
# твердження — геометричне: жоден нащадок шапки не сміє виходити за її межі.
#
# 🧭 Пара акторів несуча в обидва боки. Сам по собі «нуль порушень у
# super_admin» не відрізнити від «прилад нічого не міряє»; org-адмін є
# контролем, що доводить протилежне — на ньому шапка вміщається, тож нуль
# означає саме вміщення. Плюс ліхтар на РОЗМІР множини: порожній набір вузлів
# дав би нуль порушень безкоштовно.
#
# 🔒 Стелі, названі поіменно:
#   · ОДНЕ вікно (1440×900) — мобільна смуга має власну розкладку (card-flip);
#   · судиться лише `header[role="banner"]`, не вся сторінка;
#   · вимір геометричний, тож він мовчить про читабельність і про порядок
#     фокусу — це сусідні осі з власними приладами.
RSpec.describe "Топбар: роле-залежна верстка", :js do
  let(:organization) { create(:organization, name: "Черкаський Лісогосподарський Консорціум") }
  let(:password)     { "top-bar-overflow-1" }

  let!(:org_admin)   { create(:user, :admin, organization: organization, password: password) }
  let!(:platform)    { create(:user, :super_admin, organization: organization, password: password) }

  # Та сама ширина, на якій дефект знайдено візуальною QA.
  def desktop = [ 1440, 900 ]

  # Повертає вузли, чий прямокутник виходить за межі шапки, — кожен із власними
  # координатами. Допуск 1px: subpixel-округлення браузера не є переповненням.
  def overflowing_nodes
    page.driver.browser.evaluate(<<~JS)
      (() => {
        const bar = document.querySelector('header[role="banner"]');
        if (!bar) return { error: 'no banner' };
        const box = bar.getBoundingClientRect();
        const nodes = Array.from(bar.querySelectorAll('*'));
        const escaped = nodes.filter((n) => {
          const r = n.getBoundingClientRect();
          if (r.width === 0 && r.height === 0) return false;
          return r.top < box.top - 1 || r.bottom > box.bottom + 1 ||
                 r.left < box.left - 1 || r.right > box.right + 1;
        });
        return {
          measured: nodes.length,
          bar: `h=${Math.round(box.height)}`,
          // Координати, а не самі класи: коли це червоніє, ім'я класу не каже
          // НІЧОГО про причину — чи вузол ширший, чи вищий, і на скільки. Перший
          // прогін цього приладу коштував саме тим, що я прочитав горизонтальне
          // переповнення там, де воно було вертикальне.
          escaped: escaped.map((n) => {
            const r = n.getBoundingClientRect();
            return `${n.className.toString().slice(0, 40)} | top=${Math.round(r.top)} bot=${Math.round(r.bottom)} h=${Math.round(r.height)}`;
          })
        };
      })()
    JS
  end

  it "вміщає шапку для org-адміна — контроль, що прилад узагалі щось міряє" do
    page.driver.resize(*desktop)
    sign_in_as(org_admin, password: password)

    result = overflowing_nodes

    # Ліхтар на популяцію: без нього «нуль порушень» читалось би як здоровʼя
    # навіть тоді, коли селектор не знайшов жодного вузла.
    expect(result["measured"]).to be > 10
    expect(result["escaped"]).to be_empty
  end

  it "вміщає шапку і для платформеного актора, якому додається перемикач контексту" do
    page.driver.resize(*desktop)
    sign_in_as(platform, password: password)

    result = overflowing_nodes

    expect(result["measured"]).to be > 10
    expect(result["escaped"]).to be_empty
  end
end
