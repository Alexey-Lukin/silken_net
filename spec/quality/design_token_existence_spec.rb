# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ІСНУВАННЯ токена: кожен `<utility>-<gaia|status|token>-*` клас, ужитий у
# Phlex-дереві, мусить бути оголошений у `@theme` (`04_04 §3`).
#
# Народився з дефекту, що прожив непоміченим і був невидимий за побудовою:
# `text-gaia-primary-text` стояв на ДЕВ'ЯТИ сайтах у шести файлах, а
# `--color-gaia-primary-text` не існував ніде. Tailwind v4 на невідомий токен не
# лається — він просто НЕ ГЕНЕРУЄ клас, тож розмітка виглядає правильною, CSS
# мовчить, і колір тексту тихо успадковується від `<body>`. Наслідок був не
# косметичний: три кнопки на `bg-gaia-primary` діставали успадкований
# `--gaia-text`, що в ТЕМНІЙ темі (єдиній, якою користуються) дає 1.98:1 при
# планці WCAG AA 4.5:1 — тобто нечитабельно. Спека самого компонента при цьому
# пінила `include("text-gaia-primary-text")` і була зелена: вона стверджувала
# наявність РЯДКА, а не існування токена (`04_06 §B.2` BP #14).
#
# 🔒 Стелі, названі чесно — зелений тут НЕ означає «кольори правильні»:
#   · Гейт судить ІСНУВАННЯ, ніколи ПРИДАТНІСТЬ. Оголошений токен із контрастом
#     1.1:1 пройде: контраст — окрема вісь (`00_07` UI.3), і вона потребує
#     фактичної пари fg/bg, яку статичний скан не бачить (фон часто приходить
#     від батьківського компонента або з `<body>` за три файли вгору).
#   · Джерелом істини для ЦІЄЇ вісі взято `application.css`, а не білд — бо
#     предмет тут саме «токен оголошено», і повідомлення про помилку веде в
#     `@theme`. ⚠️ Раніше тут стояло інше обґрунтування — «білд у `.gitignore`,
#     тож у CI його може не бути» — і воно ВИМІРЯНО хибне: обидві спек-джоби
#     ходять через `setup-rails-test`, яка робить `tailwindcss:build`. Ця хибна
#     посилка коштувала дорого: вона ж відмовляла в білд-якорі третій вісі нижче,
#     і без якоря дзеркальний гейт сім місяців стеріг мертвий namespace.
#   · Скан покриває `app/views/**/*.rb`. Класи, зібрані з інтерполяції, з
#     констант або з БД, тут невидимі за побудовою.
#   · `@layer`-класи (`gaia-responsive-table`, `gaia-sticky-thead`) під регекс не
#     підпадають — вони не несуть utility-префікса, і це навмисно.
module DesignTokenGate
  CSS_PATH   = Rails.root.join("app/assets/tailwind/application.css")
  BUILD_PATH = Rails.root.join("app/assets/builds/tailwind.css")

  # Утиліти, що приймають колірний токен. Список явний, а не «будь-яке слово
  # перед дефісом»: інакше гейт ловив би `gap-`, `p-`, `w-` і ставав шумом,
  # а шумний advisory — це вимкнений гейт (`ssot-maintenance` §Guard-craft).
  COLOUR_UTILITIES = %w[
    text bg border ring divide outline fill stroke accent caret
    from via to shadow decoration placeholder
  ].freeze

  # `/20` — Tailwind-суфікс прозорості; він НЕ частина імені токена, і зрізати
  # його обов'язково, інакше `bg-token-forest/20` читався б як окремий токен.
  TOKEN_RE = /
    (?<![-\w])
    (?:#{COLOUR_UTILITIES.join('|')})-
    ((?:gaia|status|token)-[a-z0-9-]+?)
    (?:\/\d{1,3})?
    (?![\w-])
  /x

  module_function

  def theme_block
    File.read(CSS_PATH)[/@theme\s*\{(.*?)^\}/m, 1]
  end

  def declared
    theme_block.to_s.scan(/--color-([a-z0-9-]+)\s*:/).flatten.to_set
  end

  def used
    Dir.glob(Rails.root.join("app/views/**/*.rb")).each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, acc|
      rel = Pathname(file).relative_path_from(Rails.root).to_s
      File.readlines(file).each_with_index do |line, idx|
        line.scan(TOKEN_RE).flatten.each { |token| acc[token] << "#{rel}:#{idx + 1}" }
      end
    end
  end

  # Імена font-size токенів з `@theme`. Компаньйони `--text-X--line-height`
  # відкидаються: вони НЕ окремі позиції шкали, а їхнє ім'я містить `--`
  # всередині — саме за цим і фільтруємо, бо `[a-z0-9-]+` ковтає їх мовчки.
  #
  # 🔴 Префікс `--text-` тут НЕ косметика і НЕ вибір стилю: це namespace, з якого
  # Tailwind v4 генерує `text-<name>`. Доти регекс шукав `--font-size-*` — форму
  # беток v4, перейменовану до релізу, — і збігався з `@theme`, який ту саму
  # мертву форму й оголошував. Гейт був зелений сім місяців, бо звіряв дві НАШІ
  # сторони між собою; шкала при цьому не існувала в CSS жодного дня.
  def declared_font_sizes
    theme_block.to_s.scan(/--text-([a-z0-9-]+)\s*:/).flatten.reject { |n| n.include?("--") }.to_set
  end

  # Позиції шкали, реально вжиті в Phlex-дереві. Лукбігайнд пропускає варіантний
  # префікс (`md:text-display-sm`), бо `:` не входить у `[-\w]`.
  def used_text_sizes
    tree = Dir.glob(Rails.root.join("app/views/**/*.rb")).map { |f| File.read(f) }.join("\n")
    ApplicationComponent::CUSTOM_TEXT_SCALE.select do |name|
      tree.match?(/(?<![-\w])text-#{Regexp.escape(name)}(?![\w-])/)
    end.to_set
  end

  # Tailwind емітить `@theme`-змінну в `:root` РІВНО тоді, коли з неї щось
  # згенеровано; невживану — вирізає. Тому присутність `--text-<name>:` у білді
  # є прямим свідченням «утиліта існує», без розбору екранованих імен класів
  # (`.md\:text-display-sm`).
  def built_css
    BUILD_PATH.exist? ? BUILD_PATH.read : nil
  end
end

# rubocop:disable RSpec/MultipleDescribes -- три групи в одному файлі свідомо:
# всі перевикористовують `DesignTokenGate`, тож окремі файли означали б ДРУГИЙ і
# ТРЕТІЙ парсер того самого `@theme` — рівно та дуплікація, яку ці гейти й
# ловлять. Вкладати їх одна в одну теж не можна: контракти різні (існування
# токена ⊥ рівність множин ⊥ досяжність утиліти в білді), і спільний `describe`
# брехав би про предмет.
RSpec.describe "design tokens: every used token exists in @theme" do # rubocop:disable RSpec/DescribeClass
  let(:declared) { DesignTokenGate.declared }
  let(:used) { DesignTokenGate.used }

  # Ліхтар на власний вимір: гейт над порожньою множиною зелений назавжди, і
  # відрізнити «нічого не порушено» від «екстрактор осліп» можна лише так.
  it "extracts a non-trivial population from both sides" do
    expect(DesignTokenGate.theme_block).to be_present, "@theme block not found — the extractor is blind"
    expect(declared.size).to be >= 25
    expect(used.size).to be >= 25
  end

  it "declares every colour token the Phlex tree uses" do
    missing = used.reject { |token, _| declared.include?(token) }

    report = missing.map { |token, sites| "  #{token} — #{sites.size} site(s), e.g. #{sites.first}" }

    expect(missing).to be_empty, <<~MSG
      Phlex components use colour tokens that `@theme` never declares.
      Tailwind silently emits NO class for these, so the colour falls back to
      whatever the element inherits — the markup lies and the CSS stays quiet.

      Fix: declare `--color-<token>` in the `@theme` block of
      #{DesignTokenGate::CSS_PATH.relative_path_from(Rails.root)} (and give it a value in BOTH
      `:root` and the `prefers-color-scheme: dark` block), or drop the class from
      the component.

      #{report.join("\n")}
    MSG
  end
end

# 🔴 Друга вісь того ж крос-шарового контракту: `CUSTOM_TEXT_SCALE` мусить бути
# РІВНА множині `--text-*` з `@theme` — і саме рівна, не «включати».
#
# Механізм, і він мовчазний в обидва боки. TailwindMerge розрізняє `text-<size>`
# і `text-<color>` ЛИШЕ за цим списком: токен, доданий у CSS і забутий у
# константі, робить `text-hero` КОЛІРНИМ класом, тож він конфліктує з
# `text-gaia-primary-text` і один із двох тихо зникає при мержі. Дзеркально —
# ім'я, лишене в константі після видалення з CSS, вчить merger'а шкалі, якої
# нема, і глушить справжній колірний клас із тим самим суфіксом.
#
# 🔒 Чому воно живе ТУТ, а не окремим файлом: `@theme` уже розібраний вище
# (`DesignTokenGate.theme_block`), тож це +1 приклад, а не другий парсер.
# ⚠️ Це прямо СПРОСТОВУЄ обґрунтування, що доти стояло в `04_04` («Tailwind v4
# не експортує @theme у Ruby-сумісному форматі, парсинг CSS фрагільний, тому
# тримаємо дві точки істини під code review»): парсер існує в цій же сюїті з
# моменту, коли гейт існування токенів було написано. Обґрунтування виправлено
# разом із цим прикладом.
#
# 🔒 Чесна стеля, і вона виявилась вужчою, ніж читалась: гейт судить ІМЕНА, ніколи
# ЗНАЧЕННЯ (`--text-tiny: 40rem` пройде — придатність розміру не є множинним
# питанням). 🔴 Але дірка була не у значенні, а в тому, що обидві звірювані сторони
# НАШІ: імена збігались ідеально під префіксом, з якого Tailwind нічого не генерує.
# Дзеркало доводить згоду, не правильність — зовнішній якір тримає третя вісь нижче.
RSpec.describe "CUSTOM_TEXT_SCALE mirrors the @theme font-size scale" do # rubocop:disable RSpec/DescribeClass
  let(:declared) { DesignTokenGate.declared_font_sizes }
  let(:registered) { ApplicationComponent::CUSTOM_TEXT_SCALE.to_set }

  it "extracts a non-trivial scale from the CSS side" do
    expect(declared.size).to be >= 4, "the @theme font-size extractor is blind — it found #{declared.size}"
  end

  it "registers exactly the font-size tokens @theme declares" do
    missing = declared - registered
    extra = registered - declared

    expect(missing | extra).to be_empty, <<~MSG
      `CUSTOM_TEXT_SCALE` and the `@theme` font-size scale have drifted.

      In CSS but NOT registered: #{missing.to_a.sort.inspect}
        → TailwindMerge will treat `text-<name>` as a COLOUR class, so it
          collides with real colour utilities and one of them vanishes silently.

      Registered but NOT in CSS: #{extra.to_a.sort.inspect}
        → the merger is taught a scale that no longer exists, which suppresses
          a genuine colour class sharing that suffix.

      Fix: keep both sides equal — `--text-<name>` in
      #{DesignTokenGate::CSS_PATH.relative_path_from(Rails.root)} (@theme block)
      and `<name>` in ApplicationComponent::CUSTOM_TEXT_SCALE.
    MSG
  end
end

# 🔴 ТРЕТЯ вісь, і єдина з ЗОВНІШНІМ якорем. Дві вище звіряють наші власні доми
# один з одним — а такий гейт за побудовою не бачить випадку, коли обидві сторони
# помиляються ОДНАКОВО. Саме це тут і сталося: `@theme` оголошував `--font-size-*`
# (namespace беток v4, перейменований до релізу на `--text-*`), константа дзеркалила
# ті самі імена, гейт-дзеркало був зелений — і жодна з семи позицій шкали не
# існувала в CSS. 448 ужитків `text-micro|mini|tiny|compact` у Phlex-дереві
# успадковували кореневі 16px; видимим це стало рівно один раз, коли підпис у
# топбарі ліг у два рядки й вигнав шапку за власні межі (`00_07` UI.3).
#
# 🔒 Чому якорем узято БІЛД, попри протилежне рішення в двох сусідніх шапках.
# Там стояло «`app/assets/builds/` у .gitignore, тож у CI його може не бути
# взагалі — гейт по ньому був би зелений на порожній множині». Посилка ВИМІРЯНА і
# хибна: обидві спек-джоби (`ci.yml` `test` і `feature-test`) заходять через
# `./.github/actions/setup-rails-test`, а та дія кроком «Build Tailwind CSS»
# робить `bin/rails tailwindcss:build`. Білд у CI є завжди, коли ці приклади
# біжать. Ризик порожньої множини реальний — його знімає не відмова від якоря, а
# ліхтар нижче: файл мусить бути на місці й містити core-утиліту.
#
# 🔒 Стеля: судиться лише ІСНУВАННЯ утиліти, ніколи її значення чи придатність
# (`--text-tiny: 40rem` пройде). І лише ВЖИТІ позиції — шкала має право
# пропонувати більше, ніж спожито, тож `display-md`/`display-lg` при нулі ужитків
# правомірно невидимі для Tailwind і для цього гейта.
RSpec.describe "the custom text scale actually reaches the built CSS" do # rubocop:disable RSpec/DescribeClass
  let(:css) { DesignTokenGate.built_css }
  let(:used) { DesignTokenGate.used_text_sizes }

  # Ліхтар на ОБИДВА боки виміру: файл існує, він є справжнім виводом Tailwind
  # (несе core-розмір), і шкала справді вживається. Без цього «нуль порушень»
  # означало б «нема чого міряти» — рівно той клас, який гейт і ловить.
  it "reads a real Tailwind build and a non-empty usage set" do
    expect(css).to be_present, <<~MSG
      #{DesignTokenGate::BUILD_PATH.relative_path_from(Rails.root)} is missing — this gate has nothing to
      anchor on. Run `bin/rails tailwindcss:build` (~50ms); CI does it in
      .github/actions/setup-rails-test.
    MSG
    expect(css).to include("--text-sm:"), "the build carries no core font-size — it is not a Tailwind output"
    expect(used.size).to be >= 4
  end

  it "generates every scale position the Phlex tree uses" do
    dead = used.reject { |name| css.to_s.include?("--text-#{name}:") }

    expect(dead).to be_empty, <<~MSG
      These scale positions are used in `app/views/**` but Tailwind generated
      NOTHING for them, so every site inherits whatever font-size is above it.

      Dead: #{dead.sort.inspect}

      Tailwind v4 takes font sizes from the `--text-*` namespace. A declaration
      under any other prefix is emitted as a plain custom property and produces
      no utility — silently. Check the `@theme` block in
      #{DesignTokenGate::CSS_PATH.relative_path_from(Rails.root)}.
    MSG
  end
end
# rubocop:enable RSpec/MultipleDescribes
