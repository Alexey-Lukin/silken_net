# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.60 · SEC.22] Дім ключа кешу між писачами з master-key і coap-читачем без нього.
RSpec.describe Ota::PackageStore do
  let(:cluster)  { create(:cluster) }
  let(:firmware) { create(:bio_contract_firmware, bytecode_payload: "AB" * 64) }

  before { Rails.cache.clear }

  it "reads nothing until a writer has warmed the campaign" do
    expect(described_class.read(firmware.id, cluster.id)).to be_nil
  end

  it "hands the reader exactly what the packager produced, per cluster" do
    warmed = described_class.warm!(firmware, cluster.id)

    expect(described_class.read(firmware.id, cluster.id)).to eq(warmed)
    expect(warmed).to eq(OtaPackagerService.prepare(firmware, chunk_size: OtaChunkable::CHUNK_SIZE,
                                                              cluster_id: cluster.id)[:packages].to_a)
    # Печатка ІНШОГО кластера — чужий ключ, тож і запис інший.
    expect(described_class.read(firmware.id, create(:cluster).id)).to be_nil
  end

  it "fails loudly in the writer when the process holds no master key" do
    allow(OtaSealKeyService).to receive(:signing_key_for)
      .and_raise(SecurityError, "PROVISIONING_MASTER_KEY ENV is required")

    expect { described_class.warm!(firmware, cluster.id) }.to raise_error(SecurityError)
    expect(described_class.read(firmware.id, cluster.id)).to be_nil
  end
end
