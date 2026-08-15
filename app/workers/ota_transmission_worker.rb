# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "timeout"

# ⚠️ [FW.60 superseded] Push-конвеєр чанків на gateway.ip_address (CGNAT-egress,
# inbound-недосяжний) — жоден код більше не enqueue'ить цей воркер:
# Ota::DeploymentDispatcherService пише gateways.pending_firmware_id, доставку
# тягне сама Королева (poll → OTA-hint → Downlink::PendingQueueService
# chunk-server). Видалити після bench-верифікації poll-тракту [bench:coap];
# CHUNK_SIZE лишається живою константою пакування.
class OtaTransmissionWorker
  include Sidekiq::Job
  include CoapEncryption
  # Використовуємо окрему чергу для низхідного зв'язку, щоб не блокувати телеметрію
  sidekiq_options queue: "downlink", retry: false

  # 🔴 [ARCH.59] Тут стояв `sidekiq_retries_exhausted`-блок, який мав рятувати
  # шлюз, залиплий у `:updating`. Він НЕ ВИКОНУВАВСЯ ЖОДНОГО РАЗУ: під
  # `retry: false` Sidekiq прокидає виняток одразу в `death_handlers`, минаючи
  # exhausted-хук — тобто «конфіг повний, шлях мертвий», лише з коментарем
  # «[P1 FIX]», який читався як доказ, що клас закрито. Знято, а не полагоджено:
  # сам воркер — залишок push-ери (нуль enqueuer'ів після FW.60), тож
  # відроджувати тут порятунок означало б лікувати мертвий шлях. Живий сторож
  # цього стану — `GatewayStalenessSweepWorker#release_stuck_ota_gateways`, і він
  # не залежить від того, який саме процес залишив шлюз у `:updating`.
  CHUNK_SIZE = 512
  MAX_CHUNK_RETRIES = 5

  def perform(queen_uid, firmware_type, record_id, chunk_index = 0, retry_count = 0)
    gateway = Gateway.find_by!(uid: queen_uid)
    key_record = HardwareKey.find_by!(device_uid: queen_uid)

    # 1. ОТРИМАННЯ ОБ'ЄКТА ПРОШИВКИ
    firmware_obj = fetch_firmware_record(firmware_type, record_id)

    # 2. ПАКУВАННЯ (Hardware-Aligned Packaging)
    # Отримуємо нарізані пакети з заголовками [0x99][Index][Total].
    # [FW.23] Forward gateway.cluster_id so OtaPackagerService appends the
    # 3 HMAC-SHA256 trailer chunks (0x9B) after the bytecode stream.
    # Soldier's dual-gate verifier rejects tampered or replayed images
    # before flash write — without the trailer that defence is inactive.
    # gateways.cluster_id is NOT NULL, so the trailer is always emitted
    # on the production path.
    ota_data = OtaPackagerService.prepare(
      firmware_obj,
      chunk_size: CHUNK_SIZE,
      cluster_id: gateway.cluster_id
    )
    packages = ota_data[:packages].to_a
    # [FW.23] When HMAC trailer is appended, manifest exposes total_packages
    # (= bytecode chunks + 3 trailer); the progress bar and the "done?"
    # comparison below must follow the wire count, not just the bytecode
    # chunks. Fallback to total_chunks keeps the helper safe to call from
    # a non-cluster context (specs, future Rake tasks).
    total_chunks = ota_data[:manifest][:total_packages] ||
                   ota_data[:manifest][:total_chunks]

    # Переводимо Королеву в режим оновлення тільки при першому чанку
    gateway.update!(state: :updating) if chunk_index.zero?

    # ⚡ [СИНХРОНІЗАЦІЯ]: Звітуємо Архітектору через Turbo Stream
    broadcast_progress(queen_uid, chunk_index, total_chunks)

    # 🔐 КРИПТОГРАФІЧНИЙ ЗАХИСТ (AES-256-CBC з випадковим IV)
    encrypted_package = coap_encrypt(packages[chunk_index], key_record.binary_key)

    begin
      # Збільшений таймаут для супутникових стрибків Starlink
      Timeout.timeout(25) do
        # Формуємо шлях CoAP з метаданими для Queen-реле
        url = "coap://#{gateway.ip_address}/ota/#{firmware_type}?ch=#{chunk_index}&ttl=#{total_chunks}"

        response = CoapClient.put(url, encrypted_package)

        raise "NACK: Шлюз відхилив чанк #{chunk_index} [Code: #{response&.code}]" unless response&.success?
      end
    rescue Timeout::Error, StandardError => e
      handle_chunk_failure(queen_uid, firmware_type, record_id, chunk_index, retry_count, e.message)
      return
    end

    # [S2.4] Track OTA chunk transmission for Prometheus monitoring
    SilkenNet::Metrics::OTA_CHUNKS_SENT_TOTAL.increment(labels: { firmware_version: firmware_obj.version })

    next_index = chunk_index + 1

    if next_index < total_chunks
      # Pacing: звільняємо потік Sidekiq між чанками замість блокуючого sleep.
      # HAL_FLASH_Program на STM32 потребує ~400 мс на запис у Flash.
      self.class.perform_in(0.4.seconds, queen_uid, firmware_type, record_id, next_index, 0)
    else
      # 4. ЗАВЕРШЕННЯ ЕВОЛЮЦІЇ
      gateway.update!(state: :idle, firmware_version: firmware_obj.version)
      broadcast_progress(queen_uid, total_chunks, total_chunks, status: "COMPLETE")

      Rails.logger.info "✅ [OTA] Еволюція завершена для #{queen_uid}. Версія: #{firmware_obj.version}"
    end
  end

  private

  # Вибір правильної моделі на основі типу OTA
  def fetch_firmware_record(type, id)
    case type.to_s
    when "mruby", "firmware" then BioContractFirmware.find(id)
    when "tinyml", "weights" then TinyMlModel.find(id)
    else raise ArgumentError, "🚨 Невідомий тип прошивки: #{type}"
    end
  end

  def broadcast_progress(uid, current, total, status: "TRANSMITTING")
    percent = ((current.to_f / total) * 100).to_i

    # Трансляція в персональний канал пристрою
    Turbo::StreamsChannel.broadcast_replace_to(
      TurboStreams::Name.gateway_ota(uid),
      target: Firmwares::OtaProgressBar.dom_id(uid),
      html: Firmwares::OtaProgressBar.new(
        uid: uid,
        percent: percent,
        current: current,
        total: total,
        status: status
      ).call
    )
  end

  def handle_chunk_failure(uid, type, record_id, index, retry_count, error)
    Rails.logger.error "⚠️ [OTA Failure] #{uid} чанк #{index}: #{error}"

    if retry_count < MAX_CHUNK_RETRIES
      # Експоненціальна затримка перед повтором
      wait_time = (retry_count + 1) * 15
      self.class.perform_in(wait_time.seconds, uid, type, record_id, index, retry_count + 1)
      broadcast_progress(uid, index, 100, status: "RETRYING_IN_#{wait_time}S")
    else
      Gateway.find_by(uid: uid)&.update!(state: :faulty)
      broadcast_progress(uid, index, 100, status: "FAILED")
      # Тут можна ініціювати Emergency Alert
    end
  end
end
