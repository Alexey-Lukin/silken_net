# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# ⚖️ [FW.66 (Б) · S8b] Конверт атестованого батча — доказ листа v2. Ідентичність тримає схема,
# запис ідемпотентний і чужого конверта не привласнює.
RSpec.describe QattEnvelope do
  let(:gateway) { create(:gateway) }
  let(:envelope) { [ 0x02 ].pack("C") + Random.bytes(16 + 16 + 64) }
  let(:public_key_hex) { "AB" * 32 }

  def record(gw = gateway)
    described_class.record!(envelope: envelope, gateway: gw, public_key_hex: public_key_hex, received_at: Time.current)
  end

  it "записує конверт раз і на ретраї віддає той самий sha256, не дублюючи рядок" do
    sha = record

    expect(record).to eq(sha)
    expect(sha).to eq(Digest::SHA256.digest(envelope))
    expect(described_class.count).to eq(1)
    expect(described_class.sole.public_key_hex).to eq("ab" * 32)
  end

  it "конверт, що вже належить іншій Королеві, не привласнює — рядки батча хешу не дістають" do
    record(create(:gateway))
    allow(Rails.logger).to receive(:error)

    expect(record).to be_nil
    expect(Rails.logger).to have_received(:error).with(/уже належить шлюзу/)
  end

  it "незмінний після запису" do
    record

    expect { described_class.sole.update!(received_at: 1.day.ago) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  describe "схема — навіть повз модель" do
    let(:row) do
      { gateway_id: gateway.id, gateway_uid: gateway.uid, envelope: envelope, received_at: Time.current,
        created_at: Time.current }
    end

    it "не дає записати ключ поруч із чужими байтами" do
      expect { described_class.insert(row.merge(sha256: Random.bytes(32), public_key_hex: "ab" * 32)) }
        .to raise_error(ActiveRecord::StatementInvalid, /qatt_envelopes_sha256_is_envelope_hash/)
    end

    it "не дає записати ключ не в нижньому hex" do
      expect { described_class.insert(row.merge(sha256: Digest::SHA256.digest(envelope), public_key_hex: "AB" * 32)) }
        .to raise_error(ActiveRecord::StatementInvalid, /qatt_envelopes_public_key_hex_shape/)
    end
  end

  it "шлюз зі збереженими конвертами не видаляється — доказ листа не зникає разом із ним" do
    record

    expect(gateway.destroy).to be(false)
    expect(gateway.errors[:base]).to be_present
  end
end
