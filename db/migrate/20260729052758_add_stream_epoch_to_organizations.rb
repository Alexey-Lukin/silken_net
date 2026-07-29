# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.25 Ф3] Покоління імен Turbo-стрімів організації.
#
# Підписане ім'я стріму — детермінований HMAC без TTL, а ActionCable підписку не
# ре-авторизує. Тобто рядок, який сторінка колись відрендерила, лишався ключем
# назавжди. Епоха робить відкликання можливим: bump міняє АДРЕСУ, тож збережений
# токен указує в порожнечу — і для цього не треба ані гейтити підписника (клас
# каналу обирає клієнт), ані гасити його `reject`'ом (той тихий і незворотний).
#
# `default: 1`, а не 0 — щоб ім'я читалось як `..._org_7_e1`, тобто «перша епоха».
# `null: false` несуче: nil дав би `_e` без числа, тобто ОДНЕ ім'я на всі епохи —
# рівно той спільний канал, від якого вся ця вісь і рятує.
class AddStreamEpochToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :stream_epoch, :integer, default: 1, null: false
  end
end
