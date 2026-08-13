# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🛰️ DCLIMATE VERIFICATION WORKER (Cosmic Eye — Orbital Consensus)
# = ===================================================================
# Асинхронна верифікація EWS-алертів через супутникові дані dClimate.
# Використовує custom retry logic для моделювання орбітального вікна:
# - 15 ретраїв ≈ 48+ годин (Sidekiq exponential backoff)
# - Якщо всі ретраї вичерпані (хмарність >48 годин) → inconclusive → DAO audit
class DclimateVerificationWorker
  include Sidekiq::Job

  # Черга alerts має високий пріоритет — верифікація впливає на фінансові операції.
  # 15 ретраїв з exponential backoff ≈ 48+ годин орбітального вікна.
  sidekiq_options queue: "alerts", retry: 15

  # [48-HOUR ORBITAL WINDOW]: Якщо всі 15 ретраїв вичерпано (хмарність/кронопокрив
  # тривалістю >48 годин), маркуємо алерт як inconclusive для ручного DAO-аудиту.
  sidekiq_retries_exhausted do |job, _exception|
    alert = EwsAlert.find_by(id: job["args"].first)
    if alert
      audit_note = "Orbital verification failed due to prolonged canopy/cloud cover. Manual DAO audit required."
      existing_notes = alert.resolution_notes
      combined_notes = existing_notes.present? ? "#{existing_notes}\n[#{Time.current.iso8601}] #{audit_note}" : audit_note

      alert.update!(
        satellite_status: :inconclusive,
        resolution_notes: combined_notes
      )
      Rails.logger.warn "☁️ [Cosmic Eye Exhausted] Алерт ##{alert.id} — верифікація не вдалася після всіх спроб. " \
                        "Потрібен ручний DAO-аудит."
    end
  end

  def perform(alert_id)
    alert = EwsAlert.find_by(id: alert_id)
    return unless alert

    # Пропускаємо, якщо алерт вже верифіковано або відхилено
    return unless alert.satellite_unverified?

    Dclimate::VerificationService.new(alert).perform
    # [INF.26] Інкремент `EWS_ALERTS_TOTAL` знято звідси: метрика зветься «total EWS
    # alerts», а цей сайт лічив лише ті, що дійшли до супутникової верифікації Й
    # повернули результат — одна підмножина з тринадцяти сайтів створення. Дім переїхав
    # у `EwsAlert.after_create_commit`. ⚠️ Разом із ним зник ЄДИНИЙ числовий слід
    # супутникового результату; окремої метрики на нього не було ніколи → `00_07` INF.26.
  end
end
