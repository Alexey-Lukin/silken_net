# frozen_string_literal: true

class CeloRewardWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 3

  def perform(cluster_id, target_date_string)
    cluster = Cluster.find_by(id: cluster_id)
    return Rails.logger.error "🛑 [Celo ReFi] Кластер ##{cluster_id} не знайдено." unless cluster

    target_date = Date.parse(target_date_string)

    Celo::CommunityRewardService.new(cluster, target_date).reward_community!
  rescue StandardError => e
    Rails.logger.error "🛑 [Celo ReFi] Помилка нагороди для кластера ##{cluster_id}: #{e.message}"
    raise e
  end
end
