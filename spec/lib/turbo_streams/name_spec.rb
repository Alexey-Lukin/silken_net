# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Дім імен стрімів. Піни тут навмисно на ЛІТЕРАЛИ, а не на переспів логіки
# модуля: очікування мусить бути НЕЗАЛЕЖНИМ твердженням про бажаний результат,
# інакше приклад — тавтологія, що не може впасти (`04_06` BP; та сама вада, що
# колись зробила mailer-спеку зеленою на `.humanize`-дефекті).
#
# 🔴 І головне, що ці літерали справді пінять: вони мусять бути БАЙТ-У-БАЙТ
# тими самими рядками, які пінять спеки продюсерів (`tree_spec:346`,
# `ews_alert_spec:714,754`, `unpack_telemetry_worker_spec:63`,
# `ota_transmission_worker_spec:66`, `pending_queue_service_spec`) і підписників
# (`telemetry_controller_spec:41`, `alerts_controller_spec:157`,
# `dashboard_controller_spec:105`, `firmwares_controller_spec:176`,
# `gateways_controller_spec`). Розбіжність тут = тихо мертвий тракт.
RSpec.describe TurboStreams::Name do
  describe ".org" do
    it "builds the telemetry stream name" do
      expect(described_class.org(:telemetry, 42)).to eq("telemetry_stream_org_42")
    end

    it "builds the alerts stream name" do
      expect(described_class.org(:alerts, 42)).to eq("ews_alerts_org_42")
    end

    it "builds the map stream name" do
      expect(described_class.org(:map, 42)).to eq("geospatial_matrix_org_42")
    end

    # Продюсери передають ЦІЛИЙ `organization_id` (у них уже є FK і зайвий SELECT
    # на firehose неприйнятний), підписники — обʼєкт. Дім мусить приймати обидва,
    # і давати ТЕ САМЕ імʼя, інакше сторони розійдуться саме тут.
    it "accepts a record and a bare id interchangeably" do
      org = instance_double(Organization, id: 42)

      expect(described_class.org(:telemetry, org)).to eq(described_class.org(:telemetry, 42))
    end

    # Описка в ключі не повинна народжувати тихий новий стрім.
    it "raises on an unknown kind instead of inventing a stream" do
      expect { described_class.org(:teIemetry, 42) }.to raise_error(KeyError)
    end

    # Гард fail-closed — і він ДОСЯЖНИЙ, тому тут пін, а не мертва гілка:
    # `..._org_` без id було б імʼям, спільним для всіх організацій.
    it "raises rather than mint an org-less name shared by every tenant" do
      expect { described_class.org(:telemetry, nil) }.to raise_error(ArgumentError, /спільним для всіх/)
      expect { described_class.org(:telemetry, instance_double(Organization, id: nil)) }
        .to raise_error(ArgumentError)
    end
  end

  describe ".gateway_ota" do
    it "builds the OTA channel name from the gateway uid" do
      expect(described_class.gateway_ota("SNET-Q-ABCD1234")).to eq("ota_channel_SNET-Q-ABCD1234")
    end

    it "accepts a gateway record and its bare uid interchangeably" do
      gateway = instance_double(Gateway, uid: "SNET-Q-ABCD1234")

      expect(described_class.gateway_ota(gateway)).to eq(described_class.gateway_ota("SNET-Q-ABCD1234"))
    end

    it "raises on a blank uid" do
      expect { described_class.gateway_ota(nil) }.to raise_error(ArgumentError, /uid/)
    end
  end
end
