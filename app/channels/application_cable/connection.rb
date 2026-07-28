# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Ідентичність WebSocket-зʼєднання. До цього файлу її не було взагалі, і саме
# тому штатний примітив відкликання був НЕРОБОЧИЙ, а не «невживаний»:
# `subscribe_to_internal_channel` вимагає `connection_identifier.present?`
# (actioncable `connection/internal_channel.rb`), а без жодного `identified_by`
# набір `identifiers` порожній → ідентифікатор = `""` → канал відкликання не
# підписується, і `remote_connections…disconnect` летить у порожнечу.
#
# 🔒 ЩО ЦЕЙ ФАЙЛ НЕ РОБИТЬ — і це не недоробка, а вимір (`00_07` SEC.25, канон
# `04_04 §8.1`). Він встановлює ОСОБУ, а не право слухати конкретний стрім.
# Авторизацію підписки тут свідомо НЕ будували, бо обидві її половини впали:
#
#   (а) Клас каналу вибирає КЛІЄНТ. `connection/subscriptions.rb` бере
#       `id_options[:channel].safe_constantize` з клієнтського JSON і перевіряє
#       лише спадкування від `ActionCable::Channel::Base`. Підпис Turbo накриває
#       САМЕ ІМʼЯ стріму, не імʼя каналу (`streams_helper.rb`: `channel` —
#       звичайний атрибут, `signed-stream-name` — підписаний). А
#       `<turbo-cable-stream-source>` тримає `channel` в `observedAttributes`,
#       тож зміна атрибута перепідписує елемент САМА. Отже власний канал із
#       авторизацією обходиться одним рядком у devtools — і слухають його лише
#       ті, хто й так грав чесно.
#   (б) `reject` вбиває підписку ТИХО й НЕЗВОРОТНО. `reject()` кличе
#       `forget(subscription)`, підписка зникає зі списку, і `reload()` на
#       реконекті її вже не перевідправить; колбека `rejected` елемент не
#       визначає взагалі. Тобто fail-closed reject недосяжний для зловмисника
#       (він на іншому каналі) і калічить лише легітимного глядача, чиє імʼя
#       резолвер не впізнав. Той самий режим відмови, за який відкинуто TTL.
#
# Тому клас «підписане імʼя = безстроковий capability-токен» лишається ВІДКРИТИМ
# і закривається окремою формою (org-epoch у самому імені — «покинути адресу»
# замість «гейтити підписника»), а не тут. Не дописуй сюди `subscribed`-гард,
# не звірившись із `04_04 §8.1`.
#
# ⚠️ Bearer-шляху тут НЕМАЄ свідомо. `base_controller` має два шляхи автентифікації,
# але WebSocket-handshake із браузера не несе `Authorization` (обмеження
# WebSocket API, не Rails), а всі підписки в цьому дереві народжуються в
# Phlex-компонентах дашборда. Гілка під нативний WS-клієнт була б недосяжним
# кодом із дня написання; коли такий клієнт зʼявиться, він упаде ГУЧНО на
# `reject_unauthorized_connection`, а не пройде тихо.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # `session_id` тут не косметика: cookie-сесія несе стабільний per-browser
    # ідентифікатор (`CookieStore#write_session` кладе `session_data["session_id"]`),
    # тож пара «користувач + сесія» дає відкликання ОКРЕМОГО пристрою, а не всіх
    # сесій акаунта. Без нього перемикання контексту на ноутбуці рвало б стрім
    # і на телефоні.
    identified_by :current_user, :session_id

    def connect
      data = session_data
      self.current_user = verified_user(data)
      self.session_id = data["session_id"]
    end

    private

      # ⚠️ Сам `ActionDispatch::Session::CookieStore` читає через
      # `request.cookie_jar.signed_or_encrypted`, і саме це було б дослівним
      # дзеркалом. Тут `encrypted` — з двох причин, і обидві варто знати.
      # (1) Вони ТОТОЖНІ, поки є `secret_key_base` (`signed_or_encrypted` віддає
      #     `encrypted` саме за цієї умови), а він у нас обовʼязковий —
      #     `config/initializers/master_key_strength_check.rb` не дає завантажитись
      #     без нього. Тобто розбіжність досяжна лише в застосунку, який і так
      #     не бутиться.
      # (2) `ActionCable::Connection::TestCookieJar` визначає `signed` і
      #     `encrypted`, але `signed_or_encrypted` — НІ. З дослівним дзеркалом
      #     спека на цей файл штатним харнесом не пишеться взагалі, тобто вибір
      #     стояв між точнішим рядком і можливістю мати гейт.
      # Серіалізатор cookie — `:json`, тож ключі СЕСІЇ рядкові, не символьні.
      def session_data
        cookies.encrypted[Rails.application.config.session_options[:key]] || {}
      end

      # Дзеркало `Api::V1::BaseController#authenticate_user!` [SEC.16]: cookie
      # salt-bound, тож зміна пароля гасить викрадену сесію одразу. Розходження
      # цих двох перевірок означало б, що вебсокет переживає ревокацію, яку HTTP
      # уже застосував — тобто рівно ту дірку, від якої стемп і зроблено.
      def verified_user(data)
        user = User.find_by(id: data["user_id"])
        reject_unauthorized_connection unless user && data["ps"].to_s == user.password_salt.to_s.last(10)

        user
      end
  end
end
