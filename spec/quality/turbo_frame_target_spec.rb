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
# ⚠️ Стеля названа: гейт звіряє ТЕКСТ виразу, не резолвить його. Тобто
# `data: { turbo_frame: frame_id }` вимагає `turbo_frame_tag(frame_id)` у тому ж
# файлі — і це навмисне звуження: обидва здорові сайти дерева саме такі, а
# резолвити метод статично означало б другий інтерпретатор, якого ніхто не звіряє.
# Ціль, оголошена в ІНШОМУ файлі, тут не проходить — і це теж свідомо: фрейм, чия
# ціль живе деінде, вже двічі виявлявся мертвим трактом (`04_04 §8.1`).
RSpec.describe "ціль data-turbo-frame існує як turbo-frame", type: :model do
  # ⛔ Оголошений виняток, а не «поки що». Доля самої панелі — відкритий ⚖️ в UI.7
  # (`00_07`): її форма ціляється в `<div id="simulation_results">`, тобто не в
  # фрейм, і клік сьогодні взагалі не доходить туди — `SimulationWorker` у дереві
  # відсутній, тож `perform_async` дає NameError→500 раніше. Конвертувати div у
  # фрейм означало б зацементувати артефакт, який може піти цілком.
  def declared_exceptions
    {
      "app/views/components/oracle_visions/simulation_panel.rb" => {
        target: "simulation_results",
        why:    "ціль існує лише як `<div>` в `oracle_visions/index`; доля панелі — ⚖️ UI.7",
        back:   "присуд UI.7 «будувати чи зняти» — раніше за будь-яку правку цієї цілі"
      }
    }
  end

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

  it "кожен оголошений виняток несе підставу І умову відкликання" do
    declared_exceptions.each_value do |row|
      expect(row[:why]).to be_present
      expect(row[:back]).to be_present
    end
  end
end
