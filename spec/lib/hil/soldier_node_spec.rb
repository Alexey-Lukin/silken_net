# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [E.64] НОСІЙ фіксу, без якого він повернеться. `bin/forest_simulator` — скрипт,
# спек у `bin/` не буває, тож модель вузла живе в `lib/hil` саме щоб мати цей файл.
#
# ⛔ Тут СВІДОМО не стабиться `SilkenNet::Attractor.calculate_z_from_state` — на відміну
# від сусідніх спек тракту, де пін у `[0.5, …]` робить асерти стабільними. Предмет цього
# файлу — що ДВА ланцюги (вузол ⊥ сервер) сходяться на СПРАВЖНІХ обчисленнях; під стабом
# приклад був би зелений і на `rand`-версії, тобто вимірював би мок.
RSpec.describe Hil::SoldierNode do
  let(:organization) { create(:organization) }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:tree_family)  { create(:tree_family) }
  let(:soldier)      { described_class.new }

  let!(:tree) do
    create(:tree, did: "SNET-0000ABCD", cluster: cluster, tree_family: tree_family).tap do |t|
      t.create_device_calibration! if t.device_calibration.nil?
      t.create_hardware_key!(
        device_uid: t.did,
        aes_key_hex: SecureRandom.hex(16).upcase,
        lorenz_seed_hex: SecureRandom.hex(32).upcase
      )
    end
  end
  # Сенсорні входи фіксовані (не rand) — предмет прикладу Lorenz-ланцюг, а не розкид.
  let(:sensors) { { temperature_c: 22, acoustic: 7, metabolism_s: 1800, voltage_mv: 3900 } }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
    allow(AlertDispatchService).to receive(:analyze_and_trigger!)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
    allow(IotexVerificationWorker).to receive(:perform_async)
    allow(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
  end


  def send_packet(reading)
    chunk = SilkenNet::LoadTest::TelemetryBatchFactory.chunk(
      did_int: tree.did.delete_prefix("SNET-").to_i(16),
      rssi: 60, voltage_mv: sensors[:voltage_mv], temperature_c: sensors[:temperature_c],
      acoustic: sensors[:acoustic], metabolism_s: sensors[:metabolism_s],
      growth_points: reading.growth_points, bio_status: reading.bio_status, ttl: 3
    )
    TelemetryUnpackerService.call(chunk)
  end

  describe "#read" do
    it "cold-starts from the tree's K_seed and then continues its OWN chain" do
      first  = soldier.read(tree, **sensors)
      second = soldier.read(tree, **sensors)

      expect(first.cold_start).to be(true)
      expect(second.cold_start).to be(false)
      # Той самий вхід із РІЗНОГО стану — різний Z. Рівність тут означала б, що
      # ланцюг не рухається, тобто «warm continuation» лише на словах.
      expect(second.z).not_to eq(first.z)
    end

    it "raises rather than inventing a state for an unprovisioned tree [SEC.11]" do
      bare = create(:tree, cluster: cluster, tree_family: tree_family)
      expect { soldier.read(bare, **sensors) }.to raise_error(described_class::MissingSeedError)
      expect(soldier.read(bare, **sensors, strict: false)).to be_nil
    end
  end

  describe "DCI acceptance (the whole point of E.64)" do
    it "emits packets the server accepts across a WARM chain — zero fraud increments" do
      3.times do
        reading = soldier.read(tree, **sensors)
        expect { send_packet(reading) }.to change(TelemetryLog, :count).by(1)
      end

      expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to have_received(:increment)
    end

    it "keeps the server's persisted tail in step with the node's own tail" do
      reading = soldier.read(tree, **sensors)
      send_packet(reading)

      log = TelemetryLog.last
      # Сервер округлює до 4 знаків при персисті `z_value`; хвіст — повний Float.
      expect(log.lorenz_state_z).to be_within(1e-9).of(reading.z)
      expect(log.cold_start_flag).to be(true)
    end

    # ⊥ ЛІХТАР. Без нього приклад вище зелений і на симуляторі, який ВГАДУЄ статус:
    # треба показати, що звірка справді дискримінує. Це відтворення точного дефекту,
    # який запалив критичний `Telemetry fraud detected` на canopy 2026-09-05.
    it "DOES flag a packet whose bio_status was GENERATED rather than computed" do
      reading = soldier.read(tree, **sensors)
      forged = Struct.new(:bio_status, :growth_points).new(
        (reading.bio_status + 1) % 3, # будь-який інший статус: заявлене ≠ обчислене
        reading.growth_points
      )

      send_packet(forged)

      # ДВІЧІ, і це пін на пару, а не на число: підробку ловлять ДВА незалежні
      # канали — `check_z_divergence!` (заявлений статус ≠ смуга серверного Z) і
      # `check_metabolic_divergence!` (GP=26 при `stress`, де прошивка пакує рівно 1).
      # Якщо котрийсь тихо перестане дискримінувати, приклад почервоніє — саме те,
      # чого не було, коли симулятор годував обидва канали випадковими числами.
      expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to have_received(:increment).twice
    end
  end
end
