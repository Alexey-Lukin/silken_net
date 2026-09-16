# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Скелетон lazy-фрейма займає ТУ САМУ коробку, що й вміст, який він заступає.
#
# 🔬 Чому вимір, а не пін на класи. Доти `04_04 §18.4` стверджував «варіанти
# займають той самий простір, що й контент» без жодного носія — і вимір
# 2026-09-16 показав, що твердження хибне на КОЖНІЙ сторінці з lazy-фреймом:
#   · скелетон малював власну картку (`p-10 border bg-gaia-surface`), чужу для
#     всіх вмістів — Δh +171 (метадані гаманця) · +52 (баланс) · −58 (хроніка:
#     картка в картці власника), фон `surface` там, де вміст `sunken`;
#   · `<turbo-frame>` за замовчуванням INLINE, тож `space-y-8` батька на нього не
#     діяв — під балансом зазор 0 замість 32px, і в скелетоні, і з вмістом.
# Жоден статичний пін цього не бачить: коробку складають класи з ДВОХ файлів
# (сторінка + компонент фрейма), а зазор — CSS-дефолт, якого в розмітці немає.
#
# 🧭 Як отримано обидва стани без блокування мережі. Сторінка вантажиться
# звичайно — міряється вміст; потім розмітка фреймів береться з HTML ЦІЄЇ Ж
# сторінки (`fetch` + `DOMParser`), тобто рівно той скелетон, що віддає сервер,
# кладеться назад у фрейм і міряється вдруге: та сама розкладка, той самий візит.
# ⚠️ `url_blacklist` драйвера тут свідомо НЕ вжито: виміряно, що присвоєння `[]`
# блокування не знімає, тобто він отруїв би сусідні браузерні приклади.
#
# 🔒 Стелі, названі поіменно:
#   · висота судиться з допуском `height_tolerance_px` — вміст переносить рядки
#     залежно від ширини (хеш транзакції, підпис власника балансу), а скелетон
#     переносів не знає; допуск ловить клас «загальний варіант не того розміру»,
#     не піксельну точність;
#   · хроніка дерева міряється на ПОРОЖНІЙ стрічці — з подіями вміст вищий, і
#     скільки їх, скелетон знати не може;
#   · лише горизонтальний вихід кісток; одна тема (геометрія від теми не залежить);
#   · лише lazy-фрейми сторінок — broadcast-стаби судять власні компонентні спеки.
RSpec.describe "Скелетон lazy-фрейма займає коробку свого вмісту", :js do
  def height_tolerance_px = 48 # три текстові рядки
  def widths = [ 390, 1024, 1440 ]

  # Коробка = обчислені стилі першого елемента фрейма. Обчислені, а не рядок класів:
  # той самий вигляд різним порядком класів — не розбіжність.
  def measure_js = <<~JS
    const done = arguments[0];
    const frames = Array.from(document.querySelectorAll('turbo-frame[loading="lazy"]'));
    const snap = () => frames.map((f) => {
      const box = f.getBoundingClientRect();
      const first = f.firstElementChild;
      const cs = first ? getComputedStyle(first) : null;
      const next = f.nextElementSibling;
      return {
        id: f.id,
        height: Math.round(box.height),
        chrome: cs && [cs.padding, cs.borderWidth, cs.backgroundColor, cs.boxShadow].join(' | '),
        gap: next ? Math.round(next.getBoundingClientRect().top - box.bottom) : null,
        escaped: Array.from(f.querySelectorAll('.animate-pulse'))
          .filter((b) => b.getBoundingClientRect().right > box.right + 1).length,
        bones: f.querySelectorAll('.animate-pulse').length
      };
    });
    const loaded = snap();
    fetch(location.href, { headers: { Accept: 'text/html' } })
      .then((r) => r.text())
      .then((html) => {
        const served = new DOMParser().parseFromString(html, 'text/html');
        frames.forEach((f) => { f.innerHTML = served.getElementById(f.id).innerHTML; });
        done({ loaded, skeleton: snap() });
      });
  JS

  let(:password)      { "skeleton-box-1" }
  let!(:organization) { create(:organization) }
  let!(:actor)        { create(:user, :super_admin, organization: organization, password: password) }
  let!(:cluster)      { create(:cluster, organization: organization) }
  let!(:tree)         { create(:tree, cluster: cluster) }
  let!(:wallet)       { create(:wallet, tree: tree) }
  let!(:transaction)  { create(:blockchain_transaction, wallet: wallet) }

  def measure(path, width)
    page.driver.resize(width, 900)
    visit_ok path
    # `loading: lazy` вантажить лише фрейм у вьюпорті — на вузькій ширині половина
    # сторінок ховає свій нижче першого екрана.
    page.driver.browser.evaluate("document.querySelectorAll('turbo-frame[loading=\"lazy\"]').forEach((f) => f.scrollIntoView())")
    expect(page).to have_no_css('turbo-frame[loading="lazy"]:not([complete])', wait: 10)

    page.driver.browser.evaluate_async(measure_js, 10)
  end

  def judge(content, placeholder, width)
    at = "#{content['id'].sub(/_\d+\z/, '')}@#{width}"
    delta = content["height"] - placeholder["height"]

    [
      ("#{at}: у скелетоні нема жодної кістки" if placeholder["bones"].zero?),
      ("#{at}: хром скелетона «#{placeholder['chrome']}» ≠ вмісту «#{content['chrome']}»" if placeholder["chrome"] != content["chrome"]),
      ("#{at}: Δh #{delta}px (скелетон #{placeholder['height']} → вміст #{content['height']})" if delta.abs > height_tolerance_px),
      ("#{at}: #{placeholder['escaped']} кісток виходять за фрейм" if placeholder["escaped"].positive?),
      ("#{at}: зазор під фреймом (скелетон) = #{placeholder['gap']}px — фрейм inline?" if placeholder["gap"]&.<=(0)),
      ("#{at}: зазор під фреймом (вміст) = #{content['gap']}px — фрейм inline?" if content["gap"]&.<=(0))
    ].compact
  end

  it "тримає хром, висоту й зазор вмісту на кожній ширині, і кістки не виходять за фрейм" do
    sign_in_as(actor, password: password)

    pages = {
      "/wallets/#{wallet.id}" => 2,
      "/blockchain_transactions/#{transaction.id}" => 1,
      "/trees/#{tree.id}" => 1
    }

    failures = []
    measured = 0

    widths.each do |width|
      pages.each do |path, frame_count|
        loaded, skeleton = measure(path, width).values_at("loaded", "skeleton")

        # Ліхтар: фрейм, що не знайшовся, дав би нуль розбіжностей безкоштовно.
        failures << "#{path}@#{width}: #{loaded.size} lazy-фреймів, очікувано #{frame_count}" if loaded.size != frame_count

        loaded.zip(skeleton).each do |content, placeholder|
          measured += 1
          failures.concat(judge(content, placeholder, width))
        end
      end
    end

    expect(measured).to eq(widths.size * pages.values.sum)
    expect(failures).to be_empty, failures.join("\n")
  end
end
