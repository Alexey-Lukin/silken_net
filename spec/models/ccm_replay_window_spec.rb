# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.40, ⚖️ founder 2026-10-05] Ковзне вікно анти-повтору CCM — RFC 4303 у Postgres.
RSpec.describe CcmReplayWindow, type: :model do
  let(:did) { "SNET-0000AC40" }
  let(:window) { described_class::WINDOW }

  def admit(fc, device_uid: did, key_epoch: 0)
    described_class.admit!(device_uid:, key_epoch:, frame_counter: fc)
  end

  def rejection(fc, device_uid: did, key_epoch: 0)
    described_class.rejection(device_uid:, key_epoch:, frame_counter: fc)
  end

  it "admits a frame once and rejects its exact repeat" do
    expect(admit(100)).to be(true)
    expect(rejection(100)).to eq(:duplicate)
    expect(admit(100)).to be(false)
  end

  # Бэклог кільця ARCH.35 приходить ПІСЛЯ живих кадрів — кадр під top_fc є нормою.
  it "admits ring backlog below the live top once, inside the window" do
    admit(500)
    expect(admit(450)).to be(true)
    expect(admit(450)).to be(false)
    expect(described_class.find_by(device_uid: did).top_fc).to eq(500)
  end

  it "rejects a frame at or beyond the window below the top as below_window" do
    admit(10_000)
    expect(rejection(10_000 - window)).to eq(:below_window)
    expect(admit(10_000 - window)).to be(false)
    expect(admit(10_000 - window + 1)).to be(true)
  end

  it "keeps no stale bits across a jump wider than the window" do
    admit(100)
    admit(100 + (2 * window))
    expect(rejection(100 + window + 1)).to be_nil
    expect(admit(100 + window + 1)).to be(true)
  end

  it "scopes the window per (DID, key epoch) — the same FC elsewhere is fresh" do
    admit(7)
    expect(admit(7, key_epoch: 1)).to be(true)
    expect(admit(7, device_uid: "SNET-0000AC41")).to be(true)
  end

  # Пре-фільтр мусить казати те саме, що авторитетний допуск, — інакше він або пускає
  # повтор до побічних ефектів кадру, або відкидає чесний кадр, який вікно прийняло б.
  # Еталон — пряма множина прийнятих FC із межею top − WINDOW.
  it "agrees with a reference model on a random sequence of live, backlog and repeated frames" do
    rng = Random.new(40)
    accepted = Set.new
    top = 0
    600.times do
      fc = case rng.rand(4)
      when 0 then top + 1 + rng.rand(3)                                # живий кадр
      when 1 then [ top - rng.rand(window + 200), 1 ].max               # бэклог або старий
      when 2 then accepted.to_a.sample(random: rng) || 1                # точний повтор
      else top + 1 + rng.rand(window * 2)                               # стрибок (cold start)
      end
      fresh = (top.zero? || fc > top || fc > top - window) && !accepted.include?(fc)
      expect(rejection(fc).nil?).to eq(fresh), "pre-filter FC #{fc} (top #{top})"
      expect(admit(fc)).to eq(fresh), "admit FC #{fc} (top #{top})"
      next unless fresh

      accepted << fc
      top = [ top, fc ].max
    end
  end

  # «Відкат БД мусить піднімати межу» — ончейн-мінти не відкочуються (06_06 §5.8).
  describe ".fence!" do
    let!(:tree) { create(:tree, did: did) }
    let(:fresh_tree) { create(:tree, did: "SNET-0000AC42") }

    before do
      create(:hardware_key, device_uid: tree.did, aes_key_hex: SecureRandom.hex(16).upcase)
    end

    it "raises the floor above the restored top, so frames sent after the backup point are rejected" do
      admit(300)
      expect(described_class.fence!(frames: 50)).to eq([ 1, 0 ])

      expect(rejection(301)).to eq(:below_window)
      expect(admit(350)).to be(false)
      expect(admit(351)).to be(true)
    end

    it "gives a current-epoch tree without a window a floor-only window" do
      create(:hardware_key, device_uid: fresh_tree.did, aes_key_hex: SecureRandom.hex(16).upcase)
      admit(300)

      expect(described_class.fence!(frames: 50)).to eq([ 1, 1 ])
      expect(admit(40, device_uid: fresh_tree.did)).to be(false)
      expect(admit(51, device_uid: fresh_tree.did)).to be(true)
    end

    it "refuses a non-positive margin" do
      expect { described_class.fence!(frames: 0) }.to raise_error(ArgumentError)
    end
  end
end
