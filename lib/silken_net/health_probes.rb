# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module SilkenNet
  # = =====================================================================
  # 🩺 HealthProbes — проби, що ДОВОДЯТЬ, а не припускають
  # = =====================================================================
  #
  # [ARCH.81] Один дім для двох поверхонь, що доти розійшлись: `/ready`
  # (оркестратор) робив чесні раунд-тріпи, а адмін-панель питала об'єкти про
  # них самих — тобто машині діставалась правда, людині здогад. Саме тому
  # проби живуть тут, а не в контролерах: розділені, вони й розійшлись.
  #
  # Правило дому: проба або доводить те, що обіцяє її ім'я, або каже, що не
  # знає. Третього («поміряю сусіднє й назву це відповіддю») немає.
  module HealthProbes
    # Одна спроба, коротка: панель — не CI-гейт, і людина чекає на відповідь.
    # Мовчання UDP коштує рівно цей таймаут; закритий порт віддає ICMP і
    # відповідає одразу.
    COAP_PROBE_TIMEOUT_S = 1.0

    module_function

    # Раунд-тріп до бази. `connection.active?` натомість питав об'єкт з'єднання
    # про його власну думку про себе — вердикт, що не залежить від того, чи
    # відповідає Postgres.
    def database_reachable?
      ActiveRecord::Base.connection.execute("SELECT 1")
      true
    rescue StandardError
      false
    end

    # ДВА КЛІЄНТИ, не дві бази [INF.22]. Тут доти стояло «обидва Redis: DB 0 і
    # DB 1» — нумерованих баз у нас більше немає (Upstash дає рівно одну), тож
    # обидва пінги йдуть в один keyspace. Обидва лишаються несучими саме тому,
    # що це РІЗНІ клієнти з різними пулами: Kredis тримає Web3-нонси й
    # mint/burn-локи, і money-шлях залежить від нього не менше, ніж від черг.
    # Пінг Sidekiq не доводить, що живий пул Kredis, і навпаки.
    def redis_reachable?
      sidekiq_ok = Sidekiq.redis { |conn| conn.call("PING") } == "PONG"
      kredis_ok  = Kredis.redis(config: :shared).ping == "PONG"
      sidekiq_ok && kredis_ok
    rescue StandardError
      false
    end

    # Скільки процесів Sidekiq справді живі. `Sidekiq::Stats` відповідає, поки
    # живий Redis — тобто «статистика прийшла» не означає, що черги хтось
    # дренує; порожній ProcessSet при живому Redis і є та тиша, якої на панелі
    # з іменем «Sidekiq Workers» не було видно.
    def sidekiq_process_count
      Sidekiq::ProcessSet.new.size
    end

    # Стан CoAP-інтейку, доведений тим самим UDP-шляхом, яким ходить Королева.
    #
    # Три відповіді, і третя несуча: демон живе ПОЗА цим процесом (PRIMARY —
    # Ingress Anchor, `06_03 §2.9(б)`), тож незадана адреса означає «не знаю», а
    # не «мертвий». Мовчазний дефолт на loopback зробив би ці два стани
    # невідрізнимими — і саме він тримав панель вічно червоною.
    #
    # Зонд — freeze-contract `CoapSmoke.liveness_probe`: сміття в опціях, яке
    # граматика відкидає ДО маршрутизації, тож ні БД, ні черг він не торкається.
    # Байт-точна звірка відповіді відрізняє «демон живий» від «на порту хтось
    # інший» — чого «порт відкритий» для connectionless-сокета не вміє в принципі.
    def coap_listener(timeout: COAP_PROBE_TIMEOUT_S)
      port = ENV.fetch("COAP_PORT", CoapSmoke::DEFAULT_PORT).to_i
      host = ENV["COAP_HOST"].presence
      return { status: "not_configured", port: port } if host.nil?

      probe = CoapSmoke.liveness_probe
      reply = CoapSmoke.shoot(host, port, probe.datagram, timeout: timeout)

      { status: coap_verdict(reply, probe), host: host, port: port }
    rescue StandardError => e
      Rails.logger.warn "[HealthProbes] CoAP-проба впала: #{e.message}"
      { status: "check_failed", port: port || CoapSmoke::DEFAULT_PORT }
    end

    def coap_verdict(reply, probe)
      return "unreachable" if reply.nil?
      return "alive" if reply.unpack1("H*").upcase == probe.expect_hex

      "wire_mismatch"
    end
  end
end
