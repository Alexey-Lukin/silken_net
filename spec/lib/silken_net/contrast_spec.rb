# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/silken_net/contrast"

# Юніт на ЧИСТУ WCAG-арифметику. Rails тут не потрібен — і це навмисно:
# двигун мусить бути доказовним без браузера, інакше єдиним способом
# перевірити число був би той самий браузер, чиї числа він і судить.
#
# 🔒 Оракули тут — ЛІТЕРАЛИ з опублікованих джерел, ніколи не переобчислення
# тією ж формулою. Спека, що рахує очікування логікою під тестом, — тавтологія,
# нездатна почервоніти (`04_06 §B.2` BP #12 / `ssot-maintenance` §Guard-craft).
# Кожен рядок: [опис, foreground, background, очікуваний ratio].
# Джерела оракулів — ЗОВНІШНІ: WebAIM Contrast Checker і опубліковані
# тесткейси W3C ACT-правила afw4f7. Жодне число тут не отримане цим кодом.
#
# Локальна змінна, а не константа: форма взята з `spec/i18n/enum_label_parity_spec.rb`
# — константа всередині `describe` протекла б у глобальний простір.
known_pairs = [
      [ "чорний на білому — теоретичний максимум", "#000000", "#ffffff", 21.00 ],
      [ "білий на білому — теоретичний мінімум",   "#ffffff", "#ffffff",  1.00 ],
      [ "#767676 — найсвітліший сірий, що ТРИМАЄ AA на білому", "#767676", "#ffffff", 4.54 ],
      [ "#777777 — на волосину НЕ тримає AA",      "#777777", "#ffffff",  4.48 ],
      [ "#595959 — канонічна межа AAA на білому",  "#595959", "#ffffff",  7.00 ],
      [ "#5a5a5a — на волосину НЕ тримає AAA",     "#5a5a5a", "#ffffff",  6.90 ],
      [ "#949494 — межа 3:1 (великий текст / non-text)", "#949494", "#ffffff", 3.03 ],
      [ "чистий синій на білому",                  "#0000ff", "#ffffff",  8.59 ],
      [ "червоний на білому — славетне «майже 4.5»", "#ff0000", "#ffffff", 4.00 ],
      [ "ACT afw4f7 Passed Example 1",             "#333333", "#ffffff", 12.63 ],
      [ "ACT afw4f7 Failed Example 1",             "#aaaaaa", "#ffffff",  2.32 ],
      # Світліший ПЕРЕДНІЙ план — інакше формула могла б мовчки припускати,
      # що текст завжди темніший за поверхню (у нашій темній темі це не так).
      [ "білий на синьому — дзеркало #7",          "#ffffff", "#0000ff",  8.59 ],
      [ "білий на #767676 — дзеркало #3",          "#ffffff", "#767676",  4.54 ],
      [ "жовтий на чорному",                       "#ffff00", "#000000", 19.56 ],
  [ "помаранчевий на чорному",                 "#ffa500", "#000000", 10.63 ]
].freeze

RSpec.describe SilkenNet::Contrast do
  describe ".ratio — проти опублікованих значень WCAG" do
    known_pairs.each do |label, fg, bg, expected|
      it "gives #{expected}:1 for #{label}" do
        actual = described_class.ratio(described_class.parse(fg), described_class.parse(bg))

        expect(actual).to be_within(0.01).of(expected)
      end
    end

    it "is symmetric — swapping foreground and background cannot change the verdict" do
      dark  = described_class.parse("#0f172a")
      light = described_class.parse("#d1fae5")

      expect(described_class.ratio(dark, light)).to eq(described_class.ratio(light, dark))
    end
  end

  describe ".parse" do
    it "reads the functional forms getComputedStyle actually returns" do
      expect(described_class.parse("rgb(16, 185, 129)")).to eq([ 16.0, 185.0, 129.0, 1.0 ])
      expect(described_class.parse("rgba(52, 211, 153, 0.55)")).to eq([ 52.0, 211.0, 153.0, 0.55 ])
    end

    it "reads hex so @theme values can be measured without a browser" do
      expect(described_class.parse("#10b981")).to eq([ 16.0, 185.0, 129.0, 1.0 ])
      expect(described_class.parse("#fff")).to eq([ 255.0, 255.0, 255.0, 1.0 ])
    end

    # Альфа-суфікс hex — четвертий байт ділиться на 255, тоді як три-/шести-
    # значний hex дає непрозорий 1.0. Гілку доти виконував лише браузерний
    # харнес, а джоба, що МІРЯЄ покриття, ганяє сюїту з `--exclude-pattern`
    # на `features/**`, тож локально вона була покрита, а в CI — ні: поріг
    # міряв не код, а те, які специ ввійшли в прогін.
    it "reads the alpha suffix of an 8- and 4-digit hex" do
      expect(described_class.parse("#10b98180")).to eq([ 16.0, 185.0, 129.0, 128 / 255.0 ])
      expect(described_class.parse("#fff0")).to eq([ 255.0, 255.0, 255.0, 0.0 ])
    end

    # 🔴 Найважливіша група файлу. Невідомий формат МУСИТЬ вибухнути, бо тихо
    # повернутий дефолт дав би правдоподібне число з непрочитаного рядка —
    # «дефолт, що звужує, невідрізнимий від перевірки, що проходить».
    %w[transparent currentColor inherit oklch(0.7\ 0.1\ 160)].each do |unreadable|
      it "refuses to guess at #{unreadable.inspect} instead of defaulting silently" do
        expect { described_class.parse(unreadable) }
          .to raise_error(SilkenNet::Contrast::UnparseableColour)
      end
    end

    it "refuses an empty string" do
      expect { described_class.parse("") }.to raise_error(SilkenNet::Contrast::UnparseableColour)
    end
  end

  # 🔴 Ця група і є причина, чому прилад мусить бути браузерним, а не статичним:
  # той самий токен дає 3.71:1 з композитом і 10.03:1 без нього — тобто помилка
  # тут не косметична, вона перевертає ВЕРДИКТ у безпечний бік.
  describe ".composite — напівпрозорий текст поверх непрозорої поверхні" do
    let(:dark_surface) { described_class.parse("#0b0f0e") }

    it "changes the verdict for the repo's own semi-transparent token" do
      subtle_dark = described_class.parse("rgba(52, 211, 153, 0.55)")

      composited = described_class.ratio(described_class.composite(subtle_dark, dark_surface), dark_surface)
      naive      = described_class.ratio(subtle_dark, dark_surface)

      expect(composited).to be_within(0.01).of(3.71)
      expect(naive).to be_within(0.01).of(10.03)
      expect(composited).to be < naive
    end

    # 🔴 Найцінніший вектор файлу: він розрізняє ПРАВИЛЬНИЙ композит від
    # правдоподібного. W3C ACT-правило afw4f7 публікує тесткейс «чорний текст із
    # 30% альфи на білому = 2.1:1». Той самий композит, зроблений у ЛІНІЙНОМУ
    # просторі замість гамма-кодованого sRGB, дає 1.40:1 — тобто помилка простору
    # не «неточність», вона перевертає вердикт. Без зовнішнього числа обидві
    # реалізації виглядають однаково розумними.
    it "matches the W3C ACT published value for 30%-alpha black on white" do
      thirty_percent_black = described_class.parse("rgba(0, 0, 0, 0.3)")
      white                = described_class.parse("#ffffff")

      composited = described_class.ratio(described_class.composite(thirty_percent_black, white), white)

      expect(composited).to be_within(0.02).of(2.11)
    end

    it "leaves a fully opaque colour untouched" do
      opaque = described_class.parse("#10b981")

      expect(described_class.composite(opaque, dark_surface)).to eq([ 16.0, 185.0, 129.0 ])
    end

    it "resolves a fully transparent source to the surface itself" do
      invisible = described_class.parse("rgba(255, 0, 0, 0)")

      expect(described_class.composite(invisible, dark_surface)).to eq(dark_surface.first(3))
    end
  end

  # WCAG SC 1.4.3: large-scale = ≥18pt, або ≥14pt bold. У CSS-пікселях
  # (1pt = 4/3px) це 24px і 18.6667px. Пари підібрані так, щоб КОЖНА межа
  # мала приклад з обох боків — інакше зсув порога на піксель лишився б зеленим.
  describe ".threshold — межа великого тексту" do
    {
      [ 23.9,    400 ] => 4.5,
      [ 24.0,    400 ] => 3.0,
      [ 18.0,    700 ] => 4.5,
      [ 18.6667, 700 ] => 3.0,
      [ 18.6667, 400 ] => 4.5,
      [ 32.0,    100 ] => 3.0,
      # 🔴 Межа ВАГИ теж потребує прикладу з обох боків, і доти його не було:
      # уся таблиця вище виживала мутацію `BOLD_WEIGHT = 700 → 600`. А 600
      # (`font-semibold`) — робоча вага в цьому дереві, тож зсув порога тихо
      # знизив би планку з 4.5 на 3.0 для реального тексту.
      [ 20.0,    600 ] => 4.5,
      [ 20.0,    700 ] => 3.0
    }.each do |(size, weight), expected|
      it "is #{expected} at #{size}px / weight #{weight}" do
        expect(described_class.threshold(font_size_px: size, font_weight: weight)).to eq(expected)
      end
    end
  end

  # Причина існування цієї групи — вимір, а не повнота: у дереві 109 сайтів
  # несуть напівпрозорий фон. Збирач, що шукає «перший НЕПРОЗОРИЙ фон»,
  # пропустив би такий шар і повернув колір панелі під ним.
  describe ".flatten_backdrop — стек напівпрозорих шарів" do
    it "composites the stack instead of skipping to the first opaque layer" do
      # Реальна форма з дерева: `bg-black/80` над білою панеллю.
      flattened = described_class.flatten_backdrop([ "rgba(0, 0, 0, 0.8)", "rgb(255, 255, 255)" ])
      skipped   = described_class.parse("rgb(255, 255, 255)").first(3)

      expect(flattened.map(&:round)).to eq([ 51, 51, 51 ])
      expect(flattened).not_to eq(skipped)
    end

    it "changes the verdict for white text — the defect this method exists for" do
      white = described_class.parse("#ffffff")
      honest = described_class.ratio(white, described_class.flatten_backdrop([ "rgba(0, 0, 0, 0.8)", "rgb(255, 255, 255)" ]))
      naive  = described_class.ratio(white, described_class.parse("rgb(255, 255, 255)"))

      expect(honest).to be > 4.5   # білий на майже-чорному — читабельно
      expect(naive).to  be < 1.1   # білий на білому — «виміряно» й неправильно
    end

    it "applies layers nearest-last, so stacking order cannot be silently inverted" do
      over_black = described_class.flatten_backdrop([ "rgba(255, 255, 255, 0.5)", "rgb(0, 0, 0)" ])
      over_white = described_class.flatten_backdrop([ "rgba(0, 0, 0, 0.5)", "rgb(255, 255, 255)" ])

      expect(over_black.map(&:round)).to eq([ 128, 128, 128 ])
      expect(over_white.map(&:round)).to eq([ 128, 128, 128 ])
    end

    # 🔴 ТРИ шари, а не два — і це не педантизм. При двох шарах `layers[0..-2]`
    # має рівно ОДИН елемент, тож `.reverse` у реалізації є no-op: видалення
    # його лишало б кожен двошаровий приклад зеленим, а колір фону на реальних
    # тришарових сайтах — неправильним. Червоний і синій тут розведені навмисно:
    # інверсія порядку міняє їх місцями, і це видно поіменно.
    it "composites three layers in the right order (two layers cannot prove this)" do
      flattened = described_class.flatten_backdrop([
        "rgba(255, 0, 0, 0.5)", "rgba(0, 0, 255, 0.5)", "rgb(255, 255, 255)"
      ])

      expect(flattened.map { |c| c.round(2) }).to eq([ 191.25, 63.75, 127.5 ])
      # інвертований порядок дав би [127.5, 63.75, 191.25] — R і B міняються
      expect(flattened[0]).to be > flattened[2]
    end

    it "refuses a stack whose deepest layer is still translucent" do
      expect { described_class.flatten_backdrop([ "rgba(0, 0, 0, 0.5)" ]) }
        .to raise_error(SilkenNet::Contrast::UnparseableColour, /напівпрозорий/)
    end

    it "refuses an empty stack rather than assuming a page background" do
      expect { described_class.flatten_backdrop([]) }
        .to raise_error(SilkenNet::Contrast::UnparseableColour)
    end
  end

  describe ".measure" do
    # Конформанс визначено як «at least 4.5:1», тож вердикт мусить рахуватись на
    # НЕОКРУГЛЕНОМУ значенні: #777777 на білому це 4.4781, і воно провалює AA,
    # хоч у звіті виглядає як «4.48». Порівняння округленого пропустило б рівно
    # межові пари — тобто саме ті, заради яких прилад і будувався.
    # 🔴 Вектор підібраний так, що ОКРУГЛЕННЯ ПЕРЕВЕРТАЄ вердикт: сирий 4.499686
    # провалює планку 4.5, округлений 4.50 — проходить. Це єдина форма, здатна
    # вбити мутацію `passes: value.round(2) >= bar`.
    # ⚠️ Попередній вектор (`#777777`, 4.478/4.48) цього не вмів: обидва числа
    # менші за планку, тож приклад був зелений при обох реалізаціях. Серед
    # чистих сірих таких пар немає взагалі — вибірка «сірий на білому» цю вісь
    # не бачила в принципі.
    it "judges the raw ratio, not the rounded one shown in the report" do
      result = described_class.measure(
        text: "#0481a2", surface: "#ffffff", font_size_px: 16, font_weight: 400
      )

      expect(result[:ratio]).to eq(4.50)
      expect(result[:passes]).to be(false)
    end

    it "still fails a pair that misses on both the raw and the rounded value" do
      result = described_class.measure(
        text: "#777777", surface: "#ffffff", font_size_px: 16, font_weight: 400
      )

      expect(result[:ratio]).to eq(4.48)
      expect(result[:passes]).to be(false)
    end

    it "reports the ratio, the bar it was judged against, and the verdict" do
      result = described_class.measure(
        text: "rgb(156, 163, 175)", surface: "rgb(255, 255, 255)",
        font_size_px: 16, font_weight: 400
      )

      expect(result).to eq(ratio: 2.54, threshold: 4.5, passes: false, large_text: false)
    end

    # Поверхня, що сама напівпрозора, означає, що збирач не дорозв'язав фон.
    # Тихо прийняти її = виміряти пару, якої на екрані немає.
    it "refuses a surface that is itself translucent — that means the backdrop was never resolved" do
      expect {
        described_class.measure(
          text: "#ffffff", surface: "rgba(0, 0, 0, 0.8)",
          font_size_px: 16, font_weight: 400
        )
      }.to raise_error(SilkenNet::Contrast::UnparseableColour, /напівпрозора/)
    end
  end
end
