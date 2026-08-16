# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeChronicle::TextFormatter do
  describe ".homeostasis_title" do
    it "returns the homeostasis title" do
      expect(described_class.homeostasis_title).to eq("Deep Homeostasis")
    end
  end

  describe ".homeostasis_description" do
    context "when avg_z is present" do
      let(:insight) { OpenStruct.new(avg_z: 29.4) }

      it "includes the Z-value" do
        result = described_class.homeostasis_description(insight)
        expect(result).to include("29.4")
        expect(result).to include("Z-value stable")
      end
    end

    context "when avg_z is nil" do
      let(:insight) { OpenStruct.new(avg_z: nil) }

      it "falls back to N/A" do
        result = described_class.homeostasis_description(insight)
        expect(result).to include("N/A")
        expect(result).to include("Z-value stable")
      end
    end
  end

  describe ".stress_title" do
    it "returns the stress title" do
      expect(described_class.stress_title).to eq("Elevated Stress Detected")
    end
  end

  describe ".stress_description" do
    context "when stress_index and max_temp are present" do
      let(:insight) { OpenStruct.new(stress_index: 0.753, max_temp: 42) }

      it "includes stress percentage and temperature" do
        result = described_class.stress_description(insight)
        expect(result).to include("75.3%")
        expect(result).to include("42°C")
        expect(result).to include("Recommendation: monitoring")
      end
    end

    # [ARCH.84] Доти цей приклад цементував дефект — і найгірше, що чесна
    # відповідь на те саме питання стояла ТРЬОМА рядками нижче («falls back to
    # N/A for temperature»). Пін цілиться у відбиток («Stress index: N/A.»), бо
    # голий `include("N/A")` пройшов би через сусідню температуру.
    context "when stress_index is nil" do
      let(:insight) { OpenStruct.new(stress_index: nil, max_temp: 38) }

      it "names the unmeasured state instead of a fabricated zero" do
        result = described_class.stress_description(insight)
        expect(result).to include("Stress index: N/A.")
        expect(result).not_to include("Stress index: 0")
      end
    end

    # ⊥ Ліхтар: нуль тут ДОСЯЖНИЙ — здорове дерево дає рівно `0.0`, тож без цієї
    # половини «не виміряно» не відрізнити від «виміряли, вийшов нуль».
    context "when stress_index is a measured zero" do
      let(:insight) { OpenStruct.new(stress_index: 0.0, max_temp: 21) }

      it "prints it as a number" do
        expect(described_class.stress_description(insight)).to include("Stress index: 0.0%.")
      end
    end

    context "when max_temp is nil" do
      let(:insight) { OpenStruct.new(stress_index: 0.5, max_temp: nil) }

      it "falls back to N/A for temperature" do
        result = described_class.stress_description(insight)
        expect(result).to include("N/A°C")
      end
    end
  end

  describe ".fraud_title" do
    it "returns the fraud title" do
      expect(described_class.fraud_title).to eq("AI Guard Anomaly")
    end
  end

  describe ".fraud_description" do
    context "when deviation_from_baseline is present" do
      # deviation_from_baseline — частка 0.0..1.0 (InsightGeneratorService#calculate_deviation);
      # раніше стаб був pre-scaled 47.2 і маскував рендер "0.35%" замість "35%".
      let(:insight) { OpenStruct.new(deviation_from_baseline: 0.472) }

      it "renders the deviation fraction as a percentage" do
        result = described_class.fraud_description(insight)
        expect(result).to include("47.2%")
        expect(result).to include("AI Guard detected anomaly")
      end
    end

    context "when deviation_from_baseline is nil" do
      let(:insight) { OpenStruct.new(deviation_from_baseline: nil) }

      it "falls back to N/A" do
        result = described_class.fraud_description(insight)
        expect(result).to include("N/A%")
      end
    end
  end

  describe ".alert_icon" do
    {
      "fire_detected"     => "🔥",
      "chainsaw_detected" => "🪚",
      "severe_drought"    => "💧",
      "insect_epidemic"   => "🐛",
      "vandalism_breach"  => "🚨",
      "seismic_anomaly"   => "🌍",
      "system_fault"      => "⚠",
      "field_audit"       => "🔍",
      "firmware_fault"    => "⚙"
    }.each do |alert_type, expected_icon|
      it "returns #{expected_icon} for #{alert_type}" do
        expect(described_class.alert_icon(alert_type)).to eq(expected_icon)
      end
    end

    it "returns ⚠ for unknown alert types" do
      expect(described_class.alert_icon("unknown_type")).to eq("⚠")
    end

    it "handles symbol input via to_s" do
      expect(described_class.alert_icon(:fire_detected)).to eq("🔥")
    end
  end

  describe ".alert_title" do
    {
      "fire_detected"     => "Fire Detected",
      "chainsaw_detected" => "Chainsaw Detected",
      "severe_drought"    => "Severe Drought",
      "insect_epidemic"   => "Insect Epidemic",
      "vandalism_breach"  => "Vandalism Breach",
      "seismic_anomaly"   => "Seismic Anomaly",
      "system_fault"      => "System Fault",
      "field_audit"       => "Field Audit",
      "firmware_fault"    => "Firmware Fault"
    }.each do |alert_type, expected_title|
      it "returns '#{expected_title}' for #{alert_type}" do
        alert = OpenStruct.new(alert_type: alert_type)
        expect(described_class.alert_title(alert)).to eq(expected_title)
      end
    end

    it "humanizes unknown alert types" do
      alert = OpenStruct.new(alert_type: "custom_alert")
      expect(described_class.alert_title(alert)).to eq("Custom alert")
    end
  end

  describe ".alert_description" do
    it "returns the alert message when present" do
      alert = OpenStruct.new(message: "Temperature exceeded 60°C")
      expect(described_class.alert_description(alert)).to eq("Temperature exceeded 60°C")
    end

    it "returns fallback text when message is nil" do
      alert = OpenStruct.new(message: nil)
      expect(described_class.alert_description(alert)).to eq("Alert triggered")
    end
  end

  describe ".recovery_title" do
    it "returns the recovery title" do
      expect(described_class.recovery_title).to eq("Incident Resolved")
    end
  end

  describe ".recovery_description" do
    context "with resolved_at and created_at" do
      let(:alert) do
        OpenStruct.new(
          resolved_at: Time.current,
          created_at: 3.days.ago,
          resolution_notes: nil
        )
      end

      it "includes the duration in days" do
        result = described_class.recovery_description(alert)
        expect(result).to include("Incident closed.")
        expect(result).to include("Duration: 3 days.")
      end
    end

    context "with resolved_at, created_at, and resolution_notes" do
      let(:alert) do
        OpenStruct.new(
          resolved_at: Time.current,
          created_at: 1.day.ago,
          resolution_notes: "Root cause identified"
        )
      end

      it "includes duration and notes" do
        result = described_class.recovery_description(alert)
        expect(result).to include("Duration: 1 day.")
        expect(result).to include("Root cause identified")
      end
    end

    context "without resolved_at" do
      let(:alert) do
        OpenStruct.new(
          resolved_at: nil,
          created_at: 2.days.ago,
          resolution_notes: nil
        )
      end

      it "omits duration" do
        result = described_class.recovery_description(alert)
        expect(result).to include("Incident closed.")
        expect(result).not_to include("Duration")
      end
    end

    context "without resolution_notes" do
      let(:alert) do
        OpenStruct.new(
          resolved_at: Time.current,
          created_at: 5.days.ago,
          resolution_notes: nil
        )
      end

      it "omits notes section" do
        result = described_class.recovery_description(alert)
        expect(result).not_to include("Root cause")
      end
    end
  end

  describe ".maintenance_title" do
    it "humanizes the action_type" do
      record = OpenStruct.new(action_type: "sensor_replacement")
      expect(described_class.maintenance_title(record)).to eq("Sensor replacement")
    end
  end

  describe ".maintenance_description" do
    context "with user and notes" do
      let(:record) do
        mock_user = OpenStruct.new(full_name: "Taras Shevchenko")
        OpenStruct.new(user: mock_user, notes: "Replaced ADC module")
      end

      it "includes technician name and notes" do
        result = described_class.maintenance_description(record)
        expect(result).to include("Technician Taras Shevchenko")
        expect(result).to include("Replaced ADC module")
      end
    end

    context "without user" do
      let(:record) do
        OpenStruct.new(user: nil, notes: "Routine check")
      end

      it "falls back to Unknown technician" do
        result = described_class.maintenance_description(record)
        expect(result).to include("Technician Unknown")
      end
    end

    context "without notes" do
      let(:record) do
        mock_user = OpenStruct.new(full_name: "Ivan Franko")
        OpenStruct.new(user: mock_user, notes: nil)
      end

      it "shows 'No notes' fallback" do
        result = described_class.maintenance_description(record)
        expect(result).to include("No notes")
      end
    end

    context "with empty notes" do
      let(:record) do
        mock_user = OpenStruct.new(full_name: "Ivan Franko")
        OpenStruct.new(user: mock_user, notes: "")
      end

      it "shows 'No notes' fallback for blank notes" do
        result = described_class.maintenance_description(record)
        expect(result).to include("No notes")
      end
    end

    context "with very long notes" do
      let(:record) do
        mock_user = OpenStruct.new(full_name: "Lesya Ukrainka")
        long_text = "A" * 200
        OpenStruct.new(user: mock_user, notes: long_text)
      end

      it "truncates notes to 120 characters" do
        result = described_class.maintenance_description(record)
        # truncate(120) adds "..." so total ≤ 120
        notes_part = result.split(": ", 2).last
        expect(notes_part.length).to be <= 120
      end
    end
  end

  describe ".minting_title" do
    it "humanizes the token_type" do
      tx = OpenStruct.new(token_type: "carbon_coin")
      expect(described_class.minting_title(tx)).to eq("Carbon coin Minted")
    end
  end

  describe ".minting_description" do
    # 🔴 [TEST.12 вісь ТИПУ] `amount` тут БУВ Integer, і обидва піни стерегли форму,
    # якої застосунок не виробляє жодного разу: колонка — `numeric(24,6)`, тож живий
    # запис віддає **BigDecimal**, і рядок виходить «Minted 5.0 tokens», а не
    # «Minted 5 tokens» (виміряно на persisted+reloaded записі). Єдиний виробник
    # (`TreeChronicleService#blockchain_entries`) бере лише збережені транзакції,
    # тож Integer сюди не приходить ніколи. Фікстура лишається `OpenStruct` свідомо
    # — це unit-спека форматера, від БД незалежна, — але ТИП мусить бути продовий.
    context "with blockchain_network" do
      let(:tx) { OpenStruct.new(amount: BigDecimal("5"), blockchain_network: "solana") }

      it "includes amount and capitalized network" do
        result = described_class.minting_description(tx)
        expect(result).to include("Minted 5.0 tokens")
        expect(result).to include("Solana")
        # [ARCH.53]: жодних oracle-verified claim'ів у юзер-хроніці — мінт оптимістичний (L0-custodial)
        expect(result).not_to include("Chainlink")
      end
    end

    # ⚠️ Вхід НЕДОСЯЖНИЙ на продовому шляху, і це оголошено, а не замовчано:
    # `blockchain_network` має DB-дефолт `evm` І `inclusion`-валідацію без
    # `allow_nil` (виміряно: запис із `nil` не валідний). Тобто фолбек `|| "Polygon"`
    # — ГАРД проти `nil.capitalize`, а не поведінка, яку колись побачить користувач.
    # Приклад лишено саме як пін гарда; знімати гілку не можна — вона ловить падіння.
    context "without blockchain_network (недосяжний вхід — пін ГАРДА)" do
      let(:tx) { OpenStruct.new(amount: BigDecimal("10"), blockchain_network: nil) }

      it "defaults to Polygon" do
        result = described_class.minting_description(tx)
        expect(result).to include("Polygon")
        expect(result).to include("Minted 10.0 tokens")
      end
    end
  end
end
