# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Дім імен Turbo-стрімів — ОДИН, і кличуть його ОБИДВІ сторони тракту.
#
# 🔴 Чому це не косметика, а несуче. До цього кожне імʼя писалось руками з обох
# боків незалежно: 5 підписок (`app/views/components/**`) + 6 броадкастів
# (воркери/моделі/сервіси), плюс реєстр-коментар у `config/cable.yml` і таблиця
# в `04_04 §8.1`. Сторони не звіряло ніщо. Один символ різниці дає або тихо
# мертвий тракт — репо ловило цей клас ТРИЧІ постфактум (`wallet` проти
# `[wallet, :transactions]`, `transaction_{id}` проти `blockchain_transaction_{id}`,
# `actuator_card_{id}` проти `actuator_{id}`), — або, якщо втрачено саме токен
# `_org_`, живий крос-тенант витік (`00_07` SEC.25: `"telemetry_stream"` віддавав
# payload чужих Королев кожному автентифікованому глядачу).
#
# 🔒 Що цей дім НЕ робить: він не доводить, що передана організація — глядачева.
# Це питання «чи МОЖЕ це зʼєднання слухати цей стрім», і обидва факти разом
# існують лише в `subscribed` власного каналу — тобто у Ф1 (`00_07` SEC.25).
# Render-time assert тут свідомо НЕ ставиться: він тавтологічний (усі три
# контролери виводять org тим самим виразом, з яким його б і порівнювали) і
# недосяжний для компонент-спек-харнеса, що рендерить через
# `ApplicationController.renderer`, де `current_user` не оголошений хелпером.
#
# Форма дому вибрана так, щоб її читав AST-гейт (`lib/turbo_stream_inventory.rb`):
# клас імені видно з ІМЕНІ МЕТОДУ на цьому ресівері, тож `org` і `gateway_ota`
# лишаються РІЗНИМИ класами обовʼязку доказу, а не зливаються в «indirect».
module TurboStreams
  module Name
    # Реєстр org-скоуплених стрімів. `fetch`, а не `[]`: описка в ключі мусить
    # падати гучно, а не народжувати тихе нове імʼя, на яке ніхто не підписаний.
    ORG_PREFIXES = {
      telemetry: "telemetry_stream",
      alerts: "ews_alerts",
      map: "geospatial_matrix"
    }.freeze

    class << self
      def org(kind, organization)
        "#{ORG_PREFIXES.fetch(kind)}_org_#{demand_id(organization)}"
      end

      # Імʼя БЕЗ org-токена — безпечне лише транзитивно (сторінка, що його
      # рендерить, сама org-скоуплена). Тому в гейті це окремий клас із окремим
      # обовʼязком доказу, і форма того доказу залежить від кардинальності
      # сторінки, не від форми імені (стеля №4 у шапці scope-гейта).
      def gateway_ota(gateway)
        "ota_channel_#{demand_uid(gateway)}"
      end

      private

      # Fail-closed, і це НЕ захисне padding: `nil` тут дав би `..._org_` —
      # імʼя, СПІЛЬНЕ для всіх організацій, тобто рівно той витік, від якого цей
      # дім існує. Викликачі, що легально можуть не мати організації, гасять це
      # ВЛАСНИМ guard'ом (`return unless org_id` / `if @organization`) — тут
      # мовчазний фолбек був би гіршим за виняток.
      def demand_id(organization)
        id = organization.respond_to?(:id) ? organization.id : organization
        raise ArgumentError, "org-стрім без організації: імʼя стало б спільним для всіх" if id.blank?

        id
      end

      def demand_uid(gateway)
        uid = gateway.respond_to?(:uid) ? gateway.uid : gateway
        raise ArgumentError, "ota-стрім без uid шлюзу" if uid.blank?

        uid
      end
    end
  end
end
