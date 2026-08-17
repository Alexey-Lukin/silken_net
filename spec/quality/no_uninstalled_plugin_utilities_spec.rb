# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [UI.3] Утиліта з плагіна, якого ми не ставили, не сміє стояти в розмітці —
# і це не гігієна, а єдиний спосіб побачити цілий КЛАС мовчазних дефектів.
#
# Механізм: Tailwind v4 на невідомий клас **не лається** — він просто не генерує
# для нього нічого. Тож розмітка виглядає написаною, CSS мовчить, елемент
# успадковує чуже оформлення, і жоден рантайм не має де впасти. Клас має
# shipping-record у цьому дереві тричі: фантомний `--gaia-primary-text` на девʼяти
# сайтах (кнопки виходили 1.98:1 у темній темі), `.prose` при невстановленому
# `@tailwindcss/typography` (посилання всередині markdown втрачали БУДЬ-ЯКУ
# відмітність — WCAG 1.4.1 у найгіршій формі), і вся entrance-анімація дерева:
# **94 входження `animate-in`/`fade-in`/`zoom-in`/`slide-in-from-*` у 47 файлах при
# нулі в білді**, знято 2026-08-15.
#
# 🔴 НАЙДОРОЖЧЕ — не сама розмітка, а те, що сюїта її ЗАСВІДЧУВАЛА. Сім прикладів
# звалися «renders with fade-in animation» і пінили `include("animate-in")`, тобто
# стверджували наявність РЯДКА, а не існування утиліти — і були зелені весь час,
# поки анімації не існувало жодного дня. Це та сама форма, якою фантомний токен
# прожив стільки ж: пін на текст класу не є заявою про його ефект.
#
# 🔒 ЧОМУ ДЕРИВАЦІЯ, А НЕ РЕЄСТР. Перелік «заборонених» класів гнив би однобічно:
# поставив плагін — а гейт і далі забороняє. Тому джерелом правди взято те саме
# місце, де Tailwind v4 плагіни ОГОЛОШУЄ — директиву `@plugin` у самому CSS. Немає
# оголошення — класи діалекту заборонені; зʼявиться — гейт замовкне сам, без правки
# цього файла (`ssot-maintenance` §Guard-craft #53: реєстр винятків, чию умову ніхто
# не перевіряє, переживає власну підставу).
#
# ⚠️ ЧОМУ НЕ ЗВІРЯЄМО З БІЛДОМ: предмет тут — «клас діалекту СТОЇТЬ у розмітці», і
# судити його треба там, де він стоїть; повідомлення про помилку веде у файл і рядок,
# чого білд дати не може. 🔴 **Доти тут стояло інше обґрунтування — «`app/assets/builds/`
# у `.gitignore`, тож у CI його може не бути взагалі» — і воно ВИМІРЯНО хибне** (2026-08-17):
# обидві спек-джоби заходять через `./.github/actions/setup-rails-test`, крок «Build
# Tailwind CSS» = `bin/rails tailwindcss:build`. Ризик порожньої множини реальний, але
# знімає його ЛІХТАР, а не відмова від якоря — і саме ця відмова, повторена в чотирьох
# домах, лишила шкалу типографіки без зовнішнього свідка на сім місяців
# (§Guard-craft #67/#68; жива вісь із білд-якорем тепер у `design_token_existence_spec`).
#
# ⚠️ Чесна стеля, три пункти. (1) Гейт знає рівно ті діалекти, які перелічені нижче:
# новий плагін невидимий, доки хтось не додасть рядок — але додати його дешево, а
# мовчання тут не імітує здоровʼя, бо кожен доданий діалект одразу міряється по
# всьому дереву. (2) Судиться ДЖЕРЕЛО, не DOM: клас, зібраний інтерполяцією, пройде.
# (3) Іконкові ШРИФТИ (`ph ph-*` Phosphor) сюди свідомо НЕ входять — це інше
# твердження («шрифт підключено»), і за §Guard-craft #46 воно потребує власного
# гейта, а не «and» у цьому. Живі сайти того класу → `00_07` UI.3.
module UninstalledPluginUtilitiesGate
  VIEWS_GLOB = Rails.root.join("app/views/**/*.rb")
  CSS_PATH   = Rails.root.join("app/assets/tailwind/application.css")

  # Плагін → сигнатурні утиліти, які існують ЛИШЕ завдяки йому.
  # Ключ мусить збігатися з тим, що писали б у `@plugin "…"`.
  DIALECTS = {
    "tailwindcss-animate" => /\b(?:animate-(?:in|out)|fade-(?:in|out)|zoom-(?:in|out)(?:-\d+)?|slide-(?:in-from|out-to)-[a-z]+(?:-\d+)?)\b/,
    "@tailwindcss/typography" => /\bprose(?:-[a-z0-9]+)?\b/
  }.freeze

  # Проза про клас легальна й потрібна — коментарі пояснюють, ЧОМУ його зняли.
  # Гейт, що червоніє на власній документації, знімають першим (прецедент —
  # `no_turbo_permanent_spec`). Межа саме «рядок-коментар», ніколи «все після `#`»:
  # у Ruby `#` живе й усередині `"#{…}"`, тож ширше обрізання ховало б розмітку.
  def self.installed_plugins
    CSS_PATH.read.scan(/^\s*@plugin\s+["']([^"']+)["']/).flatten.to_set
  end

  def self.violations
    installed = installed_plugins
    Dir[VIEWS_GLOB].sort.flat_map do |path|
      rel = Pathname.new(path).relative_path_from(Rails.root)
      File.readlines(path).each_with_index.flat_map do |line, idx|
        next [] if line =~ /\A\s*#/

        DIALECTS.filter_map do |plugin, pattern|
          next if installed.include?(plugin)
          hit = line[pattern]
          next unless hit

          "#{rel}:#{idx + 1}: `#{hit}` — діалект `#{plugin}`, який не оголошено через @plugin"
        end
      end
    end
  end
end

RSpec.describe "утиліти невстановлених Tailwind-плагінів", type: :model do
  it "не стоять у розмітці — нуль винятків" do
    expect(UninstalledPluginUtilitiesGate.violations).to be_empty
  end

  # Liveness обох множин: без цього «нуль порушень» означало б і «нуль перевірок»
  # — рівно те, чим сім знятих прикладів були сім місяців.
  it "справді сканує дерево і справді знає діалекти" do
    # Підлога ловить ЗЛАМАНИЙ glob, а не є переписом (дерево на день написання —
    # 93 файли; число тут було б volatile-лічильником, а порожня множина —
    # вічнозеленою декорацією).
    expect(Dir[UninstalledPluginUtilitiesGate::VIEWS_GLOB].size).to be > 50
    expect(UninstalledPluginUtilitiesGate::DIALECTS).not_to be_empty
  end

  # 🔴 Половина, без якої гейт неможливо зняти чесно: він мусить ЗАМОВКНУТИ, щойно
  # плагін оголошено. Інакше перший, хто поставить плагін, дістане червоне на
  # правильному коді — а найдешевша відповідь на такий гейт це його видалити.
  it "замовкає на діалекті, чий плагін ОГОЛОШЕНО" do
    allow(UninstalledPluginUtilitiesGate).to receive(:installed_plugins)
      .and_return(UninstalledPluginUtilitiesGate::DIALECTS.keys.to_set)

    expect(UninstalledPluginUtilitiesGate.violations).to be_empty
  end
end
