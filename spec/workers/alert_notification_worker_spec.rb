# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlertNotificationWorker, type: :worker do
  let(:organization) { create(:organization, billing_email: "billing@forest.org") }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster, latitude: 49.42, longitude: 32.06) }
  let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "enqueues SingleNotificationWorker for each admin/forester" do
      admin = create(:user, :admin, organization: organization)
      forester = create(:user, :forester, organization: organization)
      _investor = create(:user, :investor, organization: organization)

      described_class.new.perform(alert.id)

      # Push + Telegram for admin and forester, no jobs for investor.
      # [ARCH.78] SMS-джоб немає навіть для critical — канал відкинуто присудом.
      sms_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "sms" }
      push_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "push" }
      telegram_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "telegram" }

      expect(sms_jobs).to be_empty
      expect(push_jobs.size).to eq(2)
      expect(telegram_jobs.size).to eq(2)
    end

    it "uses Sidekiq::Client.push_bulk for batch enqueue (A-4 optimization)" do
      create(:user, :admin, organization: organization)
      create(:user, :forester, organization: organization)

      # Verify push_bulk is called with correct args count:
      # Critical alert → 2 Push + 2 Telegram (admin + forester) = 4 entries
      expect(Sidekiq::Client).to receive(:push_bulk).with(
        hash_including(
          "class" => SingleNotificationWorker,
          "args" => a_collection_containing_exactly(
            [ anything, alert.id, "push" ],
            [ anything, alert.id, "telegram" ],
            [ anything, alert.id, "push" ],
            [ anything, alert.id, "telegram" ]
          )
        )
      ).and_call_original

      described_class.new.perform(alert.id)
    end

    it "does not call push_bulk when no stakeholders exist" do
      expect(Sidekiq::Client).not_to receive(:push_bulk)

      described_class.new.perform(alert.id)
    end

    it "sends email for critical alerts with billing email" do
      mailer_double = double(deliver_later: true)
      notification_double = double(critical_notification: mailer_double)
      allow(AlertMailer).to receive(:with).and_return(notification_double)

      described_class.new.perform(alert.id)

      expect(AlertMailer).to have_received(:with).with(alert: alert)
    end

    it "does not send email for non-critical alerts" do
      medium_alert = create(:ews_alert, :drought, cluster: cluster, tree: tree)
      allow(AlertMailer).to receive(:with)

      described_class.new.perform(medium_alert.id)

      expect(AlertMailer).not_to have_received(:with)
    end

    # [UI.4-суміжне] Регресія живого бага: `EwsAlert.belongs_to :cluster, optional: true`,
    # а воркер енкʼюїться безумовно з `after_create_commit`. До гарда кожен безкластерний
    # алерт валив NoMethodError на `cluster.organization` → 5 ретраїв → morgue.
    it "skips a clusterless alert instead of raising" do
      clusterless = create(:ews_alert, :fire, cluster: nil, tree: nil)
      allow(Sidekiq::Client).to receive(:push_bulk)

      expect { described_class.new.perform(clusterless.id) }.not_to raise_error
      expect(Sidekiq::Client).not_to have_received(:push_bulk)
    end

    it "returns nil when alert not found" do
      expect(described_class.new.perform(-1)).to be_nil
    end
  end
end
