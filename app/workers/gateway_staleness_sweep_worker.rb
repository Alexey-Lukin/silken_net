# frozen_string_literal: true

# [ARCH.54 Шар 0] Dead-man switch Королеви: Rails сам детектить тишу шлюзу,
# не покладаючись на здатність хворого кричати (heartbeat/SOS — Шари 1-2,
# вони ЗБАГАЧУЮТЬ, а цей sweeper — первинний permanence-сторож NaaS).
#
# Канон: 06_08 §1.3 (Queen Health Heartbeat → Rails). Тиша = last_seen_at
# прострочив config_sleep_interval_s з люфтом 1.2 (скоуп Gateway.offline —
# One-Home порога, той самий, що online?/дашборд).
#
# Три обов'язки за один прохід:
#   1. offline + робочий стан → report_fault! + EwsAlert(queen_offline)
#      (критичний: кластер осліп, емісія його дерев без нагляду).
#   2. faulty + знову online → recover! + resolve відповідного алерту
#      (симетрія: тиша скінчилась — лісник не їде дарма).
#   3. attest-lapse спостереження: QATT-Королева (є ed25519 pubkey), батчі
#      ходять (online), а підписи зникли > ATTEST_LAPSE_HOURS — можлива
#      підміна прошивки/деградація L1. Поки лише метрика+лог (алерт-тип
#      додамо, коли L1 стане mandatory — свідома стеля, 00_07 ARCH.54).
class GatewayStalenessSweepWorker
  include Sidekiq::Job
  # alerts(2): народжує life-safety сигнали EWS — вище за critical(3)-slash
  # у strict-дренажі; сам прохід — кілька легких запитів.
  sidekiq_options queue: "alerts", retry: 2

  ATTEST_LAPSE_HOURS = 24

  def perform
    flagged   = flag_silent_gateways
    recovered = recover_returned_gateways
    lapsed    = observe_attest_lapse

    SilkenNet::Metrics::GATEWAYS_FAULTY.set(Gateway.faulty.count)
    SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED.set(lapsed)

    Rails.logger.info(
      "👑 [ARCH.54] Staleness sweep: flagged=#{flagged} recovered=#{recovered} attest_lapsed=#{lapsed}"
    )
  end

  private

  # Мовчазні шлюзи у робочих станах → faulty + алерт. Свідомо ПОЗА скоупом:
  # maintenance (людина вже знає) і last_seen_at IS NULL (шлюз зареєстрований,
  # але ще ніколи не виходив в ефір — «мовчання ненародженого» ≠ деградація;
  # стеля позначена: field-інсталяція без першого зв'язку лишається невидимою
  # до першого mark_seen!).
  def flag_silent_gateways
    count = 0
    Gateway.offline.where.not(last_seen_at: nil)
           .where(state: [ :idle, :active, :updating ])
           .includes(:cluster).find_each do |gateway|
      gateway.report_fault!
      create_offline_alert(gateway)
      SilkenNet::Metrics::GATEWAYS_OFFLINE_TOTAL.increment
      count += 1
    end
    count
  end

  def recover_returned_gateways
    count = 0
    Gateway.online.faulty.includes(:cluster).find_each do |gateway|
      gateway.recover!
      resolve_comms_alerts(gateway)
      count += 1
    end
    count
  end

  # Дедуп по кластеру: EwsAlert-валідація uniqueness тримає лише tree_id-алерти
  # (tree_id тут nil), тому анти-спам guard — руками. Стеля: друга Королева
  # того ж кластера, що впала ПІД активним алертом першої, окремого алерту не
  # отримає (uid — у message; кластер сьогодні ~1 Queen). cluster_id завжди
  # present — Gateway#belongs_to :cluster обов'язковий.
  def create_offline_alert(gateway)
    return if EwsAlert.unresolved.alert_type_queen_offline
                      .exists?(cluster_id: gateway.cluster_id)

    silent_for = ((Time.current - gateway.last_seen_at) / 60).round
    EwsAlert.create!(
      cluster_id: gateway.cluster_id,
      severity: :critical,
      alert_type: :queen_offline,
      message: "👑 Королева #{gateway.uid} мовчить #{silent_for} хв " \
               "(останній зв'язок #{gateway.last_seen_at.utc.iso8601}). " \
               "Кластер без uplink — телеметрія дерев не надходить."
    )
  end

  # Резолвимо ОБИДВА comms-типи: dead-man switch (ми помітили тишу) і Helium-SOS
  # (Королева крикнула через чужі hotspot'и, ARCH.34). Обидва стверджують одне —
  # «Королева без uplink» — і обидва спростовує той самий факт: вона знову в ефірі.
  # До цього queen_uplink_lost не мав резолвера ЖОДНОГО (HeliumSosWorker обіцяв
  # «sweeper-recovery після повернення батчів», але sweeper фільтрував лише
  # queen_offline) → лишався активним вічно й латчив comms_no_ack? назавжди.
  # resolve! без `user:` — машинний шлях (дискримінатор gap-E: див.
  # BlockchainBurningService#critical_unmaintained?).
  def resolve_comms_alerts(gateway)
    EwsAlert.unresolved
            .where(alert_type: [ :queen_offline, :queen_uplink_lost ])
            .where(cluster_id: gateway.cluster_id).find_each do |alert|
      alert.resolve!(notes: "Королева #{gateway.uid} повернулась в ефір " \
                            "(#{gateway.last_seen_at.utc.iso8601}).") # online ⇒ present
    end
  end

  # QATT-джерело правди: HardwareKey#ed25519_public_key_hex (той самий
  # реєстр, що верифікація конверта). last_attested_at нарешті отримує
  # читача (до ARCH.54 колонка була write-only).
  def observe_attest_lapse
    lapsed = Gateway.online.joins(:hardware_key)
                    .where.not(hardware_keys: { ed25519_public_key_hex: [ nil, "" ] })
                    .where(last_attested_at: [ nil, ...ATTEST_LAPSE_HOURS.hours.ago ])
    lapsed.find_each do |gateway|
      Rails.logger.warn(
        "👑 [ARCH.54] Attest-lapse: #{gateway.uid} online, але QATT-підпису нема " \
        "з #{gateway.last_attested_at&.utc&.iso8601 || 'ніколи'} — перевірити EDSK/прошивку."
      )
    end
    lapsed.count
  end
end
