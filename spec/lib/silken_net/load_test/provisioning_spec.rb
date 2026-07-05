# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::LoadTest::Provisioning do
  it "provision-ить runnable кластер (Королева+дерева+ключі+гаманці+історія) і прибирає його" do
    result = described_class.provision(trees: 3, history_per_tree: 2)

    expect(result.trees.size).to eq(3)
    # Королева = AES-256 (32B) — цим ключем drain-bench шифрує батч.
    expect(result.gateway.hardware_key.binary_key.bytesize).to eq(32)

    result.trees.each do |tree|
      expect(tree.hardware_key.binary_lorenz_seed.bytesize).to eq(32) # distinct K_seed → Lorenz
      expect(tree.wallet).to be_present                               # money-каскад не no-op
      expect(tree.telemetry_logs.count).to eq(2)                      # warm previous_lorenz_state
    end

    tree_ids = result.trees.map(&:id)
    described_class.teardown(result)
    expect(::Tree.where(id: tree_ids)).to be_empty
    expect(::Gateway.where(id: result.gateway.id)).to be_empty
  end

  it "ensure-ить поточну+наступну місячну партицію (drain пише created_at=now)" do
    described_class.ensure_partitions!
    [ Time.current, 1.month.from_now ].each do |t|
      regclass = ActiveRecord::Base.connection.select_value(
        "SELECT to_regclass('public.telemetry_logs_#{t.strftime('y%Ym%m')}')"
      )
      expect(regclass).to be_present
    end
  end
end
