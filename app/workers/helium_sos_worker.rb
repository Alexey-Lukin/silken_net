# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.34 L3] Розбір SOS-кадру Королеви з Helium-webhook'а → EwsAlert
# (queen_uplink_lost). Королева ЖИВА, але без власних uplink'ів — телеметрія
# Солдатів буферизується у Flash-ринг (ARCH.35), потрібна ескалація (виїзд).
#
# SOS-wire 12B (📐 One-Home — 06_08 §1.2; firmware-half ARCH.34 його ж
# емітуватиме): [queen_did:4 BE][vcap_mv:2 BE][error_code:1]
# [uptime_min:3 BE][flags:1][rsv:1]. Приймаємо ≥8B (обов'язкова частина
# did+vcap+err+перший байт uptime відсутній... ні: строго 12 або більше —
# майбутні розширення хвостом; коротше = malformed).
#
# Ідентичність: dev_eui → gateways.helium_dev_eui (реєструється при
# Helium-Console провіженінгу) + cross-check queen_did проти hex-частини
# uid (UID_FORMAT SNET-Q-%08X — did і Є ті 8 hex). Розбіжність = спуф або
# misprovision → drop з гучною метрикою, НЕ алерт (не смикаємо лісника
# на підробку).
class HeliumSosWorker
  include Sidekiq::Job
  # alerts(2): SOS і Є алерт — життєво-критичний сигнал EWS.
  sidekiq_options queue: "alerts", retry: 2

  SOS_MIN_BYTES = 12
  ERROR_CODES = {
    1 => "starlink_down",
    2 => "lte_down",
    3 => "q2q_unreachable",
    4 => "buffer_pressure" # Flash-ринг > 50% (умова активації, 02_05 §6.1)
  }.freeze

  def perform(dev_eui, payload_b64, reported_at = nil)
    Sentry.set_tags(helium_dev_eui: dev_eui)

    gateway = Gateway.find_by(helium_dev_eui: dev_eui.to_s.strip.upcase)
    unless gateway
      Rails.logger.warn "🆘 [Helium] SOS від незареєстрованого dev_eui=#{dev_eui} — drop."
      SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL.increment(labels: { outcome: "unknown_dev_eui" })
      return
    end

    sos = decode_sos(payload_b64)
    unless sos
      SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL.increment(labels: { outcome: "malformed" })
      return
    end

    # Cross-check двох незалежних ідентичностей: LoRaWAN-шар (dev_eui) і
    # SilkenNet-шар (queen_did у самому кадрі). uid = SNET-Q-%08X(did).
    expected_uid = format("SNET-Q-%08X", sos[:queen_did])
    unless gateway.uid == expected_uid
      Rails.logger.error "🚨 [Helium] DID-mismatch: dev_eui=#{dev_eui} мапиться на " \
                         "#{gateway.uid}, а кадр каже #{expected_uid} — спуф/misprovision."
      SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL.increment(labels: { outcome: "did_mismatch" })
      return
    end

    # Функціонально шлюз offline для бекенда (батчів не буде) — не чекаємо
    # 5-хв sweeper'а. maintenance не чіпаємо (людина вже поруч).
    gateway.report_fault! if gateway.may_report_fault? && !gateway.maintenance?

    create_sos_alert(gateway, sos, reported_at)
    SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL.increment(labels: { outcome: "accepted" })
  end

  private

  def decode_sos(payload_b64)
    raw = Base64.strict_decode64(payload_b64.to_s)
    return nil if raw.bytesize < SOS_MIN_BYTES

    did, vcap, err, up_hi, up_mid, up_lo, flags =
      raw.unpack("N n C C3 C")
    {
      queen_did: did, vcap_mv: vcap, error_code: err,
      uptime_min: (up_hi << 16) | (up_mid << 8) | up_lo, flags: flags
    }
  rescue ArgumentError
    Rails.logger.warn "🆘 [Helium] Битий Base64 у SOS-payload."
    nil
  end

  # Ідемпотентність: один активний queen_uplink_lost на КОРОЛЕВУ (SOS
  # ретрансмітиться, поки uplink мертвий — не плодимо дублікати; resolve зробить
  # лісник або sweeper-recovery після повернення батчів).
  #
  # 🔴 **Ключ — пара `cluster_id` + `message_params ->> 'uid'`, а не сам кластер**
  # [ARCH.54]: кластерний ключ глушив би не повтор ТІЄЇ САМОЇ Королеви, а крик
  # СУСІДНЬОЇ — два незалежні свідчення про два пристрої зливались в одне, і
  # мовчазно. Дзеркало того самого фіксу в `GatewayStalenessSweepWorker` (там же
  # й резолвер звужено симетрично — інакше повернення однієї Королеви гасить
  # алерт іншої). ⚠️ `?` у `where("… ? …")` Rails бере за bind-плейсхолдер, тому
  # JSONB-стрілка йде окремим рядком-умовою.
  # cluster_id завжди present (Gateway#belongs_to :cluster обов'язковий).
  def create_sos_alert(gateway, sos, reported_at)
    return if EwsAlert.unresolved.alert_type_queen_uplink_lost
                      .where(cluster_id: gateway.cluster_id)
                      .where("message_params ->> 'uid' = ?", gateway.uid)
                      .exists?

    reason = ERROR_CODES.fetch(sos[:error_code], "code_#{sos[:error_code]}")
    EwsAlert.create!(
      cluster_id: gateway.cluster_id,
      severity: :critical,
      alert_type: :queen_uplink_lost,
      # Два ключі, а не булевий параметр: reported_at — прозовий фрагмент.
      message_key: reported_at ? "queen_uplink_lost_reported" : "queen_uplink_lost",
      message_params: { uid: gateway.uid, reason: reason, vcap_mv: sos[:vcap_mv],
                        uptime_min: sos[:uptime_min], reported_at: reported_at }
    )
  end
end
