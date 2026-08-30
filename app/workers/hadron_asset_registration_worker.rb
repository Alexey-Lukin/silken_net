# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚠️ [BIZ.11] Воркер-сирота: НУЛЬ enqueue-сайтів у app/lib/config (переміряно
# 2026-08-25; сюїта смикає perform руками, тож інвентар читає його живим).
# Пускач = майбутній Hadron::TokenizeForestPlotService, і його свідомо НЕ
# будують до присудів UNI.16 (чи RWA-запис узагалі допустимий за Лісовим
# кодексом) + BIZ.22 (чи не є він ознакою інвестконтракту) — 00_07 BIZ.11.
# Не dead code: register_asset! лишається цільовим трактом RWA-реєстрації.
class HadronAssetRegistrationWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3_low", retry: 5

  def perform(naas_contract_id)
    naas_contract = NaasContract.find(naas_contract_id)

    with_web3_error_handling("Hadron", "NaaSContract ##{naas_contract_id}") do
      Polygon::HadronComplianceService.new.register_asset!(naas_contract)
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "🛡️ [Hadron] NaaSContract ##{naas_contract_id} not found, skipping"
  end
end
