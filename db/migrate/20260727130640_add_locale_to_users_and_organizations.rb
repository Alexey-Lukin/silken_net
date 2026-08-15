# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [I18N.1] Дім persisted мовної вподоби.
#
# У запиті локаль дає `LocaleSettable`, але його браузерні джерела не переживають
# перехід у Sidekiq — а саме там живе доставка пошти (`deliver_later`). Без
# persisted-колонки `I18n.with_locale` на межі доставки був би no-op: локаль
# просто нізвідки взяти.
#
# ⚠️ [I18N.3, 2026-08-15] Рядок вище доти казав «для НЕ-веб-контекстів» — і це
# перестало бути правдою: `users.locale` тепер ТРЕТІЙ щабель самого резолву
# ([`04_04 §12.4`](../../docs/04_04_Phlex_UI_and_Tailwind.md)), тобто джерело для
# ОБОХ контурів. Точний перелік щаблів тут свідомо не наводиться — міграція
# фіксує момент народження колонки, а не чинний ланцюг.
#
# ДВІ колонки, бо адресати різні, і це не дублювання:
#   · `users.locale`         — PasswordMailer шле конкретному User;
#   · `organizations.locale` — AlertMailer шле на `organizations.billing_email`,
#     тобто на скриньку, за якою може не стояти жоден User-запис.
#
# NULL — це не «англійська», а «не обрано»: тоді доставка чесно падає на
# `I18n.default_locale`. Дефолт на рівні БД брехав би, що користувач зробив
# вибір, і назавжди сховав би різницю між «обрав en» і «ми не знаємо».
class AddLocaleToUsersAndOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :locale, :string
    add_column :organizations, :locale, :string
  end
end
