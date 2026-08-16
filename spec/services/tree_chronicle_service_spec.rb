# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeChronicleService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }

  describe ".call" do
    context "with no events" do
      it "returns empty entries and valid pagy" do
        result = described_class.call(tree: tree)

        expect(result[:entries]).to be_empty
        expect(result[:pagy]).to respond_to(:page)
        expect(result[:pagy].count).to eq(0)
      end
    end

    context "with AiInsight events" do
      it "formats homeostasis events when stress_index < 0.2" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.1, reasoning: { "avg_z" => "24.3" })

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.event_type).to eq(:homeostasis)
        expect(entry.title).to eq("Deep Homeostasis")
        expect(entry.severity).to eq(:stable)
        expect(entry.source_type).to eq("AiInsight")
      end

      it "formats stress events when stress_index >= 0.3" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.5,
               reasoning: { "max_temp" => "42" })

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.event_type).to eq(:stress)
        expect(entry.severity).to eq(:warning)
      end

      it "formats critical stress events when stress_index >= 0.8" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.85)

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.severity).to eq(:critical)
      end

      it "formats fraud events" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, fraud_detected: true,
               reasoning: { "deviation_from_baseline" => "35" })

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.event_type).to eq(:fraud)
        expect(entry.severity).to eq(:critical)
        expect(entry.icon).to eq("\u26A0")
      end
    end

    context "with EwsAlert events" do
      it "formats alert events" do
        create(:ews_alert, tree: tree, cluster: cluster,
               alert_type: :fire_detected, severity: :critical,
               message_key: "hydrological_stress")

        result = described_class.call(tree: tree)
        alert_entry = result[:entries].find { |e| e.event_type == :alert }

        expect(alert_entry).to be_present
        expect(alert_entry.severity).to eq(:critical)
        expect(alert_entry.icon).to include("\u{1F525}")
      end

      it "includes recovery events for resolved alerts" do
        alert = create(:ews_alert, tree: tree, cluster: cluster,
                       alert_type: :severe_drought, severity: :medium,
                       message_key: "hydrological_stress")
        alert.update_columns(status: "resolved", resolved_at: Time.current,
                             resolution_notes: "Rain restored moisture")

        result = described_class.call(tree: tree)
        recovery_entry = result[:entries].find { |e| e.event_type == :recovery }

        expect(recovery_entry).to be_present
        expect(recovery_entry.title).to eq("Incident Resolved")
        expect(recovery_entry.severity).to eq(:stable)
      end

      # 🔴 Ітеруємо РЕАЛЬНІ значення enum'а, а не власний перелік: саме
      # розрив між ними й був дефектом — `EwsAlert` веде словник
      # `low/medium/critical`, а хроніка малює за `stable/info/warning/
      # critical`, тож `:medium` падав у той самий дефолт, що й `:stable`,
      # і тривога середньої тяжкості виглядала як «усе гаразд».
      # Нове значення в enum'і зробить цей приклад червоним — що й треба.
      describe "alert severity translation" do
        # Словник, який ЗНАЄ `Trees::Chronicle` — усе поза ним падає в його
        # дефолтну гілку, тобто малюється як «усе гаразд».
        let(:chronicle_vocabulary) { %i[stable info warning critical] }

        EwsAlert.severities.each_key do |alert_severity|
          it "maps EwsAlert severity #{alert_severity.inspect} into the chronicle vocabulary" do
            create(:ews_alert, tree: tree, cluster: cluster,
                   alert_type: :severe_drought, severity: alert_severity,
                   message_key: "hydrological_stress")

            entry = described_class.call(tree: tree)[:entries]
                                   .find { |e| e.source_type == "EwsAlert" }

            expect(chronicle_vocabulary).to include(entry.severity)
            # Негативна половина несуча: без неї приклад був би зеленим і
            # тоді, коли КОЖНА тяжкість мапиться в один і той самий колір.
            expect(entry.severity).not_to eq(:stable)
          end
        end
      end
    end

    context "with MaintenanceRecord events" do
      it "formats maintenance events" do
        user = create(:user, organization: organization)
        create(:maintenance_record, maintainable: tree, user: user,
               action_type: :inspection, performed_at: 1.day.ago)

        result = described_class.call(tree: tree)
        entry = result[:entries].find { |e| e.event_type == :maintenance }

        expect(entry).to be_present
        expect(entry.severity).to eq(:info)
        expect(entry.icon).to eq("\u2699")
      end
    end

    context "with BlockchainTransaction events" do
      it "formats confirmed minting events" do
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "a" * 40)
        create(:blockchain_transaction, wallet: wallet,
               status: :confirmed, token_type: :carbon_coin,
               confirmed_at: 1.day.ago, tx_hash: "0x" + SecureRandom.hex(32))

        result = described_class.call(tree: tree)
        entry = result[:entries].find { |e| e.event_type == :minting }

        expect(entry).to be_present
        expect(entry.icon).to eq("\u25C6")
      end

      # 🔴 [ARCH.101] Доти тут стояв захардкоджений `event_type: :minting` на КОЖЕН
      # рядок гаманця, тож слеш-інтент (`create_slash_intent!` пише його на той самий
      # гаманець дерева й доводить до `:confirmed`) з'являвся в хроніці як «Minted»
      # із зеленим success-бейджем — сторінка дерева свідчила про вилучення коштів
      # як про емісію. Пін тримає ВСІ ТРИ осі разом (тип · тон · іконка): напрямок,
      # що змінив лише підпис, лишив би дві третини брехні на екрані.
      it "derives a burn row as :burning across type, severity and icon" do
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "a" * 40)
        contract = create(:naas_contract, organization: tree.cluster.organization, cluster: tree.cluster)
        create(:blockchain_transaction, wallet: wallet, sourceable: contract,
               status: :confirmed, token_type: :carbon_coin,
               confirmed_at: 1.day.ago, tx_hash: "0x" + SecureRandom.hex(32))

        result = described_class.call(tree: tree)
        entry = result[:entries].find { |e| e.event_type == :burning }

        expect(entry).to be_present
        expect(entry.severity).to eq(:warning)
        expect(entry.icon).to eq("\u2B22")
        expect(entry.title).to include("Burned")
        expect(result[:entries].map(&:event_type)).not_to include(:minting)
      end
    end

    context "with pagination" do
      before do
        25.times do |i|
          create(:ai_insight, :daily_health_summary, analyzable: tree,
                 target_date: i.days.ago, stress_index: 0.1,
                 model_source: "test_#{i}")
        end
      end

      it "returns paginated results (default 20 per page)" do
        result = described_class.call(tree: tree, page: 1)

        expect(result[:entries].size).to eq(20)
        expect(result[:pagy].count).to eq(25)
        expect(result[:pagy].last).to eq(2)
      end

      it "returns second page" do
        result = described_class.call(tree: tree, page: 2)

        expect(result[:entries].size).to eq(5)
      end
    end

    context "with chronological ordering" do
      it "sorts entries by date descending (newest first)" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 3.days.ago, stress_index: 0.1, model_source: "old")
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.1, model_source: "new")

        result = described_class.call(tree: tree)
        dates = result[:entries].map(&:date)

        expect(dates).to eq(dates.sort.reverse)
      end
    end

    context "with no wallet" do
      it "returns empty blockchain entries when wallet is nil" do
        allow(tree).to receive(:wallet).and_return(nil)

        result = described_class.call(tree: tree)
        minting_entries = result[:entries].select { |e| e.event_type == :minting }
        expect(minting_entries).to be_empty
      end
    end

    context "with unresolved alerts" do
      it "does not include recovery entry for unresolved alert" do
        create(:ews_alert, tree: tree, cluster: cluster,
               alert_type: :severe_drought, severity: :medium,
               message_key: "hydrological_stress")

        result = described_class.call(tree: tree)
        recovery_entries = result[:entries].select { |e| e.event_type == :recovery }

        expect(recovery_entries).to be_empty
      end
    end

    context "with resolved alert but nil resolved_at" do
      it "does not include recovery entry when resolved_at is nil" do
        alert = create(:ews_alert, tree: tree, cluster: cluster,
                       alert_type: :severe_drought, severity: :medium,
                       message_key: "hydrological_stress")
        alert.update_columns(status: "resolved", resolved_at: nil)

        result = described_class.call(tree: tree)
        recovery_entries = result[:entries].select { |e| e.event_type == :recovery }

        expect(recovery_entries).to be_empty
      end
    end

    context "with BlockchainTransaction fallback date" do
      it "uses created_at when confirmed_at is nil" do
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "a" * 40)
        create(:blockchain_transaction, wallet: wallet,
               status: :confirmed, token_type: :carbon_coin,
               confirmed_at: nil, tx_hash: "0x" + SecureRandom.hex(32))

        result = described_class.call(tree: tree)
        minting_entry = result[:entries].find { |e| e.event_type == :minting }

        expect(minting_entry).to be_present
        expect(minting_entry.date).to be_present
      end
    end

    context "with stress_index boundary values" do
      it "formats homeostasis for stress_index 0.29 (below stress threshold)" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.29,
               reasoning: { "avg_z" => "24.3" })

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.event_type).to eq(:homeostasis)
        expect(entry.severity).to eq(:stable)
      end

      it "formats stress for stress_index exactly 0.3" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.3,
               reasoning: { "max_temp" => "42" })

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.event_type).to eq(:stress)
        expect(entry.severity).to eq(:warning)
      end

      it "formats stress with warning severity for stress_index 0.79" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.79)

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.severity).to eq(:warning)
      end

      it "formats stress with critical severity for stress_index exactly 0.8" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.8)

        result = described_class.call(tree: tree)
        entry = result[:entries].first

        expect(entry.severity).to eq(:critical)
      end
    end

    context "with pagination edge cases" do
      it "clamps page to 1 when page is 0" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.1)

        result = described_class.call(tree: tree, page: 0)
        expect(result[:entries]).not_to be_empty
        expect(result[:pagy].page).to eq(1)
      end

      it "clamps page to 1 when page is negative" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.1)

        result = described_class.call(tree: tree, page: -5)
        expect(result[:entries]).not_to be_empty
        expect(result[:pagy].page).to eq(1)
      end

      it "clamps per_page to 100 when exceeding maximum" do
        result = described_class.call(tree: tree, per_page: 200)
        # Should not raise, per_page clamped internally
        expect(result[:entries]).to be_an(Array)
      end

      it "clamps per_page to 1 when below minimum" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.1)
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 2.days.ago, stress_index: 0.1, model_source: "test2")

        result = described_class.call(tree: tree, per_page: 0)
        expect(result[:entries].size).to eq(1)
      end

      it "returns empty entries for page beyond total" do
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 1.day.ago, stress_index: 0.1)

        result = described_class.call(tree: tree, page: 999)
        expect(result[:entries]).to be_empty
      end
    end

    context "with mixed event sources" do
      it "collects entries from all four sources and sorts chronologically" do
        # Create one entry from each source
        create(:ai_insight, :daily_health_summary, analyzable: tree,
               target_date: 4.days.ago, stress_index: 0.1, model_source: "mixed_test")
        create(:ews_alert, tree: tree, cluster: cluster,
               alert_type: :fire_detected, severity: :critical,
               message_key: "hydrological_stress", created_at: 3.days.ago)
        user = create(:user, organization: organization)
        create(:maintenance_record, maintainable: tree, user: user,
               action_type: :inspection, performed_at: 2.days.ago)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x" + "b" * 40)
        create(:blockchain_transaction, wallet: wallet,
               status: :confirmed, token_type: :carbon_coin,
               confirmed_at: 1.day.ago, tx_hash: "0x" + SecureRandom.hex(32))

        result = described_class.call(tree: tree)

        event_types = result[:entries].map(&:event_type)
        expect(event_types).to include(:homeostasis, :alert, :maintenance, :minting)

        # Verify chronological order (newest first)
        dates = result[:entries].map(&:date)
        expect(dates).to eq(dates.sort.reverse)
      end
    end
  end
end
