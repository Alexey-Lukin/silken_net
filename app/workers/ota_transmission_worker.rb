class OtaTransmissionWorker
  include Sidekiq::Job
  sidekiq_options queue: "downlink", retry: 3

  def perform(queen_uid, firmware_type, record_id)
    gateway = Gateway.find_by!(uid: queen_uid)

    # Збираємо бінарний payload (TinyML або mruby)
    payload = case firmware_type
    when "mruby"
      BioContractFirmware.find(record_id).binary_payload
    when "tinyml"
      TinyMlModel.find(record_id).binary_weights_payload
    end

    # Розбиваємо на чанки (наприклад, по 512 байт для CoAP)
    chunks = payload.chars.each_slice(512).map(&:join)

    chunks.each_with_index do |chunk, index|
      # Відправляємо через UDP/CoAP на IP-адресу модему SIM7070G Королеви
      # Використовуємо кастомний клас CoapClient (який ми ще напишемо в lib/)
      CoapClient.put("coap://#{gateway.ip_address}/ota/#{firmware_type}?chunk=#{index}", chunk)
    end

    Rails.logger.info "📡 [OTA] Прошивку успішно відправлено на Шлюз #{queen_uid}"
  end
end
