# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Single tree end-to-end flow" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
  end

  describe "tree with cluster" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "creates a wallet on tree creation" do
      expect(tree.wallet).to be_present
      expect(tree.wallet.balance).to eq(0)
      expect(tree.wallet.organization).to eq(organization)
    end

    it "creates a device calibration on tree creation" do
      expect(tree.device_calibration).to be_present
    end

    it "tracks voltage and last_seen_at" do
      expect(tree.last_seen_at).to be_nil
      tree.mark_seen!(3500)
      expect(tree.last_seen_at).to be_present
      expect(tree.latest_voltage_mv).to eq(3500)
    end

    # [ARCH.99] Доти тут два приклади рахували «відсоток заряду» й «низьке
    # живлення» від 4150/3000 мВ — напружень, яких стабілізована шина не дає
    # (`02_03 §7`). Величину знято; наскрізний енергосигнал тепер — тиша.
    it "reads node energy end-to-end as silence, not as a level" do
      tree.update_columns(latest_voltage_mv: 3300, last_seen_at: Time.current)
      expect(tree.supply_voltage_mv).to eq(3300)
      expect(tree).to be_fresh_signal

      tree.update_columns(last_seen_at: (Tree::SILENCE_THRESHOLD + 1.hour).ago)
      expect(tree).not_to be_fresh_signal
      expect(Tree.silent).to include(tree)
    end
  end

  # ⚠️ [⚖️ 2026-07-30] Назва «standalone installation» БІЛЬШЕ НЕ описує продуктовий
  # сценарій: одиноке дерево (B2C) отримує ВЛАСНИЙ кластер із одного дерева, а не NULL —
  # інакше воно не провіжниться взагалі (`K_ota` деривується з `cluster_id`). Блок
  # лишається регресійним захистом nil-гардів на ще-nullable колонці; читати його як
  # модель B2C не можна.
  describe "clusterless tree (nil-guard regression, NOT the B2C model)" do
    let!(:tree) { create(:tree, cluster: nil, tree_family: tree_family) }

    it "creates a wallet without organization" do
      expect(tree.wallet).to be_present
      expect(tree.wallet.organization).to be_nil
    end

    it "still tracks voltage" do
      tree.mark_seen!(4000)
      expect(tree.latest_voltage_mv).to eq(4000)
    end
  end
end
