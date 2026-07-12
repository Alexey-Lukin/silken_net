# frozen_string_literal: true

module Ota
  # [SEC.20 Rails-half] Диспетчер OTA-кампанії: розгортає прошивку на шлюзи
  # організації через fan-out per-gateway OtaTransmissionWorker.
  #
  # Anti-rollback: firmware.id мусить СТРОГО перевершити clusters.ota_version_hiwater
  # (Rails-дзеркало Солдатового інваріанта — той самий firmware.id їде в seg-4
  # HMAC-трейлера і палиться у Flash-KV 0x15 при APPLY, docs/03_06 §4).
  # Слот палиться при DISPATCH (свідомо суворіше за Soldier APPLY-time):
  # обірвана кампанія перевипускається НОВИМ записом прошивки, не re-issue.
  class DeploymentDispatcherService
    # Воркерова гілка BioContractFirmware у fetch_firmware_record.
    FIRMWARE_TYPE = "firmware"

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
      cohort_uids, skipped = plan_and_burn_hiwater!

      # Стеля (свідома): інфра-збій нижче (Redis-down посеред enqueue,
      # DB-збій активації) лишає hiwater спаленим — це БЕЗПЕЧНА сторона
      # (частково-полетілу кампанію відкочувати не можна); recovery = новий
      # запис прошивки. TOCTOU до воркерового state=:updating закривається
      # ARCH.59 ota_started_at-механікою.
      cohort_uids.each do |uid|
        OtaTransmissionWorker.perform_async(uid, FIRMWARE_TYPE, @firmware.id, 0, 0)
      end
      # Оживлення read-live шва: TelemetryUnpackerService#latest_tree_firmware_id
      # читає .active — без активації check_firmware_mismatch! лишається no-op.
      @firmware.deploy_globally!(percentage: @canary_percentage) if cohort_uids.any?

      Result.new(dispatched_gateways: cohort_uids.size, skipped_clusters: skipped)
    end

    private

    # У одній транзакції: lock цільових кластерів → відсів rollback/порожніх →
    # canary-когорта per-cluster → hiwater-бамп ЛИШЕ кластерам з реальним диспатчем.
    # Enqueue — після commit (щоб job не стартував поперед бампа).
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
