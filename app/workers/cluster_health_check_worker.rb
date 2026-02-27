# frozen_string_literal: true

class ClusterHealthCheckWorker
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform
    Rails.logger.info "🕵️ [D-MRV] Початок перевірки здоров'я всіх активних контрактів..."

    NaasContract.status_active.find_each do |contract|
      contract.check_cluster_health!
    end
  end
end
