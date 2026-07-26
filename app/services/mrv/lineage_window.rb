# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Mrv
  # ==========================================================================
  # 🪟 MRV LINEAGE WINDOW (вікно вимірів mint-інтенту — MRV.1)
  # ==========================================================================
  # ОДИН дім запиту «логи вікна tx»: юзають fail-open обчислення кореня при мінті
  # (Wallet#attach_lineage_root) і lineage-bundle (аудиторський перерахунок).
  # Вікно = tuple-діапазон `(from_at, from_id) < (created_at, id) <= (to_at, to_id)`
  # — суміжні вікна гаманця не перетинаються і не лишають дір; порожнє вікно
  # (from == to або to NULL) чесно дає нуль рядків.
  # ==========================================================================
  module LineageWindow
    module_function

    def logs_for(tx)
      tree = tx.wallet&.tree
      return TelemetryLog.none if tree.nil? || tx.telemetry_window_to_at.nil?

      # «Голі» created_at-межі поруч із tuple-предикатами РЕДУНДАНТНІ семантично,
      # але несучі для плану: PG прунить партиції лише по literal/param на
      # partition-key — RowCompareExpr він не розкладає (EXPLAIN: 9 партицій → 1).
      scope = tree.telemetry_logs
                  .where(created_at: ..tx.telemetry_window_to_at)
                  .where("(telemetry_logs.created_at, telemetry_logs.id) <= (?, ?)",
                         tx.telemetry_window_to_at, tx.telemetry_window_to_id)
      if tx.telemetry_window_from_at
        scope = scope.where(created_at: tx.telemetry_window_from_at..)
                     .where("(telemetry_logs.created_at, telemetry_logs.id) > (?, ?)",
                            tx.telemetry_window_from_at, tx.telemetry_window_from_id)
      end
      scope.order(:created_at, :id)
    end

    # Merkle-корінь вікна (nil для порожнього) — leaf-формула One-Home Mrv::TelemetryLeaf.
    def root_for(tx)
      MerkleTree.root(logs_for(tx).preload(:tree).map { |log| Mrv::TelemetryLeaf.cid_for(log) })
    end
  end
end
