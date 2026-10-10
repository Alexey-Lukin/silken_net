# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [FW.59, ратифіковано 2026-10-10 — врізка під `AlertDispatchService` у 04_02] Причина
# останнього справжнього ребуту Солдата — код `diag[7..5]` CCM-кадру (`ResetCause`). NULL —
# кадр поля не має (ECB-ера), тож колонка nullable і без дефолту: нуль тут уже означає
# «не повідомлено», а не «не було поля».
class AddResetCauseToTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :telemetry_logs, :reset_cause, :integer, limit: 2
  end
end
