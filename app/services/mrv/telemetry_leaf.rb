# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Mrv
  # ==========================================================================
  # 🍃 MRV TELEMETRY LEAF (canonical leaf-формула Merkle-дерев — ARCH.12/E.60)
  # ==========================================================================
  # ОДИН дім leaf-формули для обох якорів (Eth-L1 state_root · Polygon
  # archive_root) і mint-lineage вікон: leaf = детермінований CIDv1 канонічного
  # payload'а запису телеметрії (`05_02 §E.60`). Скаляри пінені явно — бо
  # JSON.generate(BigDecimal) дає scientific-notation, JSON.generate(Time) —
  # залежить від бібліотеки, а enum-рядок міняється при rename ключа:
  #   z_value    → BigDecimal#to_s("F") (plain "23.45"; NULL лишається null —
  #                рядок НІКОЛИ не виключається з дерева через відсутнє поле)
  #   bio_status → сирий integer з enum-мапи (rename-proof)
  #   created_at → utc.iso8601(6) (µs — прецедент AuditLog#chain_payload)
  #   device_uid → tree.did (attr_readonly — лист не «переїжджає» між DID)
  # Зміна формули = нова версія, і версія живе на РЯДКУ (`telemetry_logs.leaf_version`), не
  # глобально: кожен корінь перераховується формулою своїх рядків, тож історія не переписується.
  #
  # ⚖️ [FW.66 (Б) · S8, `05_02 §E.60`] v2 — CCM-рядок: замість Z (CCM-ера його не має) лист
  # зобовʼязує щодо сирого кадру ефіру `raw_record` (30 Б: DID ‖ gossip ‖ FC ‖ шифртекст ‖ MIC —
  # gossip входить в AAD CCM) у нижньому hex. v2-payload декларує версію ключем, v1 — без ключа
  # (його формулу пінить золотий вектор, тож поле не дописати). ⚠️ Стеля: кадр зашифровано
  # сесійним ключем, а ратчет його знищує (backward secrecy), тож після ротації MIC і вимір
  # з кадру не відтворить ніхто — лист зобовʼязує щодо ІДЕНТИЧНОСТІ кадру, не щодо виміру.
  # Вміст v2 — ⚖️ до фліпу FW.2 (`00_07` FW.66): після першого заякореного v2-листа зміна = v3.
  # Інваріант пари (версія ⟷ кадр) тримає CHECK `telemetry_logs_leaf_version_shape`; «невідома
  # версія» тут — неможливий стан, і він падає голосно.
  # ==========================================================================
  module TelemetryLeaf
    VERSIONS = [ 1, 2 ].freeze

    module_function

    def payload_for(log)
      case log.leaf_version
      when 1
        {
          telemetry_log_id: log.id,
          device_uid: log.tree.did,
          z_value: log.z_value&.to_s("F"),
          bio_status: TelemetryLog.bio_statuses[log.bio_status],
          created_at: log.created_at.utc.iso8601(6)
        }
      when 2
        {
          leaf_version: 2,
          telemetry_log_id: log.id,
          device_uid: log.tree.did,
          raw_record: log.raw_record.unpack1("H*"),
          created_at: log.created_at.utc.iso8601(6)
        }
      else
        raise ArgumentError, "TelemetryLog ##{log.id}: невідома версія листа #{log.leaf_version.inspect}"
      end
    end

    def cid_for(log)
      Filecoin::CidGenerator.cidv1(payload_for(log))
    end
  end
end
