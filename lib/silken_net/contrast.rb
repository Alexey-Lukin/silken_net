# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module SilkenNet
  # WCAG 2.x контраст — ЧИСТА арифметика, без Rails і без браузера.
  #
  # Дім: пара «текст ⟷ поверхня» вимірюється лише там, де обидві половини
  # ВІДОМІ, а відомими їх робить браузер (`00_07` UI.3). Тут — рівно рахунок;
  # збирання пар живе в `spec/support/contrast_audit.rb`.
  #
  # 🔴 Чому це окремий файл, а не приватні методи спеки: сторож і кампанія
  # мусять рахувати ОДНИМ кодом, інакше вони розійдуться (`ssot-maintenance`
  # §Guard-craft, таксономія носіїв). Той самий модуль обслуговує і звіт
  # міграції, і CI-гейт.
  #
  # 🔒 Стелі, названі чесно:
  #   · Модуль судить ПАРУ, яку йому дали. Він не знає, чи ця пара справді
  #     стоїть одна на одній — це відповідальність збирача.
  #   · Невідомий формат кольору = ВИНЯТОК, ніколи не мовчазний дефолт. Число,
  #     виведене з припущення про непрочитаний рядок, гірше за відмову міряти
  #     (клас «мовчазний дефолт»: дефолт, що звужує, невідрізнимий від
  #     перевірки, що проходить).
  #   · Композит робиться в sRGB (гамма-кодованому) просторі — так, як
  #     компонує браузер. Лінеаризація йде ПІСЛЯ композиту, і цей порядок
  #     несучий: переставивши його, дістанеш правдоподібне й неправильне число.
  module Contrast
    # Невідомий/нечитабельний CSS-колір. Ловиться збирачем і рахується як
    # окрема ПРИЧИНА невимірності, а не як «нуль порушень».
    class UnparseableColour < StandardError; end

    # WCAG 2.1/2.2, Relative luminance. Поріг 0.04045 — errata W3C травня 2021;
    # чинні REC (WCAG 2.2 · 2.1) несуть саме його, дореррат-значення було 0.03928.
    #
    # ⚠️ Тут доти стояло сім рядків про те, що для НАС заміна нібито не
    # косметика — мовляв, альфа-композит дає дробові канали, які можуть лягти
    # у щілину між порогами. **Заява спростована виміром, а не зня́та за
    # непотрібністю.** Щілина — це канал у [10.016, 10.315]; вектор, свідомо
    # сконструйований у неї (`rgba(255,255,255,0.04)` над чорним → канал 10.2),
    # дає 19.775510 проти 19.775687, тобто різницю 0.000177 — на два порядки
    # нижчу за точність звіту, і `round(2)` в обох випадках 19.78. Специфікація
    # має рацію: «has no practical effect» чинне й для дробових каналів.
    # Константа лишається новою, бо це чинна норма, а не бо вона щось міняє.
    LINEARISATION_CUTOFF = 0.04045
    CHANNEL_WEIGHTS      = { r: 0.2126, g: 0.7152, b: 0.0722 }.freeze
    CONTRAST_OFFSET      = 0.05

    # SC 1.4.3 (AA). «Large-scale» = ≥18pt, або ≥14pt bold.
    # CSS-конвенція: 1pt = 4/3 px → 18pt = 24px, 14pt = 56/3 px.
    # 🔴 Дріб, а не десяткове: `18.6667` БІЛЬШЕ за справжні 14pt
    # (18.666666…), тож текст рівно 14pt bold судився барою 4.5 замість
    # 3.0 — виміряно, не виведено. Через браузер це не спрацьовувало
    # (Chrome сам віддає «18.6667px»), але прямий Ruby-виклик — так.
    LARGE_TEXT_PX        = 24.0
    LARGE_BOLD_TEXT_PX   = 56.0 / 3
    BOLD_WEIGHT          = 700

    THRESHOLD_NORMAL = 4.5
    THRESHOLD_LARGE  = 3.0

    RGB_FUNCTIONAL = /\A
      rgba?\(\s*
      (?<r>[\d.]+)\s*[,\s]\s*
      (?<g>[\d.]+)\s*[,\s]\s*
      (?<b>[\d.]+)
      (?:\s*[,\/]\s*(?<a>[\d.]+%?))?
      \s*\)
    \z/x

    HEX = /\A\#(?<hex>\h{3,8})\z/

    module_function

    # CSS-рядок → [r, g, b, a] у 0..255 / 0..1.
    #
    # Приймає рівно ті форми, які реально віддає `getComputedStyle` (rgb/rgba)
    # плюс hex — щоб тим самим кодом можна було рахувати значення з `@theme`
    # без браузера. Усе інше (`oklch`, `color-mix`, `transparent`, `currentColor`)
    # — виняток: ці форми потребують контексту, якого модуль не має.
    def parse(css)
      raw = css.to_s.strip
      raise UnparseableColour, "порожній колір" if raw.empty?

      if (m = RGB_FUNCTIONAL.match(raw))
        return in_gamut!([ m[:r].to_f, m[:g].to_f, m[:b].to_f, parse_alpha(m[:a]) ], raw)
      end

      return parse_hex(Regexp.last_match(:hex)) if HEX.match(raw)

      raise UnparseableColour, "нерозпізнаний формат кольору: #{raw.inspect}"
    end

# 🔴 Fail-loud і в ДРУГИЙ бік. Парсер був асиметричний: `rgb(-20,0,0)` кидав
# (регекс не бере мінус), а `rgb(300,0,0)` проходив МОВЧКИ як 300.0 — і далі
# давав яскравість >1 та безглузде відношення з виглядом обчисленого.
# Через браузер це недосяжно (`getComputedStyle` клампить), тож клас
# ЛАТЕНТНИЙ — саме тому й закривається тут, а не гейтом: рукописний виклик у
# спеці є повноцінним входом цього модуля.
# ⚠️ Клампити НЕ можна: тихо виправлене значення — це той самий мовчазний
# дефолт, лише з іншого боку.
def in_gamut!(rgba, raw)
  r, g, b = rgba
  return rgba if [ r, g, b ].all? { |c| c.between?(0, 255) }

  raise UnparseableColour, "канал поза 0..255: #{raw.inspect}"
end

    def parse_alpha(token)
      return 1.0 if token.nil?

      token.end_with?("%") ? token.to_f / 100.0 : token.to_f
    end

    def parse_hex(hex)
      digits = case hex.length
      when 3, 4 then hex.chars.flat_map { |c| [ c, c ] }.join
      when 6, 8 then hex
      else raise UnparseableColour, "hex довжини #{hex.length}"
      end

      bytes = digits.scan(/\h{2}/).map { |pair| pair.to_i(16) }
      [ bytes[0].to_f, bytes[1].to_f, bytes[2].to_f, bytes[3] ? bytes[3] / 255.0 : 1.0 ]
    end

    # Source-over композит напівпрозорого поверх НЕПРОЗОРОГО, у sRGB.
    #
    # Формула для непрозорого низу (Ab = 1) вироджується в лінійну
    # інтерполяцію: Cr = Cs·As + Cb·(1 − As).
    def composite(source, backdrop)
      alpha = source[3]
      return source.first(3) if alpha >= 1.0

      (0..2).map { |i| source[i] * alpha + backdrop[i] * (1.0 - alpha) }
    end

    # Згортає СТЕК фонових шарів в один непрозорий колір.
    #
    # 🔴 Причина існування цього методу — не повнота, а дефект, який без нього
    # неминучий: у дереві 109 сайтів несуть напівпрозорий фон (`bg-black/80`,
    # `bg-emerald-950/10`, `bg-gaia-surface/80`). Збирач, що шукає «перший
    # НЕПРОЗОРИЙ фон», такий шар ПРОПУСКАЄ і повертає колір панелі під ним —
    # тобто видає правдоподібне й неправильне число, ще й у безпечний бік.
    #
    # Стек іде від НАЙБЛИЖЧОГО шару до найдальшого; останній мусить бути
    # непрозорим (його розв'язує збирач, дійшовши до `<body>`).
    def flatten_backdrop(stack)
      raise UnparseableColour, "порожній стек фону" if stack.empty?

      layers = stack.map { |css| parse(css) }
      base   = layers.last
      raise UnparseableColour, "найглибший шар фону напівпрозорий: #{stack.last.inspect}" if base[3] < 1.0

      layers[0..-2].reverse.reduce(base.first(3)) { |acc, layer| composite(layer, acc) }
    end

    def relative_luminance(rgb)
      linear = rgb.first(3).map do |channel|
        c = channel / 255.0
        c <= LINEARISATION_CUTOFF ? c / 12.92 : (((c + 0.055) / 1.055)**2.4)
      end

      CHANNEL_WEIGHTS[:r] * linear[0] +
        CHANNEL_WEIGHTS[:g] * linear[1] +
        CHANNEL_WEIGHTS[:b] * linear[2]
    end

    # Контраст двох НЕПРОЗОРИХ кольорів. Симетричний за побудовою.
    def ratio(one, two)
      a = relative_luminance(one)
      b = relative_luminance(two)
      lighter, darker = a > b ? [ a, b ] : [ b, a ]

      (lighter + CONTRAST_OFFSET) / (darker + CONTRAST_OFFSET)
    end

    def large_text?(font_size_px:, font_weight:)
      size = font_size_px.to_f
      return true if size >= LARGE_TEXT_PX

      font_weight.to_i >= BOLD_WEIGHT && size >= LARGE_BOLD_TEXT_PX
    end

    def threshold(font_size_px:, font_weight:)
      large_text?(font_size_px: font_size_px, font_weight: font_weight) ? THRESHOLD_LARGE : THRESHOLD_NORMAL
    end

    # Повний вимір однієї пари. `text` і `surface` — CSS-рядки як їх віддав
    # браузер; поверхня МУСИТЬ бути непрозорою (розв'язує її збирач).
    #
    # Повертає хеш із самим числом І з порогом, проти якого його судили —
    # інакше звіт неможливо перечитати, не переобчислюючи.
    def measure(text:, surface:, font_size_px:, font_weight:)
      fg = parse(text)
      bg = parse(surface)
      raise UnparseableColour, "поверхня напівпрозора: #{surface.inspect}" if bg[3] < 1.0

      composited = composite(fg, bg)
      value      = ratio(composited, bg.first(3))
      bar        = threshold(font_size_px: font_size_px, font_weight: font_weight)

      # 🔴 Вердикт судиться на НЕОКРУГЛЕНОМУ значенні, округлюється лише те, що
      # йде в звіт. Конформанс визначено як «at least 4.5:1», тож 4.478 — це
      # провал, хоч на екрані він виглядає як «4.48». Порівняння округленого
      # тихо пропустило б рівно межові пари.

      {
        ratio: value.round(2),
        threshold: bar,
        passes: value >= bar,
        large_text: bar == THRESHOLD_LARGE
      }
    end
  end
end
