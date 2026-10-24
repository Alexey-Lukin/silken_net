# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReplayNoncePurgeWorker do
  it "removes expired keys and keeps the live ones" do
    ReplayNonce.claim!(scope: "m2m_fallback", digest: "old", ttl: 10.minutes)
    ReplayNonce.claim!(scope: "m2m_fallback", digest: "live", ttl: 2.days)

    travel(1.day) { described_class.new.perform }

    expect(ReplayNonce.pluck(:digest)).to eq([ "live" ])
  end
end
