# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SILENCE-1] Dead-man switch Солдата: аномальна тиша → per-tree field_audit
# («слухай, не карай»), повернення в ефір → машинний resolve (gap-E);
# статус дерева недоторканний — dormant/removed/deceased лишаються людям.
RSpec.describe TreeStalenessSweepWorker, type: :worker do
  subject(:sweep) { described_class.new.perform }

  let(:cluster) { create(:cluster) }

  def silent_tree(silent_for: 25.hours)
    tree = create(:tree, cluster: cluster)
    tree.update_columns(last_seen_at: silent_for.ago)
    tree
  end

  describe "мовчазний вузол" do
    it "створює критичний per-tree field_audit, НЕ чіпаючи статус дерева" do
      tree = silent_tree

      expect { sweep }.to change { EwsAlert.alert_type_field_audit.count }.by(1)

      alert = EwsAlert.alert_type_field_audit.last
      expect(alert.tree_id).to eq(tree.id)
      expect(alert.cluster_id).to eq(cluster.id)
      expect(alert.severity_critical?).to be(true)
      expect(alert.message).to include(tree.did)
      expect(tree.reload.status).to eq("active") # «слухай, не карай» — жодного suspend
    end

    it "не дублює активну ескалацію того ж дерева (другий прохід)" do
      silent_tree
      sweep

      expect { described_class.new.perform }
        .not_to change { EwsAlert.alert_type_field_audit.count }
    end

    # Програна dedup-гонка (`escalate_field_audit!` → nil на RecordNotUnique/
    # RecordInvalid) НЕ рахується як флаг. Гонку двох одночасних проходів у
    # однопотоковому тесті не відтворити, тож пін іде по контракту колаборанта:
    # анти-джойн скоупу дерево пропустив, а створення все одно не відбулось.
    it "не лічить дерево флагнутим, коли ескалацію програно в гонці" do
      silent_tree
      allow(EwsAlert).to receive(:escalate_field_audit!).and_return(nil)

      expect(SilkenNet::Metrics::TREE_SILENCE_TOTAL).not_to receive(:increment)
      expect { sweep }.not_to change { EwsAlert.alert_type_field_audit.count }
    end

    # ⊥ dedup-скоупів (SILENCE-1 факт (2)) живе на рівні моделі — тест
    # «coexists in BOTH directions» в ews_alert_spec; ВОРКЕР же по темному
    # кластеру свідомо не ескалює (dark-cluster suppression нижче).
    it "пропускає легітимно-мовчазні статуси (dormant/removed/deceased)" do
      %i[dormant removed deceased].each do |status|
        tree = create(:tree, cluster: cluster)
        tree.update_columns(status: status, last_seen_at: 25.hours.ago)
      end

      expect { sweep }.not_to change { EwsAlert.alert_type_field_audit.count }
    end

    it "пропускає ніколи-не-бачених (last_seen_at nil — ще не народжений в ефірі)" do
      create(:tree, cluster: cluster, last_seen_at: nil)

      expect { sweep }.not_to change { EwsAlert.alert_type_field_audit.count }
    end

    it "не чіпає вузол у межах порога" do
      silent_tree(silent_for: 23.hours)

      expect { sweep }.not_to change { EwsAlert.alert_type_field_audit.count }
    end

    it "поріг живе у SystemParameter (48h → 25-годинна тиша ще легітимна)" do
      SystemParameter.set(:tree_silence_threshold_hours, 48,
                          value_type: "integer", category: "alerts")
      silent_tree(silent_for: 25.hours)

      expect { sweep }.not_to change { EwsAlert.alert_type_field_audit.count }
    end

    # Fail-safe: misconfig-значення тихо давало б threshold→0 → flag ВСЬОГО флоту.
    it "misconfig-поріг (non-numeric string) → fail-safe до дефолту 24h, НЕ 0" do
      SystemParameter.set(:tree_silence_threshold_hours, "garbage",
                          value_type: "string", category: "alerts")
      fresh = create(:tree, cluster: cluster)
      fresh.update_columns(last_seen_at: 1.hour.ago) # при threshold→0 флагнулось би
      silent_tree(silent_for: 25.hours)              # при дефолті 24h — флагається

      expect { sweep }.to change { EwsAlert.alert_type_field_audit.count }.by(1)
      expect(EwsAlert.alert_type_field_audit.last.tree_id).not_to eq(fresh.id)
    end
  end

  # Анти-шторм: gateway на кластер один, дерев — тисячі; Queen падає → через
  # поріг УВЕСЬ кластер «мовчазний» → без глушника N critical-алертів разом.
  describe "dark-cluster suppression (корельована тиша)" do
    it "активний queen_offline кластера глушить per-tree fan-out" do
      create(:ews_alert, cluster: cluster, tree: nil, severity: :critical,
                         alert_type: :queen_offline, status: :active)
      silent_tree

      expect { sweep }.not_to change { EwsAlert.alert_type_field_audit.count }
    end

    it "активний cluster-level field_audit (blackout) глушить per-tree fan-out" do
      EwsAlert.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")
      silent_tree

      expect { sweep }
        .not_to change { EwsAlert.alert_type_field_audit.where.not(tree_id: nil).count }
    end

    it "cluster-less дерево НЕ глушиться темним чужим кластером (NOT IN NULL-пастка)" do
      create(:ews_alert, cluster: cluster, tree: nil, severity: :critical,
                         alert_type: :queen_offline, status: :active)
      orphan = create(:tree, cluster: nil)
      orphan.update_columns(last_seen_at: 25.hours.ago)

      expect { sweep }.to change { EwsAlert.alert_type_field_audit.count }.by(1)
      expect(EwsAlert.alert_type_field_audit.last.tree_id).to eq(orphan.id)
    end
  end

  describe "повернення в ефір" do
    it "резолвить ескалацію машинно (resolved_by NULL — дискримінатор gap-E)" do
      tree = silent_tree
      sweep
      alert = EwsAlert.alert_type_field_audit.last

      tree.reload.mark_seen! # свіжий last_seen_at → тиша спростована
      described_class.new.perform

      expect(alert.reload.status_resolved?).to be(true)
      expect(alert.resolved_by).to be_nil
      expect(alert.resolution_log.last["key"]).to eq("tree_returned")
      expect(alert.resolution_texts.join).to include(tree.did)
    end

    it "НЕ резолвить cluster-level field_audit (tree_id nil — не наш сигнал)" do
      EwsAlert.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")
      tree = create(:tree, cluster: cluster)
      tree.mark_seen! # свіже дерево в кластері ≠ спростування blackout-ескалації

      described_class.new.perform

      expect(EwsAlert.alert_type_field_audit.where(tree_id: nil).first.status_active?).to be(true)
    end

    it "тримає ескалацію живою, доки вузол мовчить" do
      silent_tree
      sweep

      expect { described_class.new.perform }
        .not_to change { EwsAlert.status_resolved.count }
    end

    # Інакше критичний алерт висів би вічно: last_seen_at такого дерева
    # більше не оновиться, а escalate non-active не чіпає.
    it "резолвить ескалацію, коли флагнуте дерево покинуло active (removed)" do
      tree = silent_tree
      sweep
      alert = EwsAlert.alert_type_field_audit.last

      tree.update_columns(status: :removed) # людське рішення; slashing веде кейс
      described_class.new.perform

      expect(alert.reload.status_resolved?).to be(true)
      expect(alert.resolution_log.last["key"]).to eq("tree_left_active")
      expect(alert.resolution_log.last["params"]["status"]).to eq("removed")
      I18n.with_locale(:uk) do
        expect(alert.resolution_texts.join).to include("покинув active")
      end
      expect(alert.resolved_by).to be_nil
    end
  end

  describe "метрики" do
    it "ставить gauge флоту та інкрементить лічильник переходів" do
      silent_tree
      expect(SilkenNet::Metrics::TREE_SILENCE_TOTAL).to receive(:increment)
      expect(SilkenNet::Metrics::TREES_SILENT).to receive(:set).with(1)
      sweep
    end
  end
end
