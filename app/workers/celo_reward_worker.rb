# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class CeloRewardWorker
  include ApplicationWeb3Worker
  include Web3CircuitBreaker
  sidekiq_options queue: "web3", retry: 3

  def perform(cluster_id, target_date_string)
    cluster = Cluster.find_by(id: cluster_id)
    return Rails.logger.error "🛑 [Celo ReFi] Кластер ##{cluster_id} не знайдено." unless cluster

    target_date = Date.parse(target_date_string)

    with_circuit_breaker("celo_cusd") do
      with_web3_error_handling("Celo", "Cluster ##{cluster_id}") do
        Celo::CommunityRewardService.new(cluster, target_date).reward_community!
      end
    end
  rescue Web3CircuitBreaker::CircuitOpenError
    Rails.logger.warn "⚡ [Celo] Circuit OPEN — Cluster ##{cluster_id} буде повторено пізніше."
    raise
  rescue StandardError => e
    Rails.logger.error "🛑 [Celo ReFi] Помилка нагороди для кластера ##{cluster_id}: #{e.message}"
    raise
  end
end
