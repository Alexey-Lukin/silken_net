# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ДОСТАВКИ шрифта: родина, названа ПЕРШОЮ в `--font-mono`, мусить реально
# відвантажуватись — тобто мати власні `@font-face`, чиї файли Propshaft резолвить
# (`04_04 §4`).
#
# Народився з дефекту, який виглядав як коректний CSS і був невидимий з обох
# боків: `@theme` називав «JetBrains Mono» першим у стеку, 189 сайтів `font-mono`
# на нього спирались, а файлу не існувало НІДЕ — нуль `@font-face`, нуль woff2,
# нуль вебшрифт-лінків. Стек шрифтів не бреше синтаксично (перелічити невстановлений
# шрифт — законна прогресивна деградація), тому жоден лінтер тут нічого не скаже;
# ціна платиться рендером, і платить її не автор: на macOS стек падає в «SF Mono»,
# який виглядає близько до задуманого — саме тому дефект прожив непоміченим у тих,
# хто дивиться на екран щодня. На інших ОС родина інша, а на моно-таблицях різні
# метрики зсувають вирівнювання колонок хешів і адрес.
#
# ⚖️ Підстава гейта прецедентна, не смакова: клієнтський стан ламає ВІДТВОРЮВАНІСТЬ
# (тумблер теми зняли саме тому — скріншот аудитора залежав від його `localStorage`),
# а наявність шрифта в ОС є рівно тією ж залежністю, лише тихішою.
#
# 🔒 Стелі, названі чесно — зелений тут НЕ означає «типографіка правильна»:
#   · Гейт судить ДОСТАВКУ, ніколи ВИГЛЯД. Відвантажений шрифт із хибними
#     метриками чи без потрібного гліфа пройде.
#   · Судиться рівно ПЕРША родина стека — та, що є накресленням. Наступні є
#     фолбеками за визначенням, і вимагати відвантаження від них означало б
#     заборонити прогресивну деградацію.
#   · ПОКРИТТЯ підмножин (чи вистачає `unicode-range` на всі `available_locales`)
#     — ОКРЕМА вісь, і тут її свідомо немає: це друге речення, отже другий гейт
#     (`ssot-maintenance` §Guard-craft #46). Сьогодні відвантажено latin ·
#     latin-ext · cyrillic, що покриває en/lv/lt/uk.
#   · Курсивних облич не відвантажено СВІДОМО (виміряно: `italic` на 22 сайтах,
#     із них на `font-mono` один) — гейт про накреслення не питає.
#   · `--font-sans` під гейт НЕ підпадає: після ⚖️ 2026-08-19 його перша позиція
#     це `system-ui`, тобто накреслення = «системний», і відвантажувати нема чого.
module FontDeliveryGate
  THEME_PATH = Rails.root.join("app/assets/tailwind/application.css")
  # `@font-face` — НАШЕ оголошення, тож живе в нашому CSS; вендорені бінарники
  # лежать окремо (`vendor/assets/fonts`, SIL OFL), і межу тримає ця пара шляхів.
  FACE_PATH  = Rails.root.join("app/assets/stylesheets/application.css")

  module_function

  # Перша родина `--font-mono`. Береться з `@theme`, бо саме він є домом токена.
  def declared_mono_family
    decl = THEME_PATH.read[/--font-mono:\s*([^;]+);/m, 1]
    return nil if decl.nil?

    decl.strip[/\A"([^"]+)"/, 1] || decl.strip[/\A'([^']+)'/, 1] || decl.strip[/\A([\w-]+)/, 1]
  end

  # Тіла всіх `@font-face`, що оголошують саме цю родину.
  def faces_for(family)
    FACE_PATH.read.scan(/@font-face\s*\{(.*?)\}/m).flatten.select do |body|
      name = body[/font-family:\s*["']?([^"';]+)["']?\s*;/, 1]
      name&.strip == family
    end
  end

  # 🔴 ЗОВНІШНІЙ ЯКІР (§Guard-craft #67): судимо не власне оголошення, а вивід
  # Propshaft. Його `CssAssetUrls` на нерезолвний `url()` НЕ падає — він друкує
  # WARN у лог і лишає сирий патерн, тобто відсутній файл дає тихо зламане
  # посилання. Дайджест у шляху і є доказом, що файл справді знайдено.
  def compiled_font_urls
    css = Rails.application.assets.load_path.find("application.css")
    return [] if css.nil?

    Rails.application.assets.compilers.compile(css).scan(/url\("([^"]+\.woff2?)"\)/).flatten
  end

  DIGESTED = %r{\A/assets/.+-[0-9a-f]{8,}\.woff2?\z}

  # 🔴 GREEN-половина, і без неї гейт над-широкий (§Guard-craft #52). CSS-generic —
  # це не шрифт, який можна відвантажити, а вказівка «візьми системний». Якщо
  # присуд колись повернеться до системного накреслення, чесна перша позиція буде
  # саме такою — і гейт мусить МОВЧАТИ, інакше він червонить коректний код, а
  # найдешевша реакція на над-широкий гейт це послабити його.
  # Збіг ТОЧНИЙ, не префіксний: `monospace` звільнене, вигадане `monospace-x` — ні.
  CSS_GENERIC_FAMILIES = %w[
    ui-monospace monospace ui-sans-serif sans-serif ui-serif serif
    system-ui ui-rounded cursive fantasy math emoji fangsong
  ].freeze

  def generic?(family) = CSS_GENERIC_FAMILIES.include?(family)
end

RSpec.describe "Font delivery", type: :model do
  let(:family) { FontDeliveryGate.declared_mono_family }

  # Ліхтар на ПОПУЛЯЦІЮ: без нього кожен приклад нижче зелений на порожньому
  # наборі — гейт над зниклим токеном або порожнім деревом мовчав би вічно
  # (§Guard-craft #28).
  it "is a live check (the mono token exists and the tree uses it)" do
    expect(family).to be_present

    uses = Dir[Rails.root.join("app/views/**/*.rb")].sum { |f| File.read(f).scan(/\bfont-mono\b/).size }
    expect(uses).to be > 0, "нуль вжитків `font-mono` — гейт втратив підмет, зніми його"
  end

  it "declares @font-face for the family it names first" do
    skip "перша позиція — CSS-generic «#{family}», відвантажувати нема чого" if FontDeliveryGate.generic?(family)

    expect(FontDeliveryGate.faces_for(family)).not_to be_empty,
                                                      "`--font-mono` називає «#{family}» першою, але жодного `@font-face` для неї немає — " \
                                                      "тобто це побажання, а не накреслення: глядач без цього шрифта в ОС дістане наступний зі стеку"
  end

  # Пін на саму GREEN-половину: без нього «звільнення для generic» існує лише як
  # намір, і перший, хто спростить константу, зробить гейт над-широким мовчки.
  # Обидва боки, бо звільнення мусить бути ТОЧНИМ, а не префіксним.
  it "exempts CSS generics exactly, and nothing that merely looks like one" do
    expect(FontDeliveryGate.generic?("ui-monospace")).to be true
    expect(FontDeliveryGate.generic?("system-ui")).to be true
    expect(FontDeliveryGate.generic?("ui-monospace-condensed")).to be false
    expect(FontDeliveryGate.generic?("JetBrains Mono")).to be false
  end

  # Друга половина, і саме вона ловить справжній режим відмови: оголошення може
  # СТОЯТИ, а файл — зникнути (перейменування, недовендорений woff2, забутий
  # `assets.paths`). Тоді CSS синтаксично бездоганний і мовчки неробочий.
  it "delivers every declared face — Propshaft resolves each src to a digested asset" do
    urls = FontDeliveryGate.compiled_font_urls

    expect(urls).not_to be_empty, "у скомпільованому `application.css` нема жодного `url(*.woff2)`"
    unresolved = urls.reject { |u| u.match?(FontDeliveryGate::DIGESTED) }
    expect(unresolved).to be_empty,
                          "Propshaft не резолвив #{unresolved.inspect} — він друкує WARN і лишає сирий патерн, " \
                          "тож шрифт мовчки не доїде до браузера"
  end

  # [UI.1, ⚖️ 2026-08-20] Зовнішніх origin'ів у продовому CSS — НУЛЬ, і це
  # присуд, а не спостереження: carbon-weave текстура самохоститься (чужий хост
  # уже флейкував браузерну CI-смугу — Ferrum::PendingConnectionsError), а
  # `importmap_locality_spec` стереже лише JS-імпорти, тож CSS-URL доти не
  # стеріг ніхто. Судиться ВЕСЬ compiled Tailwind-білд (зовнішній якір #67);
  # CARTO-тайли сюди не входять за побудовою — їх вантажить JS, не CSS.
  it "keeps the compiled CSS free of external origins — every url() is local" do
    css = Rails.application.assets.load_path.find("tailwind.css")
    expect(css).not_to be_nil, "tailwind.css відсутній у load_path — білд не зібрано"

    compiled = Rails.application.assets.compilers.compile(css)
    urls = compiled.scan(/url\((["']?)(.+?)\1\)/).map(&:last)
    expect(urls).not_to be_empty, "у скомпільованому tailwind.css нема жодного url() — ліхтар популяції"
    external = urls.select { |u| u.match?(%r{\A(?:https?:)?//}) }
    expect(external).to be_empty,
                        "зовнішні origin'и в продовому CSS: #{external.inspect} — вендорь асет " \
                        "(прецедент carbon-weave.png) або визнай origin явним CSP-рядком і носієм тут"
  end
end
