# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Спільна логіка розбиття бінарного payload на CoAP-сегменти (TinyMlModel, BioContractFirmware).
# Моделі, що підключають цей concern, мають реалізувати метод #binary_payload та #payload_size.
module OtaChunkable
  extend ActiveSupport::Concern

  # One-Home пакувального кроку OTA. Число жило в `OtaTransmissionWorker`, чий ПУСКАЧ мертвий
  # із [FW.60] і чий файл піде після bench-верифікації poll-тракту — а константу читають два
  # живі сайти (`Downlink::PendingQueueService`, `Ota::DeploymentDispatcherService`). Тут воно
  # стоїть біля обох методів, які ним ріжуть, тож наступний, хто зноситиме воркер, не візьме
  # з собою живе значення. ⚠️ Підняття вище MTU конверта CoAP не перевіряє ніщо —
  # `PendingQueueService` нарізає без контролю розміру (спека того сервісу це фіксує).
  CHUNK_SIZE = 512

  # Розбиття на сегменти (MTU-friendly). byteslice без regex: O(n/chunk) memcpy
  # без backtracking. На 256 KB binary payload (FW.4 max) це ~3× швидше за
  # regex.scan і не виділяє inter-buffer regex match data.
  #
  # ⚠️ **Споживача СЬОГОДНІ немає, і доти тут стояв мертвий** (переміряно
  # 2026-08-17): коментар називав `OtaTransmissionWorker`, який із часів [FW.60]
  # не має жодного enqueuer'а, а власних викликачів `#chunks` у дереві нуль —
  # живий poll-тракт нарізає чанки сам (`OtaPackagerService`). Метод лишено, не
  # зрізано: зняття push-ери гейтоване стендом (`00_07` ARCH.59-нитка), і в
  # передпродовому дереві нуль викликачів вимірює недобудованість, не смерть.
  def chunks(chunk_size = CHUNK_SIZE)
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
  def total_chunks(chunk_size = CHUNK_SIZE)
    size = payload_size
    return 0 if size.zero?

    (size + chunk_size - 1) / chunk_size
  end
end
