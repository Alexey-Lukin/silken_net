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
  # Зміна формули = LEAF_VERSION+1 (historical-верифікація за версією).
  # ==========================================================================
  module TelemetryLeaf
    LEAF_VERSION = 1

    module_function

    def payload_for(log)
      {
        telemetry_log_id: log.id,
        device_uid: log.tree.did,
        z_value: log.z_value&.to_s("F"),
        bio_status: TelemetryLog.bio_statuses[log.bio_status],
        created_at: log.created_at.utc.iso8601(6)
      }
    end

    def cid_for(log)
      Filecoin::CidGenerator.cidv1(payload_for(log))
    end
  end
end
