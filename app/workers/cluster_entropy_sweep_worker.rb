# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🎲 CLUSTER ENTROPY SWEEP (оркестратор) [S6.20]
# = ===================================================================
# Погодинний fan-out: ставить ClusterEntropyAnalyzerWorker на КОЖЕН кластер,
# щоб передстресовий детектор ентропії (EWS) реально працював.
#
# Аналізатор приймає cluster_id, але його ніхто не оркеструвало → gauge
# `silkennet_cluster_entropy_score` ніколи не оновлювався, а `entropy_anomaly`
# тривоги були мертві (doc-ahead-of-code, 04_02 §11). Цей воркер замикає розрив.
class ClusterEntropySweepWorker
  include Sidekiq::Job

  # Та сама черга, що й у аналізатора, який він драйвить (alerts = EWS, пріоритет 2).
  sidekiq_options queue: "alerts", retry: 3

  def perform
    enqueued = 0
    Cluster.find_each do |cluster|
      ClusterEntropyAnalyzerWorker.perform_async(cluster.id)
      enqueued += 1
    end
    Rails.logger.info "🎲 [Entropy Sweep] Поставлено #{enqueued} аналізів ентропії кластерів."
  end
end
