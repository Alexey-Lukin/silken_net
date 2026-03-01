# frozen_string_literal: true

require "openssl"
require "timeout"

class ActuatorCommandWorker
  include Sidekiq::Job
  # Черга downlink має вищий пріоритет.
  sidekiq_options queue: "downlink", retry: 3

  def perform(command_id, explicit_key = nil)
    command = ActuatorCommand.find_by(id: command_id)
    return unless command

    actuator = command.actuator
    gateway = actuator.gateway

    # 1. ЗАХИСТ ТА ПЕРЕВІРКА ГОТОВНОСТІ
    return if command.status_acknowledged? || command.status_confirmed?

    unless gateway.ip_address.present?
      handle_failure(command, "🛑 [Downlink] Шлюз #{gateway.uid} не має IP! Наказ скасовано.")
      return
    end

    if gateway.state_updating?
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
    # explicit_key використовується при примусовій ротації.
    encryption_key = explicit_key || key_record.binary_previous_key || key_record.binary_key

    # Формуємо пакет згідно з протоколом прошивки main.c
    raw_payload = "CMD:#{command.command_payload}:#{command.duration_seconds}:#{actuator.id}"
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

      Rails.logger.info "⚡ [Downlink] Наказ #{command.id} успішно доставлено на #{gateway.uid} -> #{actuator.endpoint}"
      broadcast_command_state(command)

      # 5. ПЛАНУВАННЯ ПОВЕРНЕННЯ (The Reset)
      ResetActuatorStateWorker.perform_in(command.duration_seconds.seconds, command.id)

    rescue Timeout::Error => e
      handle_failure(command, "Gateway Timeout (No ACK from Queen)")
      raise e # Retry для Sidekiq
    rescue StandardError => e
      handle_failure(command, e.message)
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

  # Трансляція зміни стану наказу для живої картини в Dashboard
  def broadcast_command_state(command)
    Turbo::StreamsChannel.broadcast_replace_to(
      command.actuator.gateway.cluster.organization,
      target: "command_status_#{command.id}",
      html: Views::Components::Actuators::CommandStatusBadge.new(command: command).call
    )
  end
end
