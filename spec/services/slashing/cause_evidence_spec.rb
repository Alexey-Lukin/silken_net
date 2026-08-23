# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SLASH-1 §3.2] Positive-A-evidence — конкретно ЯКІ сигнали = доказ Категорії A.
# Фаза-1 свідомо КОНСЕРВАТИВНА: лише tamper (vandalism_breach). Force-majeure-типи
# (fire/drought) НЕ є доказом A → freeze (Категорія C), не burn.
# [SLASH-1 P0] vandalism_breach не має автоматичного writer'а (wire status=3 =
# vm_error → firmware_fault) — тут він створюється factory-напряму, що відповідає
# єдиному живому джерелу: ручній Field-Audit C→A ескалації (06_08 §4).
RSpec.describe Slashing::CauseEvidence do
  subject(:evidence) { described_class.new(cluster) }

  let(:cluster) { create(:cluster) }

  before do
    # Глушимо broadcast-колбеки EwsAlert (рендер/Turbo не потрібні в unit-спеці).
    silence_broadcasts!(:alert_new, :alert_notify)
  end

  describe "#positive_a?" do
    it "is TRUE for a critical, unresolved vandalism_breach (tamper) alert" do
      create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :vandalism_breach, status: :active)
      expect(evidence.positive_a?).to be(true)
    end

    it "is FALSE with no alerts (default safety → freeze, Category C)" do
      expect(evidence.positive_a?).to be(false)
    end

    # The whole point of the gate: a NATURAL event must never auto-burn.
    it "is FALSE for a force-majeure fire_detected alert" do
      create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :fire_detected, status: :active)
      expect(evidence.positive_a?).to be(false)
    end

    it "is FALSE for a severe_drought alert (force-majeure, not negligence)" do
      create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :severe_drought, status: :active)
      expect(evidence.positive_a?).to be(false)
    end

    # [SLASH-1 P0] Софт-збій прошивки (wire vm_error) — НЕ доказ вандалізму:
    # кластерний OTA-баг не сміє відкривати ворота необоротного slash.
    it "is FALSE for a firmware_fault alert (software fault ≠ tamper)" do
      create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :firmware_fault, status: :active)
      expect(evidence.positive_a?).to be(false)
    end

    it "is FALSE once the tamper alert is resolved (acknowledged → no longer live)" do
      create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :vandalism_breach, status: :resolved)
      expect(evidence.positive_a?).to be(false)
    end

    it "is FALSE for a non-critical vandalism_breach (severity below critical)" do
      create(:ews_alert, cluster: cluster, severity: :medium, alert_type: :vandalism_breach, status: :active)
      expect(evidence.positive_a?).to be(false)
    end
  end

  describe "#reason" do
    it "is :tamper when tamper evidence is present" do
      create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :vandalism_breach, status: :active)
      expect(evidence.reason).to eq(:tamper)
    end

    it "is nil when there is no Category-A evidence" do
      expect(evidence.reason).to be_nil
    end
  end
end
