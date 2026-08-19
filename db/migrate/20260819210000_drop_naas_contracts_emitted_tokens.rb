# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.103] Знімає мертву колонку `naas_contracts.emitted_tokens`.
#
# Семантику знято ⚖️-присудом 2026-08-19: величина «емітовано за ЦИМ контрактом»
# не має ВИЗНАЧЕННЯ (кластер несе кілька контрактів одночасно, mint-рядок не має
# посилання на контракт), тож усі поверхні — HTML і JSON — переведено на
# КЛАСТЕРНУ емісію з One-Home `blockchain_transactions`
# (`net_minted_by_cluster` / `for_cluster(...).net_minted_supply`).
#
# Порядок дотримано: спершу JSON дістав кластерну величину й піни (попередній
# коміт), потім різання — тож зникнення поля із зовнішніх відповідей ЯВНЕ
# (запінене `not_to have_key`), а не мовчазне.
#
# ⚠️ `safety_assured` свідомий: StrongMigrations вимагає ignored_columns-фазу для
# zero-downtime деплою, а продакшну не існує і читачів колонки в дереві нуль
# (той самий прецедент, що `DropEmittedTokensDefault`).
class DropNaasContractsEmittedTokens < ActiveRecord::Migration[8.1]
  def up
    safety_assured { remove_column :naas_contracts, :emitted_tokens }
  end

  def down
    # Без DEFAULT: його зняв `DropEmittedTokensDefault` — відкат повертає колонку
    # в останню живу форму (nullable, без дефолту), а не в первісну.
    add_column :naas_contracts, :emitted_tokens, :numeric
  end
end
