# frozen_string_literal: true

# Спільна логіка розбиття бінарного payload на CoAP-сегменти (TinyMlModel, BioContractFirmware).
# Моделі, що підключають цей concern, мають реалізувати метод #binary_payload та #payload_size.
module OtaChunkable
  extend ActiveSupport::Concern

  # Розбиття на сегменти для OtaTransmissionWorker (MTU-friendly)
  def chunks(chunk_size = 512)
    return [] if payload_size.zero?

    binary_payload.b.scan(/.{1,#{chunk_size}}/m)
  end

  def total_chunks(chunk_size = 512)
    return 0 if payload_size.zero?

    (payload_size.to_f / chunk_size).ceil
  end
end
