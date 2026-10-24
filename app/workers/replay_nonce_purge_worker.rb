# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.39, ⚖️ founder 2026-10-24] Прибиральник прострочених ключів анти-повтору (`ReplayNonce`).
# Коректність від нього не залежить: `claim!` перезахоплює прострочений ключ тим самим атомарним
# оператором. Він лише тримає таблицю малою — фолбеки QATT/M2M пишуть рядок на кожен батч і на
# кожен вхід, доки триває аварія Redis.
class ReplayNoncePurgeWorker
  include Sidekiq::Worker
  sidekiq_options queue: "low", retry: 1

  def perform
    purged = ReplayNonce.where(expires_at: ...Time.current).delete_all
    Rails.logger.info "🧹 [SEC.39] ReplayNonce: прибрано #{purged} прострочених ключів."
  end
end
