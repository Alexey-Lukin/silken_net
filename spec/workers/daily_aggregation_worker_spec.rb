# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyAggregationWorker, type: :worker do
  before do
    allow(InsightGeneratorService).to receive(:call).and_return({ processed_count: 10 })
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "when aggregation produces results" do
      it "calls InsightGeneratorService with target date" do
        described_class.new.perform("2026-03-06")

        expect(InsightGeneratorService).to have_received(:call).with(Date.new(2026, 3, 6))
      end

      it "uses yesterday UTC when no date provided" do
        expected_date = Time.current.utc.to_date - 1

        described_class.new.perform

        expect(InsightGeneratorService).to have_received(:call).with(expected_date)
      end

      it "chains ClusterHealthCheckWorker when data exists" do
        described_class.new.perform("2026-03-06")

        expect(ClusterHealthCheckWorker.jobs.size).to eq(1)
        expect(ClusterHealthCheckWorker.jobs.first["args"]).to eq(["2026-03-06"])
      end
    end

    context "when no telemetry data available" do
      before do
        allow(InsightGeneratorService).to receive(:call).and_return({ processed_count: 0 })
      end

      it "does not chain ClusterHealthCheckWorker" do
        described_class.new.perform("2026-03-06")

        expect(ClusterHealthCheckWorker.jobs).to be_empty
      end

      it "creates EwsAlert for active clusters on weekdays" do
        org = create(:organization)
        cluster = create(:cluster, organization: org)
        create(:naas_contract, organization: org, cluster: cluster, status: :active)

        # Знаходимо найближчий робочий день
        weekday = Date.new(2026, 3, 6) # п'ятниця
        weekday += 1 until weekday.on_weekday?

        expect {
          described_class.new.perform(weekday.to_s)
        }.to change(EwsAlert, :count).by(1)

        alert = EwsAlert.last
        expect(alert.severity).to eq("critical")
        expect(alert.alert_type).to eq("system_fault")
        expect(alert.message).to include("БЛЕКАУТ")
      end

      it "does not create alerts on weekends" do
        org = create(:organization)
        cluster = create(:cluster, organization: org)
        create(:naas_contract, organization: org, cluster: cluster, status: :active)

        # Знаходимо найближчу суботу
        saturday = Date.new(2026, 3, 7) # субота
        saturday += 1 until saturday.saturday?

        expect {
          described_class.new.perform(saturday.to_s)
        }.not_to change(EwsAlert, :count)
      end
    end

    context "error handling" do
      it "handles invalid date format" do
        expect(Rails.logger).to receive(:error).with(/Невірний формат дати/)

        expect { described_class.new.perform("not-a-date") }.not_to raise_error
      end

      it "re-raises StandardError for Sidekiq retry" do
        allow(InsightGeneratorService).to receive(:call).and_raise(StandardError, "DB connection lost")

        expect {
          described_class.new.perform("2026-03-06")
        }.to raise_error(StandardError, "DB connection lost")
      end
    end
  end
end
