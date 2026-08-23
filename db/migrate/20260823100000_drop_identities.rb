# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.69, присуд founder 2026-08-23] OAuth знято як спосіб входу: вимір
# показав, що Google не додає жодної властивості до наявного стека (Argon2id +
# TOTP + salt-stamp ревокація), а платить за нього повна ціна — третій незалежний
# контролер у Privacy Policy, реєстрація застосунку в чужій консолі й ручний
# DSAR-шлях для акаунта без пароля. Реєстрація, коли з'явиться її споживач,
# піде поштою: `email_verification` токен для неї вже оголошено на `User`.
#
# Разом із таблицею зникає весь клас passwordless-акаунта — тому `password_digest`
# стає безумовним, а гілки «власник без спільного секрета» більше не мають чим
# народитись.
class DropIdentities < ActiveRecord::Migration[8.1]
  def change
    # safety_assured: жодного читача не лишається (модель, екшени, маршрути й UI
    # знято тим самим комітом), прод-даних не існує — OmniAuth не був задротований
    # жодного дня, тож рядок у цій таблиці не міг з'явитися за побудовою.
    safety_assured do
      drop_table :identities do |t|
        t.references :user, null: false, foreign_key: true
        t.string :provider
        t.string :uid
        t.string :access_token
        t.string :refresh_token
        t.text :auth_data
        t.datetime :expires_at
        t.datetime :locked_at
        t.boolean :primary, default: false, null: false
        t.timestamps
      end
    end
  end
end
