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

  # [ARCH.59] Один Redis round-trip на батч, а не на кластер: `find_each` +
  # `perform_async` давав по RTT на кожен рядок, тобто N звертань на прогін.
  # Розмір батчу тримає стелю памʼяті там само, де її тримав `find_each`.
  BATCH_SIZE = 1_000

  def perform
    enqueued = 0
    Cluster.in_batches(of: BATCH_SIZE) do |batch|
      ids = batch.ids
      ClusterEntropyAnalyzerWorker.perform_bulk(ids.map { |id| [ id ] })
      enqueued += ids.size
    end
    Rails.logger.info "🎲 [Entropy Sweep] Поставлено #{enqueued} аналізів ентропії кластерів."
  end
end
