# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 Носій ДВОХ передумов, на яких стоїть присуд I18N.2 — і обидві канон
# (`04_04 §8.1а`) чесно позначав як «сильна підстава, а НЕ власний вимір».
#
# Передумова 1 — «клас 2 непридатний для РЯДКА таблиці»: `<tbody>` за
# HTML-парсингом приймає лише `<tr>`, тож `<turbo-frame>` виноситься
# foster-parenting'ом. ⚠️ Твердження про ПАРСЕР, а Turbo-стріми вставляють
# уже розібраний фрагмент через DOM API — тобто воно може бути правдивим про
# `innerHTML` і хибним про реальний шлях доставки. Міряємо ОБИДВА.
#
# Передумова 2 — чи існує спосіб віддати мітку колонки СТОРІНЦІ, лишивши
# broadcast-рядок locale-інваріантним. Card-flip малює мітку через
# `content: attr(data-label)`, тобто літерал приїздить із процесу-продюсера, де
# локалі немає. Якщо CSS custom property, поставлена на таблицю ОДИН раз,
# успадковується пізніше вставленими рядками — блокер знімається без нової
# машинерії в payload'і.
#
# Чому браузером, а не читанням специфікації: цей самий канон-абзац уже двічі
# фіксував механізм із читання джерела й обидва рази хибно (див. шапку
# `turbo_wire_method_spec`).
RSpec.describe "Responsive-table: мітка колонки в broadcast-рядку", :js do
  let(:organization) { create(:organization, name: "Label Probe Org") }
  let(:password)     { "label-probe-1" }
  let!(:admin)       { create(:user, :admin, organization: organization, password: password) }

  before do
    sign_in_as(admin, password: password)
    visit "/dashboard"
  end

  # Синтетичний DOM навмисно: питання про ПОВЕДІНКУ БРАУЗЕРА, не про наш
  # маршрут. Прив'язка до сторінки телеметрії додала б у вимір її власні
  # змінні, не змінивши відповіді.
  def measure(script) = page.driver.browser.evaluate(script)

  it "foster-parenting: innerHTML виносить frame із tbody, а DOM-вставка — НІ" do
    result = measure(<<~JS)
      (() => {
        const host = document.createElement('div');
        document.body.appendChild(host);

        // (а) шлях парсера — саме про нього канонне твердження
        host.innerHTML = '<table><tbody id="p"><turbo-frame id="fp"></turbo-frame></tbody></table>';
        const parsed = document.getElementById('fp');
        const parsedInsideTbody = parsed ? parsed.parentElement.tagName : 'MISSING';

        // (б) шлях, яким РЕАЛЬНО їде Turbo Stream: <template> + DOM-вставка
        const tpl = document.createElement('template');
        tpl.innerHTML = '<turbo-frame id="fd"></turbo-frame>';
        const tbody = document.getElementById('p');
        tbody.appendChild(tpl.content);
        const domInsideTbody = document.getElementById('fd').parentElement.tagName;

        host.remove();
        return JSON.stringify({ parsed: parsedInsideTbody, dom: domInsideTbody });
      })()
    JS

    parsed = JSON.parse(result)

    # Канон казав саме це — і це підтвердилось для шляху парсера.
    expect(parsed["parsed"]).not_to eq("TBODY"),
      "foster-parenting не спрацював: канонна підстава §8.1а хибна для innerHTML"

    # 🔴 …але шлях доставки інший, і саме він вирішує застосовність класу 2.
    expect(parsed["dom"]).to eq("TBODY"),
      "DOM-вставка теж виносить frame — тоді клас 2 недосяжний жодним шляхом"
  end

  # `published` — чи таблиця публікує змінну; повертає обчислений `content`
  # псевдоелемента рядка, вставленого ПІСЛЯ таблиці (рівно як broadcast).
  def custom_property_probe = <<~JS
    ((published) => {
      const style = document.createElement('style');
      style.textContent = '#probe td::before { content: var(--probe-col-1, attr(data-label)); }';
      document.head.appendChild(style);

      const host = document.createElement('div');
      const publishes = published ? " style=\\"--probe-col-1: 'ЧАС'\\"" : '';
      host.innerHTML = '<table id="probe"' + publishes + '><tbody id="pb"></tbody></table>';
      document.body.appendChild(host);

      const tpl = document.createElement('template');
      tpl.innerHTML = '<tr><td data-label="Timestamp">x</td></tr>';
      document.getElementById('pb').appendChild(tpl.content);

      const content = getComputedStyle(document.querySelector('#pb td'), '::before').content;
      host.remove(); style.remove();
      return content;
    })
  JS

  # 🔴 Носій регресу, якого приклад вище не бачив ЗА ПОБУДОВОЮ: його синтетичний
  # рядок МАЄ `data-label`, тобто комірка-без-мітки лежала поза його світом.
  # Реальна така комірка є — `feed_placeholder` у телеметрії це один
  # `<td colspan="4">` зі спінером, тобто `nth-child(1)`; без `:not([colspan])`
  # він успадковував `--gaia-col-1` і на КОЖНОМУ мобільному завантаженні
  # друкував «Timestamp» над написом «очікуємо аплінк».
  it "комірка, що охоплює колонки, мітки НЕ отримує" do
    result = measure(<<~JS)
      (() => {
        const style = document.createElement('style');
        style.textContent =
          '#span-probe td:nth-child(1):not([colspan])::before { content: var(--gaia-col-1, attr(data-label)); }';
        document.head.appendChild(style);

        const host = document.createElement('div');
        host.innerHTML = "<table id='span-probe' style=\\"--gaia-col-1: 'ЧАС'\\"><tbody>" +
                         "<tr><td colspan='4'>spinner</td></tr>" +
                         "<tr><td>real</td></tr></tbody></table>";
        document.body.appendChild(host);

        const rows = host.querySelectorAll('tr');
        const spanning = getComputedStyle(rows[0].querySelector('td'), '::before').content;
        const normal   = getComputedStyle(rows[1].querySelector('td'), '::before').content;

        host.remove(); style.remove();
        return JSON.stringify({ spanning, normal });
      })()
    JS

    parsed = JSON.parse(result)

    expect(parsed["spanning"]).not_to include("ЧАС")
    # ⊥ Ліхтар: сусідній рядок БЕЗ colspan мітку отримує — без цього приклад
    # був би зелений і на правилі, яке не працює взагалі.
    expect(parsed["normal"]).to include("ЧАС")
  end

  it "CSS custom property зі СТОРІНКИ доїжджає у рядок, вставлений ПІСЛЯ неї" do
    parsed = {
      "resolved" => measure("#{custom_property_probe}(true)"),
      "fallback" => measure("#{custom_property_probe}(false)")
    }

    # Головне: мітка приїхала зі СТОРІНКИ, хоч рядок вставлено пізніше й без неї.
    expect(parsed["resolved"]).to include("ЧАС"),
      "custom property не успадкувалась у пізніше вставлений рядок — опція (а) §8.1а недосяжна"

    # Ліхтар: без фолбеку перша асершн проходила б і на зламаному механізмі,
    # бо `attr(data-label)` дав би «Timestamp», а не «ЧАС» — але довести це
    # можна лише показавши, що фолбек ЖИВИЙ і дає саме «Timestamp».
    expect(parsed["fallback"]).to include("Timestamp")
  end
end
