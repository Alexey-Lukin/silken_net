# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module SilkenNet
  module LoadTest
    # = ===================================================================
    # 🌱 Provisioning — тимчасовий realistic бенчмарк-кластер для drain-bench
    # = ===================================================================
    # red-team #6 / drain-cost TOP-2: порожня telemetry-історія = cold-cheapest
    # toy — `previous_lorenz_state_for` бачить 1 партицію, 0 рядків, і КОЖЕН
    # пакет іде найдешевшою cold-start гілкою. Тут: M дерев з distinct K_seed
    # під однією Королевою, ensure партиції (drain пише created_at=now), опційна
    # КРОС-ПАРТИЦІЙНА історія (warm continuation платить справжній MergeAppend),
    # teardown за тегом. Runtime-safe raw-AR — bin/coap_load поза RSpec, тож без
    # FactoryBot; дзеркалить db/seeds.rb.
    class Provisioning
      Result = Struct.new(:gateway, :trees, :cluster, :organization, :tag, keyword_init: true)

      # Високий DID-діапазон — не колізує з db:seed (SNET-00000001..64).
      DID_BASE = 0x0F00_0000

      class << self
        def provision(trees:, history_per_tree: 0, tag: SecureRandom.hex(4))
          raise ArgumentError, "trees має бути >= 1 (drain-каскад потребує дерев)" unless trees.positive?

          purge_leftover_trees! # crash-recovery: попередній прогін міг лишити DID-хвіст
          ensure_partitions!

          org, cluster, family = provision_context(tag)
          gateway = provision_gateway(cluster, tag)
          tree_records = Array.new(trees) { |i| provision_tree(cluster, family, i, history_per_tree) }

          Result.new(gateway: gateway, trees: tree_records, cluster: cluster, organization: org, tag: tag)
        end

        def teardown(result)
          # dependent: destroy на Tree → wallet + hardware_key + telemetry_logs + calibration.
          result.trees.each(&:destroy)
          ::HardwareKey.where(device_uid: result.gateway.uid).delete_all
          result.gateway.destroy
          result.cluster.destroy
          ::TreeFamily.where(name: "loadtest-family-#{result.tag}").delete_all
          result.organization.destroy
        end

        # Попередня+поточна+наступна партиція — усі три дає worker (його вікно й
        # накриває діапазон, у який пише `seed_history!` нижче). Спиратись на
        # календар `db/structure.sql` тут БІЛЬШЕ НЕ МОЖНА: дамп несе лише те, що
        # існувало на його момент, і разова прибирачка 2026-09-01 це показала.
        def ensure_partitions!
          PartitionMaintenanceWorker.new.perform
        end

        private

        def purge_leftover_trees!
          lo = format("SNET-%08X", DID_BASE)
          hi = format("SNET-%08X", DID_BASE + 1_000_000)
          ::Tree.where(did: lo..hi).find_each(&:destroy) # BETWEEN, не materialised IN
          ::HardwareKey.where(device_uid: lo..hi).delete_all
          ::Gateway.where(uid: format("SNET-Q-%08X", DID_BASE)).find_each(&:destroy)
          ::Cluster.where(region: "loadtest").find_each(&:destroy)
          ::TreeFamily.where("name LIKE ?", "loadtest-family-%").delete_all
          ::Organization.where("name LIKE ?", "loadtest-org-%").find_each(&:destroy)
        rescue StandardError => e
          Rails.logger.warn "[LoadTest::Provisioning] leftover purge skipped: #{e.message}"
        end

        def provision_context(tag)
          org = ::Organization.create!(
            name: "loadtest-org-#{tag}", billing_email: "loadtest-#{tag}@example.com",
            crypto_public_address: "0x#{SecureRandom.hex(20)}", hadron_kyc_status: "pending"
          )
          cluster = ::Cluster.create!(
            organization: org, name: "loadtest-cluster-#{tag}", region: "loadtest"
          )
          family = ::TreeFamily.create!(
            name: "loadtest-family-#{tag}",
            critical_z_min: 5.0, critical_z_max: 45.0
          )
          [ org, cluster, family ]
        end

        def provision_gateway(cluster, _tag)
          uid = format("SNET-Q-%08X", DID_BASE)
          gateway = ::Gateway.create!(
            uid: uid, ip_address: "127.0.0.1", latitude: 49.4, longitude: 32.0,
            cluster: cluster, config_sleep_interval_s: 3600,
            last_seen_at: Time.current, state: :active
          )
          # Queen-канал: AES-256 (32 байти) — цим ключем drain-bench шифрує батч.
          ::HardwareKey.create!(
            device_uid: uid,
            aes_key_hex: SecureRandom.hex(32).upcase,
            lorenz_seed_hex: SecureRandom.hex(32).upcase
          )
          gateway
        end

        def provision_tree(cluster, family, index, history)
          did = format("SNET-%08X", DID_BASE + 1 + index)
          tree = ::Tree.create!(
            did: did, latitude: 49.4, longitude: 32.0, cluster: cluster, tree_family: family
          )
          # Tree LoRa-канал AES-128 (16 байт); distinct K_seed → distinct Lorenz.
          # Wallet створюється Tree after_create (money-каскад drain'у не no-op).
          ::HardwareKey.create!(
            device_uid: did,
            aes_key_hex: SecureRandom.hex(16).upcase,
            lorenz_seed_hex: SecureRandom.hex(32).upcase
          )
          seed_history!(tree, history) if history.positive?
          tree
        end

        # Warm previous_lorenz_state: крос-партиційна історія так, щоб
        # `previous_lorenz_state_for` платив реальний MergeAppend (не cold-cheap).
        # 12-год кроки → count>60 розтягує рядки на попередній місяць.
        def seed_history!(tree, count)
          x0, y0, z0 = SilkenNet::SeedDerivation.initial_state(tree.hardware_key.binary_lorenz_seed)
          now = Time.current
          # Не заходимо за найранішу ГАРАНТОВАНУ партицію — prev-month, який створює
          # `ensure_partitions!` вище. ⚠️ Ціна виходу за неї НЕ «INSERT падає»: усі три
          # таблиці мають `_default`-лист, тож рядок тихо осідає ТУДИ, а після цього
          # `CREATE … PARTITION OF` того місяця падає `PG::CheckViolation` НАЗАВЖДИ
          # (переміряно 2026-08-28, `00_07` ARCH.70; рунбук `06_06 §5.5`).
          earliest = now.beginning_of_month - 1.month
          count.times do |k|
            ts = now - (k * 43_200) # 12-год кроки
            ts = earliest if ts < earliest
            tree.telemetry_logs.create!(
              created_at: ts,
              bio_status: :homeostasis, z_value: z0, growth_points: 18, voltage_mv: 4000,
              lorenz_state_x: x0, lorenz_state_y: y0, lorenz_state_z: z0
            )
          end
        end
      end
    end
  end
end
