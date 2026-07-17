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

    it "друга Королева кластера під активним алертом падає БЕЗ другого алерту (документована стеля guard'а)" do
      silent_gateway
      sweep # перша впала → queen_offline активний

      second = silent_gateway # той самий cluster, ще active і вже прострочена

      expect { described_class.new.perform }
        .not_to change { EwsAlert.alert_type_queen_offline.count }
      expect(second.reload.state).to eq("faulty")
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

    # [ARCH.34] Helium-SOS-алерт не мав резолвера ЖОДНОГО: HeliumSosWorker обіцяв
    # «sweeper-recovery після повернення батчів», але sweeper фільтрував лише
    # queen_offline → рядок лишався активним вічно й латчив comms_no_ack? назавжди.
    it "резолвить і queen_uplink_lost (Helium-SOS), не лише queen_offline" do
      gateway = silent_gateway
      sos = create(:ews_alert, cluster: cluster, severity: :critical,
                               alert_type: :queen_uplink_lost, status: :active)
      sweep

      gateway.reload.mark_seen! # свіжий last_seen_at → online
      described_class.new.perform

      expect(sos.reload.status_resolved?).to be(true)
    end

    # [SLASH-1 gap-E] Дискримінатор «машина vs людина» тримається на ДЕФОЛТНОМУ kwarg'у
    # resolve!(user: nil) — майбутній машинний resolve-сайт, що передасть system-user,
    # мовчки зламав би BlockchainBurningService#critical_unmaintained? (транзієнтна тиша
    # знову латчила б PF_NO_MAINTENANCE). Піна, щоб ламалось ГУЧНО, тут.
    it "лишає resolved_by NULL — машинний resolve мусить лишатись відрізнимим (gap-E)" do
      gateway = silent_gateway
      sweep
      alert = EwsAlert.alert_type_queen_offline.last

      gateway.reload.mark_seen!
      described_class.new.perform

      expect(alert.reload.resolved_by).to be_nil
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
