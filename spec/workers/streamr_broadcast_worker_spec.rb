# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamrBroadcastWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"c" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree) }

  before do
    silence_broadcasts!(:tree_map)
  end

  describe "#perform" do
    it "calls Streamr::BroadcasterService#broadcast!" do
      service = instance_double(Streamr::BroadcasterService)
      allow(Streamr::BroadcasterService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:broadcast!)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(service).to have_received(:broadcast!)
    end

    # [S6.16] Рівень підняли з warn до error разом із переходом на One-Home
    # `find_telemetry_log_with_pruning`: сам ПРОВАЛ трансляції лишається м'яким
    # (Streamr — потік присутності, не консенсус), але ВІДСУТНІЙ лог після
    # lookup'а без прунінгу — це вже аномалія цілісності, спільна для всіх трьох
    # воркерів тракту, тож і звучить вона однаково.
    it "logs an error when telemetry_log is not found" do
      expect(Rails.logger).to receive(:error).with(/не знайдено/)
      expect(Streamr::BroadcasterService).not_to receive(:new)

      described_class.new.perform(-1, Time.current.iso8601(6))
    end

    it "does not re-raise BroadcastError (graceful degradation)" do
      service = instance_double(Streamr::BroadcasterService)
      allow(Streamr::BroadcasterService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:broadcast!).and_raise(
        Streamr::BroadcasterService::BroadcastError, "Streamr node unreachable"
      )

      expect(Rails.logger).to receive(:error).with(/Streamr/)

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.not_to raise_error
    end

    it "uses low queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("low")
    end

    it "has retry set to 3" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end
  end
end
