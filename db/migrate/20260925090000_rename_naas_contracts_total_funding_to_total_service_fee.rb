# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [BIZ.22 F3] `total_funding` → `total_service_fee` (⚖️ founder 2026-09-25:
# «легше просто перейменувати, юзерів і даних нема»). Канон уже звав колонку
# «загальна сума оплати за послугу» (00_04 §5), а слово «funding» у схемі
# читається due-diligence як інвестиційна механіка — тобто імʼя брехало про
# ПРЕДМЕТ, не лише про лексику. Аліас `total_value` знято тим самим проходом:
# `as_json(only:)` його мовчки ігнорував.
#
# `safety_assured` тут чесний, а не обхід: strong_migrations стереже rolling-
# деплой із живими даними, а pre-launch бази відтворюються сідами (шапка анкера
# `*_init_consolidated.rb`). Після першого живого деплою так перейменовувати
# колонку вже не можна — там потрібна двокрокова форма.
class RenameNaasContractsTotalFundingToTotalServiceFee < ActiveRecord::Migration[8.1]
  def change
    safety_assured { rename_column :naas_contracts, :total_funding, :total_service_fee }
  end
end
