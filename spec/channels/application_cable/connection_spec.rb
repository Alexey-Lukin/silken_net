# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт ідентичності WebSocket-зʼєднання (`00_07` SEC.25 Ф1, канон `04_04 §8.1`).
#
# 🔒 Що цей файл НЕ доводить — назване тут, бо зелений прогін інакше читається
# ширше, ніж він є:
#   · він не перевіряє авторизацію ПІДПИСКИ (її свідомо не будували — клас
#     каналу вибирає клієнт, тож власний канал обходиться атрибутом);
#   · він не розрізняє рядкові й символьні ключі сесії. Продакшн-cookie
#     серіалізується `:json` і дає рядкові, але `TestCookies` успадковує
#     `HashWithIndifferentAccess`, тож у харнесі обидві форми читаються
#     однаково. Рядковий доступ у коді тримається на вимірі серіалізатора,
#     не на цьому прикладі.
RSpec.describe ApplicationCable::Connection do
  # Два субʼєкти навмисно. Те, що тут перевіряється, — це ВИБІР користувача за
  # вмістом cookie, а односубʼєктна фікстура не відрізняє «того, кого просили»
  # від «першого в таблиці»: мутація `find_by(id:)` → `User.first` лишилась би
  # зеленою. З двома вона червоніє.
  let!(:other_user) { create(:user) }
  let!(:user) { create(:user) }

  # `TestCookies#[]=` бере `options.symbolize_keys[:value]`, коли їй дають Hash,
  # тож сесію треба класти саме обгорнутою — інакше вона мовчки стає `nil`, і
  # кожен приклад «доводив» би відмову з порожнього cookie.
  def stamp_session(user_id: user.id, ps: user.password_salt.to_s.last(10), session_id: "sid-laptop")
    cookies.encrypted[Rails.application.config.session_options[:key]] = {
      value: { "user_id" => user_id, "ps" => ps, "session_id" => session_id }
    }
  end

  describe "#connect" do
    it "identifies the user carried by the session cookie" do
      stamp_session

      connect

      expect(connection.current_user).to eq(user)
    end

    it "carries the session id, so revocation can target ONE device" do
      stamp_session(session_id: "sid-phone")

      connect

      expect(connection.session_id).to eq("sid-phone")
    end

    # Це і є причина, чому `identified_by` несе ДВА ідентифікатори: без
    # `session_id` відкликання било б по всіх сесіях акаунта одразу.
    it "builds a connection identifier that distinguishes two devices of one user" do
      stamp_session(session_id: "sid-laptop")
      connect
      laptop = connection.connection_identifier

      stamp_session(session_id: "sid-phone")
      connect

      expect(connection.connection_identifier).not_to eq(laptop)
    end

    it "rejects a connection with no session cookie at all" do
      expect { connect }.to have_rejected_connection
    end

    it "rejects a session whose salt stamp is stale [SEC.16]" do
      stamp_session(ps: "outdated00")

      expect { connect }.to have_rejected_connection
    end

    it "rejects a session pointing at a user that no longer exists" do
      stamp_session(user_id: user.id)
      user.destroy!

      expect { connect }.to have_rejected_connection
    end

    # ⚠️ Пінить рівно те, що каже назва: у користувача З паролем порожній стемп
    # не проходить. НЕ доводить ширшого — для користувача БЕЗ пароля
    # `password_salt` дорівнює `nil`, обидва боки згортаються в `""`, і
    # порівняння стає істинним (виміряно). Форма fail-open, дзеркально та сама в
    # `base_controller`; сьогодні недосяжна (щоб мати `session["user_id"]`, треба
    # пройти логін паролем), тому поведінку тут свідомо НЕ розводимо з дзеркалом
    # — розходження двох перевірок коштувало б дорожче. Стан → `00_07` SEC.16.
    it "rejects a session with a blank salt stamp" do
      stamp_session(ps: "")

      expect { connect }.to have_rejected_connection
    end
  end
end
