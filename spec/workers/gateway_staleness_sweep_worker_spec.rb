# frozen_string_literal: true

require "rails_helper"

# [ARCH.54 Шар 0] Dead-man switch Королеви: тиша → faulty + queen_offline,
# повернення в ефір → recover + resolve, attest-lapse — спостереження.
RSpec.describe GatewayStalenessSweepWorker, type: :worker do
  subject(:sweep) { described_class.new.perform }

  let(:cluster) { create(:cluster) }

  def silent_gateway(state: :active, silent_for: 10.minutes, sleep_s: 60)
    create(:gateway, cluster: cluster, state: state,
                     config_sleep_interval_s: sleep_s,
                     last_seen_at: silent_for.ago)
  end

  describe "мовчазний шлюз" do
    it "переводить у faulty і створює критичний EwsAlert(queen_offline)" do
      gateway = silent_gateway

      expect { sweep }.to change { gateway.reload.state }.from("active").to("faulty")
        .and change { EwsAlert.alert_type_queen_offline.count }.by(1)

      alert = EwsAlert.alert_type_queen_offline.last
      expect(alert.cluster_id).to eq(cluster.id)
      expect(alert.severity_critical?).to be(true)
      expect(alert.message).to include(gateway.uid)
    end

    it "не дублює активний алерт того ж кластера (анти-спам guard)" do
      silent_gateway
      sweep

      # Другий прохід: шлюз уже faulty (поза скоупом), алерт активний.
      expect { described_class.new.perform }
        .not_to change { EwsAlert.alert_type_queen_offline.count }
    end

    it "пропускає maintenance (людина вже знає)" do
      gateway = silent_gateway(state: :maintenance)
      expect { sweep }.not_to change { gateway.reload.state }
    end

    it "пропускає ніколи-не-бачених (last_seen_at nil — ще не народжений в ефірі)" do
      gateway = create(:gateway, cluster: cluster, state: :idle, last_seen_at: nil)
      expect { sweep }.not_to change { gateway.reload.state }
      expect(EwsAlert.alert_type_queen_offline.count).to eq(0)
    end

    it "не чіпає шлюз у межах sleep-інтервалу з люфтом" do
      gateway = create(:gateway, cluster: cluster, state: :active,
                                 config_sleep_interval_s: 3600,
                                 last_seen_at: 10.minutes.ago)
      expect { sweep }.not_to change { gateway.reload.state }
    end
  end

  describe "повернення в ефір" do
    it "recover'ить faulty-шлюз і резолвить queen_offline-алерт" do
      gateway = silent_gateway
      sweep
      alert = EwsAlert.alert_type_queen_offline.last

      gateway.reload.mark_seen! # свіжий last_seen_at → online
      expect { described_class.new.perform }
        .to change { gateway.reload.state }.from("faulty").to("idle")
      expect(alert.reload.status_resolved?).to be(true)
      expect(alert.resolution_notes).to include(gateway.uid)
    end
  end

  describe "метрики" do
    it "ставить gauge флоту та інкрементить лічильник переходів" do
      silent_gateway
      expect(SilkenNet::Metrics::GATEWAYS_OFFLINE_TOTAL).to receive(:increment)
      expect(SilkenNet::Metrics::GATEWAYS_FAULTY).to receive(:set).with(1)
      expect(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to receive(:set).with(0)
      sweep
    end
  end

  describe "attest-lapse (QATT-Королева без свіжого підпису)" do
    it "рахує online-шлюз з pubkey і простроченим last_attested_at" do
      gateway = create(:gateway, cluster: cluster, state: :active,
                                 config_sleep_interval_s: 3600,
                                 last_seen_at: 1.minute.ago,
                                 last_attested_at: 2.days.ago)
      create(:hardware_key, device_uid: gateway.uid,
                            ed25519_public_key_hex: "a" * 64)

      expect(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to receive(:set).with(1)
      allow(SilkenNet::Metrics::GATEWAYS_FAULTY).to receive(:set)
      sweep
    end

    it "рахує QATT-шлюз, що НІКОЛИ не атестувався (attested nil при pubkey)" do
      gateway = create(:gateway, cluster: cluster, state: :active,
                                 config_sleep_interval_s: 3600,
                                 last_seen_at: 1.minute.ago, last_attested_at: nil)
      create(:hardware_key, device_uid: gateway.uid,
                            ed25519_public_key_hex: "b" * 64)

      expect(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to receive(:set).with(1)
      allow(SilkenNet::Metrics::GATEWAYS_FAULTY).to receive(:set)
      sweep
    end

    it "не рахує L0-шлюз без pubkey" do
      create(:gateway, cluster: cluster, state: :active,
                       config_sleep_interval_s: 3600,
                       last_seen_at: 1.minute.ago, last_attested_at: nil)

      expect(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to receive(:set).with(0)
      allow(SilkenNet::Metrics::GATEWAYS_FAULTY).to receive(:set)
      sweep
    end
  end
end
