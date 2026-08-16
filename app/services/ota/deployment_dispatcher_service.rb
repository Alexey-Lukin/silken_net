# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Ota
  # [SEC.20 Rails-half] Диспетчер OTA-кампанії: таргетує прошивку на шлюзи
  # організації через per-gateway `pending_firmware_id` — [FW.60] доставку
  # виконує сама Королева (poll-після-флашу → OTA-hint → chunk-server
  # `Downlink::PendingQueueService`), push-fan-out OtaTransmissionWorker
  # superseded (CGNAT-egress inbound-недосяжний).
  #
  # Anti-rollback: firmware.id мусить СТРОГО перевершити clusters.ota_version_hiwater
  # (Rails-дзеркало Солдатового інваріанта — той самий firmware.id їде в seg-4
  # HMAC-трейлера і палиться у Flash-KV 0x15 при APPLY, docs/03_06 §4).
  # Слот палиться при DISPATCH (свідомо суворіше за Soldier APPLY-time):
  # обірвана кампанія перевипускається НОВИМ записом прошивки, не re-issue.
  class DeploymentDispatcherService
    # [FW.60] Дзеркало Queen bitmap-стелі: OTA_MAX_CHUNKS=16 × 512 Б = 8 КБ
    # збірки (docs/03_02 §5 Guard 3). Понад — Queen мовчки дропає ch≥16 і
    # збірка зависає назавжди, тож відхиляємо кампанію ДО burn.
    QUEEN_MAX_BYTECODE_CHUNKS = 16

    SkippedCluster = Struct.new(:id, :name, :reason)
    Result = Struct.new(:dispatched_gateways, :skipped_clusters, keyword_init: true) do
      def dispatched? = dispatched_gateways.positive?
    end

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(firmware:, organization:, cluster_id: nil, canary_percentage: 100)
      @firmware = firmware
      @organization = organization
      @cluster_id = cluster_id
      @canary_percentage = canary_percentage.to_i.clamp(1, 100)
    end

    def call
      if (skipped = oversized_rejection)
        return Result.new(dispatched_gateways: 0, skipped_clusters: skipped)
      end

      cohort_uids, skipped = plan_and_burn_hiwater!

      # Оживлення read-live шва: TelemetryUnpackerService#latest_tree_firmware_id
      # читає .active — без активації check_firmware_mismatch! лишається no-op.
      @firmware.deploy_globally!(percentage: @canary_percentage) if cohort_uids.any?

      Result.new(dispatched_gateways: cohort_uids.size, skipped_clusters: skipped)
    end

    private

    # [FW.60] 16-чанк/8КБ-гейт: manifest дешевий (lazy-packages не
    # матеріалізуються), total_chunks = чисті bytecode-чанки 0x99 —
    # HMAC-трейлер 0x9B живе поза Queen-bitmap'ом і стелі не їсть.
    def oversized_rejection
      manifest = OtaPackagerService.prepare(
        @firmware, chunk_size: OtaTransmissionWorker::CHUNK_SIZE
      )[:manifest]
      return nil if manifest[:total_chunks] <= QUEEN_MAX_BYTECODE_CHUNKS

      target_clusters.map { |c| SkippedCluster.new(c.id, c.name, "oversized_firmware") }
    end

    # У одній транзакції: lock цільових кластерів → відсів rollback/порожніх →
    # canary-когорта per-cluster → hiwater-бамп + pending_firmware_id-таргет
    # ЛИШЕ кластерам з реальним диспатчем (атомарно: обірваний dispatch не
    # лишає когорту без таргета при спаленому hiwater).
    def plan_and_burn_hiwater!
      cohort_uids = []
      skipped = []

      Cluster.transaction do
        target_clusters.lock.order(:id).each do |cluster|
          if cluster.ota_version_hiwater >= @firmware.id
            skipped << SkippedCluster.new(cluster.id, cluster.name, "rollback")
            next
          end

          uids = canary_cohort_uids(cluster)
          if uids.empty?
            skipped << SkippedCluster.new(cluster.id, cluster.name, "no_gateways")
            next
          end

          cluster.update_column(:ota_version_hiwater, @firmware.id)
          # [FW.60] Канарейкова когорта персистується per-gateway: Королева
          # дізнається через OTA-hint на власному poll'і, не push'ем.
          # [ARCH.59] Якір ставиться ТУТ, а не на першому hint'і: доти між
          # таргетингом і анонсом шлюз ніс кампанію без жодної позначки часу й
          # без стану, тож sweep не бачив його за побудовою — а саме там живуть
          # keyless-таргет, Королева, що не поллить, і видалена прошивка.
          # `ota_started_at` = «відколи шлюз відповідає за цю кампанію»; poll
          # його НЕ перезаписує (`Downlink::PendingQueueService#ota_hint_payload`).
          cluster.gateways.where(uid: uids)
                 .update_all(pending_firmware_id: @firmware.id, ota_started_at: Time.current)
          cohort_uids.concat(uids)
        end
      end

      [ cohort_uids, skipped ]
    end

    def target_clusters
      scope = @organization.clusters
      @cluster_id ? scope.where(id: @cluster_id) : scope
    end

    # Canary = стабільна когорта: перші N% ota_deployable-шлюзів за id,
    # ceil (мінімум 1 шлюз на непорожній кластер).
    def canary_cohort_uids(cluster)
      uids = cluster.gateways.ota_deployable.order(:id).pluck(:uid)
      return uids if @canary_percentage == 100

      uids.first((uids.size * @canary_percentage / 100.0).ceil)
    end
  end
end
