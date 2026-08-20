# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.78, присуд founder 2026-08-20] SMS-канал відкинуто (email покриває той
# самий сценарій, Telegram — другий живий канал). Телефон збирався РІВНО під
# SMS-доставку, тож без каналу це PII без цілі processing (Art. 5(1)(c)) —
# той самий клас «поле без каналу», що RoPA-знахідка про telegram_chat_id,
# лише зі зворотним присудом: там канал збудували, тут поле знімається.
class DropUsersPhoneNumber < ActiveRecord::Migration[8.1]
  def change
    # safety_assured: жодного читача колонки в коді (канал знято тим самим
    # комітом), прод-даних не існує (pre-launch).
    safety_assured { remove_column :users, :phone_number, :string }
  end
end
