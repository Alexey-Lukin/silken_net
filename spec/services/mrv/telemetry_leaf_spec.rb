# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mrv::TelemetryLeaf do
  let(:tree) { create(:tree, did: "SNET-000DDF01") }
  let(:log) do
    create(:telemetry_log,
           tree: tree,
           z_value: BigDecimal("23.45"),
           bio_status: :stress,
           created_at: Time.utc(2026, 7, 19, 12, 0, 0))
  end

  describe ".payload_for — пінені скаляри" do
    subject(:payload) { described_class.payload_for(log) }

    it "device_uid = tree.did (Tree#device_uid не існує — канон-фікс E.60)" do
      expect(payload[:device_uid]).to eq("SNET-000DDF01")
    end

    it "z_value = plain fixed-point, НЕ scientific notation" do
      expect(payload[:z_value]).to eq("23.45")
    end

    it "bio_status = сирий integer з enum-мапи (rename-proof)" do
      expect(payload[:bio_status]).to eq(1)
    end

    it "created_at = utc.iso8601(6), µs-точність" do
      expect(payload[:created_at]).to eq("2026-07-19T12:00:00.000000Z")
    end

    it "NULL z_value → JSON null (рядок НЕ виключається з дерева)" do
      log.update_column(:z_value, nil)
      expect(described_class.payload_for(log.reload)[:z_value]).to be_nil
      expect(described_class.cid_for(log)).to start_with("bafkrei")
    end
  end

  describe ".cid_for — golden vector" do
    it "пінений CID канонічного payload'а (id=42, зміна = LEAF_VERSION bump)" do
      allow(log).to receive(:id).and_return(42)
      expect(described_class.cid_for(log))
        .to eq("bafkreidmzy5hnrcpiv4nwmpiw2ndz5lf6gqm5v5wjtpk5axykm5dhrmfo4")
    end
  end

  describe "Tree#did immutability (attr_readonly)" do
    it "переприсвоєння did після створення → raise (лист не «переїжджає»)" do
      expect { tree.did = "SNET-DEADBEEF" }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
    end
  end
end
