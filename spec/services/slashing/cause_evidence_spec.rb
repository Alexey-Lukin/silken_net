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
  subject(:evidence) { described_class.new(cluster, contract: contract) }

  let(:cluster) { create(:cluster) }
  let(:contract) { create(:naas_contract, cluster: cluster, organization: cluster.organization, start_date: 1.month.ago) }

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

    it "is FALSE once the tamper alert is resolved (withdrawn by the platform → no longer live)" do
      create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :vandalism_breach, status: :resolved)
      expect(evidence.positive_a?).to be(false)
    end

    it "is FALSE for a non-critical vandalism_breach (severity below critical)" do
      create(:ews_alert, cluster: cluster, severity: :medium, alert_type: :vandalism_breach, status: :active)
      expect(evidence.positive_a?).to be(false)
    end

    # 🔒 [SLASH-1, ⚖️ делеговано 2026-09-22] Закривати доказ тепер може лише платформа, тож
    # відкритий доказ живе, доки його не закриють. Дві межі й строк дії — кожна пара нижче
    # взаємні мутації (без межі перший приклад пари червоніє, з перевернутою — другий).
    def evidence_at(time)
      create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :vandalism_breach,
                         status: :active, created_at: time)
    end

    it "is FALSE for evidence recorded BEFORE this contract started — the next contract does not burn on it" do
      evidence_at(contract.start_date - 1.day)
      expect(evidence.positive_a?).to be(false)
    end

    it "is TRUE for fresh evidence recorded while this contract is in force" do
      evidence_at(1.hour.ago)
      expect(evidence.positive_a?).to be(true)
    end

    # `fulfill` не має викликача, тож договір по `end_date` лишається `active` і дістає
    # тригери далі — верхня межа терміну мусить стояти в самих воротах.
    it "is FALSE for evidence recorded AFTER this contract's term ended, though it is still :active" do
      contract.update_columns(start_date: 20.days.ago, end_date: 2.days.ago)
      evidence_at(1.day.ago)
      expect(evidence.positive_a?).to be(false)
    end

    it "is FALSE when the contract is not in force (draft)" do
      contract.update_column(:status, NaasContract.statuses[:draft])
      evidence_at(1.hour.ago)
      expect(evidence.positive_a?).to be(false)
    end

    # Ворота не знають, ЯКИЙ інцидент довів доказ: без строку він відчиняв би слеш на
    # будь-якому пізнішому, не повʼязаному тригері.
    it "is FALSE once the evidence outlived its validity window" do
      evidence_at((Slashing::CauseEvidence::DEFAULT_EVIDENCE_VALIDITY_HOURS + 1).hours.ago)
      expect(evidence.positive_a?).to be(false)
    end

    it "reads the validity window from governance, not from the constant" do
      evidence_at(3.hours.ago)
      allow(SystemParameter).to receive(:current).and_call_original
      allow(SystemParameter).to receive(:current)
        .with(:slash_evidence_validity_hours, default: anything).and_return(2)
      expect(evidence.positive_a?).to be(false)
    end

    # Відсутня дата не сміє розчиняти межу: `(nil..)` в Arel — це «будь-коли».
    it "is FALSE (fail-closed) when the contract has no start date" do
      contract.update_column(:start_date, nil)
      evidence_at(1.hour.ago)
      expect(evidence.positive_a?).to be(false)
    end

    # Пропущений договір мусить падати, а не тихо обирати гілку без межі — на незворотних
    # воротах вона означала б «палити».
    it "cannot be asked without a contract" do
      expect { described_class.new(cluster) }.to raise_error(ArgumentError, /contract/)
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
