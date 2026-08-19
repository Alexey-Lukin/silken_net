# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [I18N.1] `resolution_notes` (text, append прози через `join("\n")`) →
# `resolution_log` (jsonb-МАСИВ записів `{key:, params:, at:}` | `{text:, at:}`).
#
# Пара «ключ+параметри» цю колонку виразити не могла саме через накопичення —
# тож фраза збиралась у локалі процесу-ПИСАЧА і мовами впереміш (укр. проза
# sweep-воркерів ⊥ англ. проза dclimate) лягала в БД. Тепер у БД лежать ключі
# (рендер — локаллю глядача в момент показу, `EwsAlert#resolution_texts`, той
# самий контракт, що `message_key`), а вільний текст ЛЮДИНИ-резолвера — окремий
# рід запису (`"text"`), який не локалізується жодною схемою.
#
# Час запису — поле `at` самого запису, тож `[iso8601]`-префікси, які писачі
# клеїли в прозу руками, зникають як клас.
#
# ⚠️ Data-міграції НЕМАЄ свідомо: продакшну не існує, `ews_alerts` порожня,
# сіди перегенеровуються (той самий прецедент, що `DropEmittedTokensDefault`).
class ReplaceEwsResolutionNotesWithLog < ActiveRecord::Migration[8.1]
  def change
    add_column :ews_alerts, :resolution_log, :jsonb, null: false, default: []
    safety_assured { remove_column :ews_alerts, :resolution_notes, :text }
  end
end
