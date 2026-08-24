# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe DclimateVerificationWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster) }

  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    silence_broadcasts!(:alert_notify, :alert_update, :alert_new)
    silence_side_effects!(:satellite_verification)
    allow(InsurancePayoutWorker).to receive(:perform_async)
    allow(BurnCarbonTokensWorker).to receive(:perform_async)
  end

  describe "sidekiq_options" do
    it "uses alerts queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("alerts")
    end

    it "retries 15 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(15)
    end
  end

  describe "#perform" do
    context "when alert exists and is unverified" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

      it "calls Dclimate::VerificationService" do
        service = instance_double(Dclimate::VerificationService)
        allow(Dclimate::VerificationService).to receive(:new).with(alert).and_return(service)
        allow(service).to receive(:perform)

        described_class.new.perform(alert.id)

        expect(service).to have_received(:perform)
      end
    end

    context "when alert does not exist" do
      it "returns nil without error" do
        expect(described_class.new.perform(-1)).to be_nil
      end
    end

    context "when alert is already verified" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :verified) }

      it "skips verification" do
        allow(Dclimate::VerificationService).to receive(:new)

        described_class.new.perform(alert.id)

        expect(Dclimate::VerificationService).not_to have_received(:new)
      end
    end

    context "when alert is already rejected_fraud" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :rejected_fraud) }

      it "skips verification" do
        allow(Dclimate::VerificationService).to receive(:new)

        described_class.new.perform(alert.id)

        expect(Dclimate::VerificationService).not_to have_received(:new)
      end
    end

    context "when alert is already inconclusive" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :inconclusive) }

      it "skips verification" do
        allow(Dclimate::VerificationService).to receive(:new)

        described_class.new.perform(alert.id)

        expect(Dclimate::VerificationService).not_to have_received(:new)
      end
    end
  end

  # -----------------------------------------------------------------------
  # Prometheus: цей воркер метрику алертів більше НЕ веде (INF.26)
  # -----------------------------------------------------------------------
  describe "Prometheus metrics" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

    # 🔴 [INF.26] Доти тут стояли ЧОТИРИ приклади, і головний із них цементував дефект
    # як норму: «increments EWS_ALERTS_TOTAL on successful verification» — тобто лічильник
    # з іменем «total EWS alerts» пінився на одній підмножині (супутниково верифіковані).
    # Решта три («does not increment …») після переносу дому стали б вакуумними: воркер
    # не торкається метрики за жодних умов. Вісь не знято, а ПЕРЕЦІЛЕНО — тут лишається
    # заборона повернути сайт назад, а справжній пін живе в `ews_alert_spec` (створення).
    it "does not touch EWS_ALERTS_TOTAL at all — the counter's home is the model callback" do
      service = instance_double(Dclimate::VerificationService)
      allow(Dclimate::VerificationService).to receive(:new).with(alert).and_return(service)
      allow(service).to receive(:perform).and_return(true)

      allow(SilkenNet::Metrics::EWS_ALERTS_TOTAL).to receive(:increment)

      described_class.new.perform(alert.id)

      expect(SilkenNet::Metrics::EWS_ALERTS_TOTAL).not_to have_received(:increment)
    end
  end

  describe ".sidekiq_retries_exhausted" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

    it "marks alert as inconclusive" do
      job = { "args" => [ alert.id ] }
      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      alert.reload
      expect(alert).to be_satellite_inconclusive
    end

    it "logs an orbital_exhausted resolution key" do
      job = { "args" => [ alert.id ] }
      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      alert.reload
      expect(alert.resolution_log.last["key"]).to eq("orbital_exhausted")
      expect(alert.resolution_texts.join).to include("Manual DAO audit required")
    end

    it "logs a warning" do
      job = { "args" => [ alert.id ] }
      allow(Rails.logger).to receive(:warn).with(/Cosmic Eye Exhausted/)

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      expect(Rails.logger).to have_received(:warn).with(/Cosmic Eye Exhausted/)
    end

    context "when alert does not exist" do
      it "does not raise error" do
        job = { "args" => [ -1 ] }
        expect { described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new) }.not_to raise_error
      end
    end

    context "when the alert already carries resolution entries" do
      it "appends a new entry instead of replacing the log" do
        alert.update!(resolution_log: [ { "text" => "Previous note" } ])

        job = { "args" => [ alert.id ] }
        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

        alert.reload
        expect(alert.satellite_status).to eq("inconclusive")
        expect(alert.resolution_texts.join).to include("Previous note")
        expect(alert.resolution_texts.join).to include("Manual DAO audit required")
      end
    end
  end
end
