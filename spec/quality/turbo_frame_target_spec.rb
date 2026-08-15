# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ЦІЛІ фрейма: кожен `data: { turbo_frame: X }` мусить мати в тому ж файлі
# `turbo_frame_tag(X)` з ТИМ САМИМ виразом (`04_04 §8`, `00_07` UI.11).
#
# Чому саме така форма. Turbo кладе відповідь у елемент `<turbo-frame>` із названим
# id; якщо там стоїть звичайний `<div>` із таким же id — фрейм не знаходиться, Turbo
# пише помилку в консоль і **не робить нічого**. Дефект тихий двічі: сабміт іде,
# сервер відпрацьовує, екран не змінюється — і жодна спека цього не бачить, бо
# компонентна не виконує Turbo, а request-спека дивиться на статус.
#
# ⚠️ Зарезервовані імена Turbo (`_top`, `_self`) — НЕ цілі: `_top` означає «вийди з
# фрейма й навігуй сторінку цілком», тобто елемента з таким id не існує ніколи.
# Без цього винятку гейт червонив би на КОРЕКТНОМУ коді (перевірено мутацією), а
# найдешевша відповідь на надто широкий гейт — послабити його, тож це не дрібниця.
#
# ⚠️ Стеля названа: гейт звіряє ТЕКСТ виразу, не резолвить його. Тобто
# `data: { turbo_frame: frame_id }` вимагає `turbo_frame_tag(frame_id)` у тому ж
# файлі — і це навмисне звуження: обидва здорові сайти дерева саме такі, а
# резолвити метод статично означало б другий інтерпретатор, якого ніхто не звіряє.
# Ціль, оголошена в ІНШОМУ файлі, тут не проходить — і це теж свідомо: фрейм, чия
# ціль живе деінде, вже двічі виявлявся мертвим трактом (`04_04 §8.1`).
RSpec.describe "ціль data-turbo-frame існує як turbo-frame", type: :model do
  # Зарезервовані Turbo-імена: не посилання на елемент, а директива навігації.
  def reserved_targets = %w[_top _self]

  # ⚠️ РЕЄСТР ПОРОЖНІЙ, І ЦЕ МЕТА, А НЕ ЗАБУТИЙ РЯДОК. Єдиний виняток, що тут
  # стояв, — `OracleVisions::SimulationPanel`, чия форма цілилась у `<div>`
  # замість фрейма; ⚖️ founder 2026-08-15 зняв панель РАЗОМ із дією `#simulate`,
  # бо фічі не існувало на жодному ярусі ([UI.7]). Отже живих порушників нуль.
  # Механізм лишається — наступний чесний виняток матиме куди сісти.
  def declared_exceptions = {}

  # Витягує з файлу дві множини: на що ЦІЛЯТЬСЯ і що ОГОЛОШЕНО фреймом.
  def frame_usage(source)
    targets = source.scan(/turbo_frame:\s*("[^"]*"|'[^']*'|[a-z_][\w.]*)/).flatten
    declared = source.scan(/turbo_frame_tag\(\s*("[^"]*"|'[^']*'|[a-z_][\w.]*)/).flatten
    [ targets, declared ]
  end

  def violations
    Dir.glob(Rails.root.join("app/views/**/*.rb")).flat_map do |path|
      rel = path.sub("#{Rails.root}/", "")
      targets, declared = frame_usage(File.read(path))

      targets.uniq.filter_map do |target|
        next if declared.include?(target)

        bare = target.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
        next if reserved_targets.include?(bare)
        next if declared_exceptions[rel]&.fetch(:target) == bare

        "#{rel} → ціль #{target} без `turbo_frame_tag(#{target})` у тому ж файлі"
      end
    end
  end

  it "тримає перелік цілей і оголошень непорожнім (liveness)" do
    # Без цього прикладу зламаний регекс зробив би головний гейт вакуумним:
    # «нуль порушень» означало б «нуль перевірених сайтів».
    gallery = File.read(Rails.root.join("app/views/components/maintenance/photo_gallery.rb"))
    targets, declared = frame_usage(gallery)

    expect(targets).to include("frame_id")
    expect(declared).to include("frame_id")
  end

  it "не має цілі без відповідного turbo_frame_tag" do
    expect(violations).to be_empty, <<~MSG
      `data-turbo-frame` вказує на елемент, який фреймом не оголошений — Turbo не
      знайде ціль, напише помилку в консоль і НЕ ЗРОБИТЬ НІЧОГО (сабміт при цьому
      відпрацює на сервері, тож дефект тихий):

      #{violations.join("\n      ")}

      Лік: оголосити ціль через `turbo_frame_tag(...)` у тому ж файлі — або,
      якщо доля елемента вирішується деінде, додати рядок у DECLARED_EXCEPTIONS
      із полями `why` (підстава) і `back` (подія, після якої виняток зникає).
    MSG
  end

  it "звільняє ЗАРЕЗЕРВОВАНІ імена Turbo, і рівно їх" do
    # Пін на сам перелік: без нього хтось спорожнить його «бо порожньо-ж-і-так»,
    # і гейт почне червоніти на коректному `_top`. Перевірено мутацією: `_top`
    # проходить, а схоже-але-чуже `_topmost` — ні (збіг ТОЧНИЙ, не префіксний).
    expect(reserved_targets).to contain_exactly("_top", "_self")
  end

  # 🔴 ІМʼЯ НАЗИВАЄ ВАКУУМ СВІДОМО. Реєстр порожній (див. ⚠️ вище), тож цикл нижче
  # СЬОГОДНІ не має підмета — і приклад із назвою «кожен виняток несе підставу»
  # читався б як виконана перевірка, якою він не є. Це рівно та форма, від якої
  # застерігає §Guard-craft: гейт, чий приклад нічого не перебирає, доповідає
  # зелене про порожнечу. Механізм лишаємо (він оживе з першим рядком реєстру),
  # але вакуум оголошуємо в ІМЕНІ, а не ховаємо в тілі.
  it "оголошений виняток (якщо зʼявиться) несе підставу І умову відкликання — реєстр наразі порожній" do
    declared_exceptions.each_value do |row|
      expect(row[:why]).to be_present
      expect(row[:back]).to be_present
    end
  end
end
