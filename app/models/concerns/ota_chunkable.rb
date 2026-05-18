# frozen_string_literal: true

# Спільна логіка розбиття бінарного payload на CoAP-сегменти (TinyMlModel, BioContractFirmware).
# Моделі, що підключають цей concern, мають реалізувати метод #binary_payload та #payload_size.
module OtaChunkable
  extend ActiveSupport::Concern

  # Розбиття на сегменти для OtaTransmissionWorker (MTU-friendly).
  # byteslice без regex: O(n/chunk) memcpy без backtracking. На 256 KB binary
  # payload (FW.4 max) це ~3× швидше за regex.scan і не виділяє inter-buffer
  # regex match data.
  def chunks(chunk_size = 512)
    size = payload_size
    return [] if size.zero?

    payload = binary_payload.b
    result = Array.new((size + chunk_size - 1) / chunk_size)
    offset = 0
    i = 0
    while offset < size
      result[i] = payload.byteslice(offset, chunk_size)
      offset += chunk_size
      i += 1
    end
    result
  end

  # Integer math — уникаємо Float, щоб для великих payload не отримати
  # off-by-one через накопичення похибки `to_f`.
  def total_chunks(chunk_size = 512)
    size = payload_size
    return 0 if size.zero?

    (size + chunk_size - 1) / chunk_size
  end
end
