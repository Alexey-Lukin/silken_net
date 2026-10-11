# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [FW.66 (Б) · S8b — `05_02 §E.60`] Підписаний QATT-конверт АТЕСТОВАНОГО батча Королеви — доказ, на який
# посилається лист Меркла v2 (`telemetry_logs.qatt_envelope_sha256`). Зберігаються лише атестовані:
# неатестований конверт нічого не доводить, а будь-хто міг би засмічувати таблицю. Ідентичність
# (`sha256 = sha256(envelope)`) і форму ключа тримає схема; рядок незмінний після запису.
# Публікується лише в lineage-бандлі для аудитора, не в публічному IPFS-артефакті (⚖️ делеговано й
# ратифіковано 2026-10-11): підписаний заголовок не редагується і несе стан детектора спуфінгу.
class QattEnvelope < ApplicationRecord
  belongs_to :gateway

  # Незмінний після запису — крім `unpacked_at`, який воркер ставить `update_all`-ом, коли з батча
  # закомічено хоч один рядок.
  def readonly? = persisted?

  # Ідемпотентний запис (ретрай Sidekiq, crash-resume): той самий конверт — той самий рядок, і
  # наявний рядок НЕ переписується. Повертає sha256 (32 Б) або nil, якщо sha уже належить ІНШІЙ
  # Королеві — чесний конверт двом шлюзам належати не може, тож рядки такого батча хешу не дістають.
  def self.record!(envelope:, gateway:, public_key_hex:, received_at:)
    sha = QattEnvelopeSignature.sha256(envelope)
    insert({ sha256: sha, gateway_id: gateway.id, gateway_uid: gateway.uid, envelope: envelope.b,
             public_key_hex: public_key_hex.downcase, received_at: received_at, created_at: Time.current },
           unique_by: :index_qatt_envelopes_on_sha256)
    owner_id = where(sha256: sha).pick(:gateway_id)
    return sha if owner_id == gateway.id

    Rails.logger.error "🚨 [L1 QATT] конверт #{sha.unpack1('H*')[0, 16]}… уже належить шлюзу ##{owner_id}, не #{gateway.uid}."
    nil
  end
end
