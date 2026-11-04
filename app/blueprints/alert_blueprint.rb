# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# 🚨 EWS-ALERT — КОНТРАКТ ВІДПОВІДІ [SEC.36, ⚖️ founder 2026-11-04]
# =============================================================================
# 🔴 П'ять JSON-гілок `alerts_controller` (`index` · `show` · `resolve` · `claim` ·
# `release`) віддавали СИРИЙ `EwsAlert` — кожну колонку таблиці, з обома JSONB
# блобом: `resolution_log` (несе вільні нотатки оператора з `resolve!`) і
# `message_params`. Свіп форми `render json: @x` (2026-09-07) їх не бачив: тут
# форма — `as_json(include:)` усередині хеша і `alert: @alert` ключем.
#
# ⚖️ Стеля — те, що вже бачить ТОЙ САМИЙ глядач на будь-якій своїй сторінці
# (скіл `backend` #58a): контракт, задокументований у `04_03 §5.12`, ⊕ те, що
# друкують `Alerts::Row`/`Alerts::Show` — тип, відрендерене повідомлення,
# призначення (без нього відповідь `claim`/`release` нічого не каже про дію) — і
# `resolved_at`, який той самий глядач бачить у хроніці дерева.
# ⛔ JSONB — лише ОГОЛОШЕНИМ ключем: `message` є рендером `message_key` +
# `message_params` (рівно тим, що читає вʼю), а `resolution_log` не віддається.
# ⚠️ Тип координат залежить від гілки (`EwsAlert#coordinates`): у дерева — `numeric`,
# тобто в JSON РЯДКИ; центр кластера (тривога без дерева) — Float із полігона, тобто
# ЧИСЛА; без полігона — `null` (`04_03 §5.12`).
# =============================================================================
class AlertBlueprint < Blueprinter::Base
  identifier :id

  fields :status, :severity, :alert_type, :created_at, :resolved_at, :assigned_to_id, :assigned_at

  field(:message) { |alert| alert.message }
  field(:coordinates) { |alert| alert.coordinates }
  field(:actionable?) { |alert| alert.actionable? }
  field(:cluster) { |alert| alert.cluster && { id: alert.cluster.id, name: alert.cluster.name } }
  field(:tree) do |alert|
    tree = alert.tree
    tree && { id: tree.id, did: tree.did, latitude: tree.latitude, longitude: tree.longitude }
  end
end
