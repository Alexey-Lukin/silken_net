# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 ПЕРИМЕТР `code_tracker_id_check` — вісь, окрема від його ФОРМИ (розкол діапазону
# живе в сусідньому файлі), і саме вона потребує ліхтаря, бо розширення периметра
# ВИГРАЄ порожньою множиною.
#
# `deploy` / `terraform` / `subgraph` додано 2026-08-27 (DOC-T.92 · OPS.36) з виміряним
# уловом НУЛЬ: усі три несуть трекер-ID у прозі, яку людина читає о 3-й ночі — Grafana
# `description:` роутить чергового до пункту за ID, — і жоден із них не наглядався нічим.
# Але нуль знахідок означає, що ЖОДНА знахідка ніколи не доведе, що ці дерева справді
# скануються: декоративне розширення й робоче виглядають із CI однаково — зеленими.
# Тому доказом живості тут є ПОПУЛЯЦІЯ (§Guard-craft #61), а не вердикт.
#
# 🔒 Спека читає `TREES`/`EXEMPT` із ДЖЕРЕЛА — як сусідня батарея читає регекс, — тож
# вона червоніє і на видаленні дерева, і на винятку, який з'їв би його назад. Власна
# копія зробила б цей файл другим домом периметра, і послаблення в скрипті лишалось би
# тут зеленим.
module TrackerIdPerimeter
  SOURCE    = Rails.root.join("scripts/code_tracker_id_check.rb")
  EXTS_GLOB = "{rb,c,h,sol,py,sh,rake,erb,yml,yaml,md,json}"
  WIDENED   = %w[deploy terraform subgraph].freeze

  def self.trees
    literal = SOURCE.read[/^TREES\s*=\s*%w\[([^\]]*)\]/, 1]
    raise "не знайдено TREES у #{SOURCE}" if literal.nil?

    literal.split
  end

  def self.exempt_re
    literal = SOURCE.read[/^EXEMPT\s*=\s*%r\{(.*)\}\s*$/, 1]
    raise "не знайдено EXEMPT у #{SOURCE}" if literal.nil?

    Regexp.new(literal)
  end

  # Файли дерева, які гейт СПРАВДІ бере: версіоновані (CI бачить лише git-tracked),
  # зі сканованим розширенням, і не відсічені `EXEMPT`.
  #
  # 🔴 Перша редакція глобила теку НАПРЯМУ й тому доводила «у теці є файли», а не «гейт
  # їх бачить»: зняття `deploy` з `TREES` лишало цей вимір зеленим. Мутація це знайшла —
  # класична форма «пара A↔B без питання про ДОСЯЖНІСТЬ» (§Guard-craft #14). Тому
  # членство в `TREES` є ПЕРЕДУМОВОЮ виміру, а не сусіднім прикладом: інакше дві
  # половини одного твердження червоніють нарізно, і кожна виглядає повною.
  def self.scanned_in(tree)
    return [] unless trees.include?(tree)

    tracked = `git -C #{Rails.root} ls-files -z -- #{tree}`.split("\0").to_set
    Dir.glob(Rails.root.join(tree, "**", "*.#{EXTS_GLOB}"))
       .map { |f| f.sub("#{Rails.root}/", "") }
       .reject { |rel| rel.match?(exempt_re) }
       .select { |rel| tracked.include?(rel) }
  end
end

RSpec.describe TrackerIdPerimeter, type: :quality do
  it "тримає дерева, додані для деплой- і аудиторської поверхонь" do
    expect(described_class.trees).to include(*described_class::WIDENED)
  end

  # Найдорожча форма тут — дерево в переліку, що НЕ додає жодного файла: гейт виглядає
  # ширшим, ніж він є, і його нуль читається як покриття.
  TrackerIdPerimeter::WIDENED.each do |tree|
    it "дерево `#{tree}` справді додає версіоновані файли у скан" do
      expect(described_class.scanned_in(tree)).not_to be_empty
    end
  end

  # 🔴 `node_modules` мусить відсікатись КЛАСОМ, на будь-якій глибині: він gitignored,
  # тож поіменний перелік дає гейту сканувати ЛОКАЛЬНО дерево, якого в CI не існує —
  # локальний і CI-прогони мовчки грейдять різні дерева, обидва зелено. Виміряно на
  # заведенні `subgraph`: одна gitignored тека внесла в скан 6873 вендорні файли.
  it "відсікає node_modules як КЛАС, на будь-якій глибині" do
    re = described_class.exempt_re

    expect(re).to match("subgraph/node_modules/foo/bar.json")
    expect(re).to match("contracts/node_modules/x.js")
    expect(re).to match("tools/ml/node_modules/y.md")
    expect(re).not_to match("deploy/akash/deploy.yaml")
  end
end
