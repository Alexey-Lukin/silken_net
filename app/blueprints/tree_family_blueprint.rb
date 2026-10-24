# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# 🌲 TREE FAMILY — КОНТРАКТ ВІДПОВІДІ [SEC.36, ⚖️ founder 2026-10-24]
# =============================================================================
# До цього блупринта `tree_families` віддавав СИРУ модель у чотирьох JSON-гілках
# (`index` · `show` · `create` · `update`), а з нею — весь JSONB `biological_properties`,
# де лежать і ключі, які жодна сторінка не друкує: модель прямо каже, що історичні
# ключі в блобі лишаються. Реєстр колонок до вмісту JSONB сліпий за побудовою
# (скіл `backend` #80), тож блоб і є механізмом, яким зайве їде назовні непоміченим.
#
# ⚖️ Стеля — те, що ВЖЕ друкує HTML (прецедент `AiInsightBlueprint`, ⚖️ 2026-09-07):
# `TreeFamilies::Index` — `name` · `scientific_name` · `trees_count`; `TreeFamilies::Show` —
# `name` · `scientific_name` · `carbon_sequestration_coefficient` · `bark_thickness` ·
# `foliage_density` · `fire_resistance_rating`. Мутації редиректять на сторінку показу,
# тож їхній JSON — вигляд `:show`.
#
# ⛔ Ключі блоба — лише ОГОЛОШЕНІ аксесори моделі, ніколи весь `biological_properties`.
# =============================================================================
class TreeFamilyBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :scientific_name

  view :index do
    fields :trees_count
  end

  view :show do
    fields :carbon_sequestration_coefficient, :bark_thickness, :foliage_density, :fire_resistance_rating
  end
end
