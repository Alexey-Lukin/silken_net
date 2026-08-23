# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.88] Носій ОДНОГО дому точності балових величин.
#
# Доти `balance`/`locked_balance`/`available_balance`/`esg_retired_balance`
# рендерились `.round(6)` · `.round(4)` · `.round(2)` у трьох різних компонентах
# — тобто застосунок відповідав на одне питання трьома числами, залежно від того,
# на який екран зайшов глядач. Дім тепер один: `ApplicationComponent#formatted_points`.
#
# Правило без носія повертається першою ж правкою (`feedback_rule_needs_a_carrier`),
# і саме тут воно поверталось би непомітно: `.round(4)` виглядає як звичайне
# форматування, а не як другий дім.
#
# ⛔ ЗАДЕКЛАРОВАНА СТЕЛЯ (без неї зелений почав би читатись ширше, ніж є):
#   • Периметр — `app/views/**`. JSON-серіалізація (`app/blueprints/**`) свідомо
#     ПОЗА ним: `WalletBlueprint` віддає сиру `numeric(24,6)`, бо API-споживач
#     рахує сам, і зрізати за нього — вирішити за чужий калькулятор.
#   • Гейт бачить лише СИНТАКСИЧНУ форму `<поле>...round(`. Значення, що приїхало
#     в компонент уже округленим із контролера (`dashboard_controller` робить
#     `.round(4)` над агрегатом), для нього не існує — і це не діра, а межа:
#     контролерна половина належить сусідній нозі того самого пункту.
#   • Судить наявність другого дому, ніколи — доречність самої точності.
#
# ✅ МУТАЦІЙНО ПЕРЕВІРЕНО 2026-08-23 — по ОСЯХ, не по гейту (осей три, мутацій дві):
#   • скан: підсаджений `wallet.balance.to_f.round(4)` у компоненті → RED із `файл:рядок`;
#   • константа: `POINTS_PRECISION` 2→3 → RED;
#   • ліхтар популяції мутації НЕ діставав: щоб він упав, треба рухати дерево вʼю.
#     Замість вдаваної перевірки — виміряний запас: 91 файл проти порога 50 (×1,8).
#     Його справжній ризик не в падінні лічби, а в застарілому глобі.
RSpec.describe "Points precision One-Home [ARCH.88]", type: :model do
  def self.point_fields
    %w[balance locked_balance available_balance esg_retired_balance]
  end

  # `wallet.balance.to_f.round(4)` · `@wallet.locked_balance.round(2)` ·
  # `@total_liquidity.to_f.round(2)` — усі форми, виміряні в дереві до зведення.
  def self.rounding_forms
    /(?:#{point_fields.join('|')}|_liquidity)[\w&.]*\.round\(/
  end

  let(:view_files) { Dir[Rails.root.join("app/views/**/*.rb")] }

  it "has a real population to judge (a gate over an empty set is green forever)" do
    expect(view_files.size).to be > 50
  end

  it "declares the precision in exactly one place" do
    expect(ApplicationComponent::POINTS_PRECISION).to eq(2)
    expect(ApplicationComponent.instance_method(:formatted_points)).to be_present
  end

  it "rounds point-bearing values nowhere but that home" do
    offenders = view_files.filter_map do |path|
      hits = File.readlines(path).each_with_index.filter_map do |line, i|
        next if line.lstrip.start_with?("#") # прозу про минуле порушення не рахуємо

        "#{Pathname.new(path).relative_path_from(Rails.root)}:#{i + 1} — #{line.strip}" if line.match?(self.class.rounding_forms)
      end
      hits.presence
    end.flatten

    expect(offenders).to be_empty, <<~MSG
      Точність балових величин має ОДИН дім — `ApplicationComponent#formatted_points`.
      Знайдено власне округлення:
      #{offenders.map { |o| "  • #{o}" }.join("\n")}
    MSG
  end
end
