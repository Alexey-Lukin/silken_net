# frozen_string_literal: true

require "openssl"
require "timeout"

class ActuatorCommandWorker
  include Sidekiq::Job
  # Черга downlink має вищий пріоритет.
  sidekiq_options queue: "downlink", retry: 3

  # [РЕТРАЙ-ПАРАДОКС]: Статус :failed виставляємо ТІЛЬКИ після того,
  # як усі ретраї вичерпано. Це запобігає "брехливому" failed у журналі,
  # якщо наступний ретрай виконається успішно.
  sidekiq_retries_exhausted do |job, _exception|
    command = ActuatorCommand.find_by(id: job["args"].first)
    if command
      error_msg = job["error_message"].to_s.truncate(200)
      if command.update(status: :failed, error_message: error_msg)
        broadcast_command_state_static(command)
      end
      Rails.logger.error "🛑 [Downlink Exhausted] Наказ ##{command.id} провалено після всіх спроб: #{error_msg}"
    end
  end

  # 📈 Статичний метод для broadcast з денормалізованим organization_id
  def self.broadcast_command_state_static(command)
    org = command.organization || command.actuator.gateway.cluster.organization
    return unless org

    Turbo::StreamsChannel.broadcast_replace_to(
      org,
      target: "command_status_#{command.id}",
      html: Actuators::CommandStatusBadge.new(command: command).call
    )
  end

  def perform(command_id, explicit_key = nil)
    command = ActuatorCommand.find_by(id: command_id)
    return unless command

    actuator = command.actuator
    gateway = actuator.gateway

    # 1. ЗАХИСТ ТА ПЕРЕВІРКА ГОТОВНОСТІ
    return if command.status_acknowledged? || command.status_confirmed?

    # ⏱️ TTL: перевіряємо актуальність перед відправкою
    if command.expired?
      handle_failure(command, "⏱️ Команда протермінована (TTL: #{command.expires_at})")
      return
    end

    unless gateway.ip_address.present?
      handle_failure(command, "🛑 [Downlink] Шлюз #{gateway.uid} не має IP! Наказ скасовано.")
      return
    end

    if gateway.updating?
      Rails.logger.warn "⏳ [Downlink] Шлюз #{gateway.uid} оновлюється. Відтермінування наказу..."
      raise "Gateway Busy: Updating"
    end

    # 2. ШИФРУВАННЯ (Dual-Key Awareness)
    key_record = HardwareKey.find_by(device_uid: gateway.uid)

    if key_record.nil? || key_record.binary_key.blank?
      handle_failure(command, "🛑 [Downlink] Ключ для Королеви #{gateway.uid} відсутній!")
      return
    end

    # ⚡ [КЕНОЗИС БЕЗПЕКИ]: Вибір мови спілкування
    # Якщо діє Grace Period, ми МАЄМО відправляти команди старим ключем,
    # бо пристрій ще не підтвердив перехід на новий.
    # explicit_key (hex-рядок) використовується при примусовій ротації.
    encryption_key = if explicit_key.present?
      [ explicit_key ].pack("H*") # Конвертуємо HEX-рядок у сирі байти
    else
      key_record.binary_previous_key || key_record.binary_key
    end

    # 🛡️ Idempotency: включаємо idempotency_token у payload для дедуплікації на STM32
    raw_payload = "CMD:#{command.command_payload}:#{command.duration_seconds}:#{actuator.id}:#{command.idempotency_token}"
    encrypted_payload = encrypt_payload(raw_payload, encryption_key)

    begin
      # 3. ФІЗИЧНА ПЕРЕДАЧА (CoAP Protocol)
      command.update!(status: :sent)
      broadcast_command_state(command)

      gateway.mark_seen!

      Timeout.timeout(7) do
        url = "coap://#{gateway.ip_address}/actuator/#{actuator.endpoint}"
        response = CoapClient.put(url, encrypted_payload)

        # Перевіряємо, чи Королева прийняла наказ
        unless response&.success?
          raise "Королева відхилила наказ. CoAP Code: #{response&.code}"
        end
      end

      # 4. ПІДТВЕРДЖЕННЯ ТА ТРАНСФОРМАЦІЯ СТАНУ
      ActiveRecord::Base.transaction do
        actuator.mark_active!
        command.update!(status: :acknowledged, sent_at: Time.current)
      end

      Rails.logger.info "⚡ [Downlink] Наказ #{command.id} (token: #{command.idempotency_token}) успішно доставлено на #{gateway.uid} -> #{actuator.endpoint}"
      broadcast_command_state(command)

      # 5. ПЛАНУВАННЯ ПОВЕРНЕННЯ (The Reset)
      ResetActuatorStateWorker.perform_in(command.duration_seconds.seconds, command.id)

    rescue Timeout::Error => e
      Rails.logger.error "🛑 [Downlink Error] Наказ ##{command.id} провалено: Gateway Timeout (No ACK from Queen)"
      raise e # Retry для Sidekiq; статус :failed виставить sidekiq_retries_exhausted
    rescue StandardError => e
      Rails.logger.error "🛑 [Downlink Error] Наказ ##{command.id} провалено: #{e.message}"
      raise e
    end
  end

  private

  def handle_failure(command, message)
    Rails.logger.error "🛑 [Downlink Error] Наказ ##{command.id} провалено: #{message}"
    command.update!(status: :failed, error_message: message.truncate(200))
    broadcast_command_state(command)
  end

  def encrypt_payload(payload, binary_key)
    cipher = OpenSSL::Cipher.new("aes-256-ecb")
    cipher.encrypt
    cipher.key = binary_key
    cipher.padding = 0

    block_size = 16
    padding_length = (block_size - (payload.bytesize % block_size)) % block_size
    padded_payload = payload + ("\x00" * padding_length)

    cipher.update(padded_payload) + cipher.final
  end

  # 📈 Використовуємо денормалізований organization_id для broadcast
  def broadcast_command_state(command)
    self.class.broadcast_command_state_static(command)
  end
end
