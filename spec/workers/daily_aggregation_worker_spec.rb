# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyAggregationWorker, type: :worker do
  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "when telemetry data exists" do
      before do
        tree = create(:tree, status: :active)
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: Date.new(2026, 3, 6).beginning_of_day + 12.hours)
      end

      it "enqueues InsightGeneratorOrchestratorWorker with target date" do
        described_class.new.perform("2026-03-06")

        expect(InsightGeneratorOrchestratorWorker.jobs.size).to eq(1)
        expect(InsightGeneratorOrchestratorWorker.jobs.first["args"]).to eq([ "2026-03-06" ])
      end

      it "uses yesterday UTC when no date provided" do
        # Створюємо лог за вчора
        tree = create(:tree, status: :active)
        yesterday = Time.current.utc.to_date - 1
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: yesterday.beginning_of_day + 12.hours)

        described_class.new.perform

        expect(InsightGeneratorOrchestratorWorker.jobs.size).to eq(1)
        expect(InsightGeneratorOrchestratorWorker.jobs.first["args"]).to eq([ yesterday.to_s ])
      end

      it "does not directly chain ClusterHealthCheckWorker (handled by batch callback)" do
        described_class.new.perform("2026-03-06")

        expect(ClusterHealthCheckWorker.jobs).to be_empty
      end
    end

    context "when no telemetry data available" do
      it "does not enqueue InsightGeneratorOrchestratorWorker" do
        described_class.new.perform("2026-03-06")

        expect(InsightGeneratorOrchestratorWorker.jobs).to be_empty
      end

      # [SLASH-1 gap-D] Тип НЕСУЧИЙ, не косметика: :system_fault сидить і в
      # comms_no_ack?-whitelist, і поза critical_unmaintained?-blacklist, тож
      # fleet-wide force-majeure накручував би penalty_factor обома гілками —
      # рівно те, що 05_05 §6 забороняє («карати лісника за вкрадений шлюз»).
      it "escalates a Field Audit (NOT :system_fault) for active clusters on weekdays" do
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
        expect(alert.alert_type).to eq("field_audit")
        I18n.with_locale(:uk) { expect(alert.message).to include("БЛЕКАУТ") }
      end

      # Багатоденний блекаут (Starlink лежить тиждень) не плодить рядок щодоби —
      # дедуп дає escalate_field_audit! (раніше був голий create! без guard'а).
      it "does not pile duplicate escalations across a multi-day blackout" do
        org = create(:organization)
        cluster = create(:cluster, organization: org)
        create(:naas_contract, organization: org, cluster: cluster, status: :active)

        # ОБИДВА дні мусять бути робочими — інакше 2-й прогін мовчки виходить по
        # on_weekday?-гілці й тест проходить, нічого не перевіривши.
        day1 = Date.new(2026, 3, 6)
        day1 += 1 until day1.on_weekday?
        day2 = day1 + 1
        day2 += 1 until day2.on_weekday?

        described_class.new.perform(day1.to_s)

        expect {
          described_class.new.perform(day2.to_s)
        }.not_to change(EwsAlert, :count)
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

    context "when error handling" do
      it "handles invalid date format" do
        allow(Rails.logger).to receive(:error).with(/Невірний формат дати/)

        expect { described_class.new.perform("not-a-date") }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Невірний формат дати/)
      end

      # [OPS.19] Пін на ДЕТАЛЬ, а не на факт логування: сусідній приклад вище
      # зелений і тоді, коли виняток не біндиться взагалі (`rescue Date::Error`
      # без `=> e`) — саме так дефект і прожив. Тут дві незалежні вимоги:
      # повідомлення винятку доїхало, і аргумент названо ЯВНО (`nil` на cron-шляху
      # мусить читатись як «аргументу не було», а не як порожній рядок).
      it "carries the exception detail AND names the argument explicitly" do
        allow(Rails.logger).to receive(:error)

        described_class.new.perform("not-a-date")

        expect(Rails.logger).to have_received(:error).with(/invalid date/)
        expect(Rails.logger).to have_received(:error).with(/"not-a-date"/)
      end

      it "re-raises StandardError for Sidekiq retry" do
        allow(TelemetryLog).to receive(:where).and_raise(StandardError, "DB connection lost")

        expect {
          described_class.new.perform("2026-03-06")
        }.to raise_error(StandardError, "DB connection lost")
      end
    end
  end
end
