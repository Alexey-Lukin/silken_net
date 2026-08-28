# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.34 L3] Розбір 12B SOS-кадру + подвійна ідентичність (dev_eui ↔
# queen_did у кадрі) + EwsAlert(queen_uplink_lost) + report_fault!.
RSpec.describe HeliumSosWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:did)     { 0xA1B2C3D4 }
  let(:gateway) do
    create(:gateway, cluster: cluster, state: :active,
                     uid: format("SNET-Q-%08X", did),
                     helium_dev_eui: "AABBCCDDEEFF0011")
  end

  # SOS 12B: [did:4][vcap:2][err:1][uptime u24][flags:1][rsv:1]
  def sos_payload(queen_did: did, vcap: 11_800, err: 1, uptime_min: 5310, flags: 0)
    raw = [ queen_did, vcap, err,
            (uptime_min >> 16) & 0xFF, (uptime_min >> 8) & 0xFF, uptime_min & 0xFF,
            flags, 0 ].pack("N n C C3 C C")
    Base64.strict_encode64(raw)
  end

  it "створює критичний EwsAlert(queen_uplink_lost) і переводить шлюз у faulty" do
    expect {
      described_class.new.perform(gateway.helium_dev_eui, sos_payload)
    }.to change { EwsAlert.alert_type_queen_uplink_lost.count }.by(1)
      .and change { gateway.reload.state }.from("active").to("faulty")

    alert = EwsAlert.alert_type_queen_uplink_lost.last
    expect(alert.cluster_id).to eq(cluster.id)
    expect(alert.severity_critical?).to be(true)
    expect(alert.message).to include(gateway.uid, "starlink_down", "11800mV")
  end

  it "ідемпотентний: SOS-ретрансміт не плодить другий алерт" do
    described_class.new.perform(gateway.helium_dev_eui, sos_payload)

    expect {
      described_class.new.perform(gateway.helium_dev_eui, sos_payload)
    }.not_to change { EwsAlert.alert_type_queen_uplink_lost.count }
  end

  # 🔴 [ARCH.54] Ідемпотентність вище й це — РІЗНІ питання, і кластерний ключ
  # відповідав на обидва однаково «мовчи». Дедуп мусить глушити повтор ТІЄЇ САМОЇ
  # Королеви, а не крик СУСІДНЬОЇ: два SOS про два пристрої є двома свідченнями.
  it "друга Королева того ж кластера дістає ВЛАСНИЙ SOS-алерт (дедуп по uid)" do
    described_class.new.perform(gateway.helium_dev_eui, sos_payload)

    second_did = 0xB2C3D4E5
    second = create(:gateway, cluster: cluster, state: :active,
                              uid: format("SNET-Q-%08X", second_did),
                              helium_dev_eui: "AABBCCDDEEFF0022")

    expect {
      described_class.new.perform(second.helium_dev_eui, sos_payload(queen_did: second_did))
    }.to change { EwsAlert.alert_type_queen_uplink_lost.count }.by(1)

    # Пін на СКЛАД: «+1» задовольнив би й дубль про першу Королеву.
    uids = EwsAlert.alert_type_queen_uplink_lost.map { |a| a.message_params["uid"] }
    expect(uids).to contain_exactly(gateway.uid, second.uid)
  end

  it "не чіпає maintenance-шлюз (людина вже поруч), але алерт створює" do
    gateway.update!(state: :maintenance)

    expect {
      described_class.new.perform(gateway.helium_dev_eui, sos_payload)
    }.to change { EwsAlert.alert_type_queen_uplink_lost.count }.by(1)

    expect(gateway.reload.state).to eq("maintenance")
  end

  it "дропає незареєстрований dev_eui з метрикою (без алерту)" do
    allow(SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL).to receive(:increment)

    described_class.new.perform("0000000000000000", sos_payload)

    expect(EwsAlert.count).to eq(0)
    expect(SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL)
      .to have_received(:increment).with(labels: { outcome: "unknown_dev_eui" })
  end

  it "дропає DID-mismatch (спуф/misprovision) — dev_eui чужої Королеви" do
    allow(SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL).to receive(:increment)

    described_class.new.perform(gateway.helium_dev_eui,
                                sos_payload(queen_did: 0xDEADBEEF))

    expect(EwsAlert.count).to eq(0)
    expect(gateway.reload.state).to eq("active")
    expect(SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL)
      .to have_received(:increment).with(labels: { outcome: "did_mismatch" })
  end

  it "дропає короткий кадр (malformed)" do
    allow(SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL).to receive(:increment)

    described_class.new.perform(gateway.helium_dev_eui,
                                Base64.strict_encode64("short"))

    expect(EwsAlert.count).to eq(0)
    expect(SilkenNet::Metrics::HELIUM_SOS_RECEIVED_TOTAL)
      .to have_received(:increment).with(labels: { outcome: "malformed" })
  end

  it "дропає битий Base64 без крашу" do
    expect {
      described_class.new.perform(gateway.helium_dev_eui, "%%%not-base64%%%")
    }.not_to change(EwsAlert, :count)
  end

  it "розшифровує error-code у людську причину" do
    described_class.new.perform(gateway.helium_dev_eui, sos_payload(err: 4))
    expect(EwsAlert.last.message).to include("buffer_pressure")
  end

  it "вшиває reported_at Console'а у message (доказовий час крику)" do
    described_class.new.perform(gateway.helium_dev_eui, sos_payload, "1750000000000")
    expect(EwsAlert.last.message).to include("reported_at=1750000000000")
  end

  it "невідомий error-code віддає сирий code_N (майбутні прошивки)" do
    described_class.new.perform(gateway.helium_dev_eui, sos_payload(err: 9))
    expect(EwsAlert.last.message).to include("code_9")
  end
end
