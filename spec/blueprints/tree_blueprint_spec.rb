# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TreeBlueprint, type: :model do
  before do
    silence_broadcasts!(:tree_map)
  end

  let(:tree_family) { create(:tree_family, name: "Quercus robur") }
  let(:cluster) { create(:cluster) }
  let(:tree) do
    create(:tree, tree_family: tree_family, cluster: cluster,
                  status: :active, latitude: 50.4501, longitude: 30.5234)
  end
  let(:wallet) { tree.wallet }

  describe ":minimal view" do
    subject(:parsed) { JSON.parse(described_class.render(tree, view: :minimal)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(tree.id)
    end

    it "includes did and status" do
      expect(parsed["did"]).to eq(tree.did)
      expect(parsed["status"]).to eq("active")
    end

    it "includes peaq_did" do
      expect(parsed).to have_key("peaq_did")
    end

    it "excludes fields from other views" do
      expect(parsed).not_to have_key("latitude")
      expect(parsed).not_to have_key("longitude")
      expect(parsed).not_to have_key("current_stress")
      expect(parsed).not_to have_key("wallet")
    end
  end

  describe ":index view" do
    subject(:parsed) { JSON.parse(described_class.render(tree, view: :index)) }

    it "includes location fields" do
      expect(parsed["latitude"]).to eq(tree.latitude.to_s)
      expect(parsed["longitude"]).to eq(tree.longitude.to_s)
    end

    it "includes did and status" do
      expect(parsed["did"]).to eq(tree.did)
      expect(parsed["status"]).to eq("active")
    end

    it "includes peaq_did in index view" do
      expect(parsed).to have_key("peaq_did")
    end

    it "includes last_seen_at" do
      expect(parsed).to have_key("last_seen_at")
    end

    it "carries the tree's actual current_stress" do
      tree.update_columns(latest_stress_index: 0.73)
      expect(parsed["current_stress"]).to eq(0.73)
    end

    # [TEST.10] Доти тут стояла лише перевірка типу, тож поле лишалось `false`
    # для дерева з непокритою тривогою і приклад цього не бачив. `under_threat?`
    # = ЛЮБА нерозвʼязана тривога дерева (на відміну від кластерного
    # `active_threats?`, який вимагає ще й critical).
    it "reports under_threat? false for a tree with no unresolved alert" do
      expect(parsed).to have_key("under_threat?")
      expect(parsed["under_threat?"]).to be(false)
    end

    it "reports under_threat? true once the tree carries an unresolved alert" do
      create(:ews_alert, :drought, tree: tree, cluster: cluster)
      expect(parsed["under_threat?"]).to be(true)
    end

    it "includes nested wallet" do
      wallet_data = parsed["wallet"]
      expect(wallet_data).to be_a(Hash)
      expect(wallet_data["id"]).to eq(wallet.id)
      expect(wallet_data["balance"]).to eq(wallet.balance.to_s)
    end

    it "includes tree_family_name" do
      expect(parsed["tree_family_name"]).to eq("Quercus robur")
    end

    # [ARCH.86] Приклада «excludes show-only fields» тут більше немає СВІДОМО:
    # його єдиним предметом було `baseline_impedance`, і після зняття осі
    # ексклюзивних полів у `:show` не лишилось жодного — `:index` є його
    # надмножиною плюс `latitude`/`longitude`.
  end

  describe ":show view" do
    subject(:parsed) { JSON.parse(described_class.render(tree, view: :show)) }

    it "includes did and status" do
      expect(parsed["did"]).to eq(tree.did)
      expect(parsed["status"]).to eq("active")
    end

    it "includes peaq_did in show view" do
      expect(parsed).to have_key("peaq_did")
    end

    it "includes last_seen_at" do
      expect(parsed).to have_key("last_seen_at")
    end

    # [TEST.10] Тут `:show` — і саме він показав, що клас закривають ПО
    # КОМПОНЕНТУ, а не по класу: обидва поля полагодили у `:index` view, а
    # ідентичні `have_key`-твердження за пʼятдесят рядків нижче лишились.
    it "carries the tree's actual current_stress" do
      tree.update_columns(latest_stress_index: 0.73)
      expect(parsed["current_stress"]).to eq(0.73)
    end

    it "carries under_threat? for a tree with no unresolved alert" do
      expect(parsed).to have_key("under_threat?")
      expect(parsed["under_threat?"]).to be(false)
    end

    it "includes nested wallet" do
      wallet_data = parsed["wallet"]
      expect(wallet_data).to be_a(Hash)
      expect(wallet_data["id"]).to eq(wallet.id)
    end

    it "includes tree_family_name" do
      expect(parsed["tree_family_name"]).to eq("Quercus robur")
    end
  end

  describe "nil tree_family edge case" do
    let(:tree_without_family) { create(:tree, cluster: cluster) }

    before do
      allow(tree_without_family).to receive(:tree_family).and_return(nil)
    end

    it "returns nil for tree_family_name in :index" do
      parsed = JSON.parse(described_class.render(tree_without_family, view: :index))
      expect(parsed["tree_family_name"]).to be_nil
    end

    # [ARCH.86] `:show` має власний `tree_family&.name`, і доти його nil-гілку
    # покривав лише побічно приклад про зняте поле — тобто поведінка була
    # перевірена ВИПАДКОВО. Пін тепер прямий.
    it "returns nil for tree_family_name in :show" do
      parsed = JSON.parse(described_class.render(tree_without_family, view: :show))
      expect(parsed["tree_family_name"]).to be_nil
    end
  end

  describe "collection rendering" do
    let!(:trees) { create_list(:tree, 3, tree_family: tree_family, cluster: cluster) }

    it "renders an array of trees" do
      parsed = JSON.parse(described_class.render(trees, view: :minimal))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      expect(parsed.map { |t| t["did"] }).to all(start_with("SNET-"))
    end
  end
end
