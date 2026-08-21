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
    # 🔴 [E.33] Без цього рядка КОЖЕН приклад нижче вимірює світ, у якому живих
    # оперативних каналів НЕМА: `TELEGRAM_BOT_TOKEN` у тест-середовищі не заданий,
    # а `available?(:push)` — жорсткий `false`. Доти піни стверджували «2 push +
    # 2 telegram» саме в такому світі, тобто цементували енкʼю каналів, яких
    # платформа не має. Стабимо ТРАНСПОРТ, а не предикат: тоді приклад іде через
    # реальну диспетчеризацію `DeliveryChannels.available?`, і її зняття почервонить.
    allow(Notifications::TelegramTransport).to receive(:configured?).and_return(true)
  end

  describe "#perform" do
    it "enqueues SingleNotificationWorker for each admin/forester" do
      admin = create(:user, :admin, organization: organization)
      forester = create(:user, :forester, organization: organization)
      _investor = create(:user, :investor, organization: organization)

      described_class.new.perform(alert.id)

      # [ARCH.78] SMS-джоб немає навіть для critical — канал відкинуто присудом.
      # [E.33] Push-джоб немає, бо транспорту НЕМА: канал відсівається на вході
      # в чергу, а не після того, як джоба доїде до `logger.warn`.
      sms_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "sms" }
      push_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "push" }
      telegram_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "telegram" }

      expect(sms_jobs).to be_empty
      expect(push_jobs).to be_empty
      expect(telegram_jobs.size).to eq(2)
    end

    # [E.33] Дзеркальна половина: гейт читає ПРЕДИКАТ, а не зашитий перелік —
    # тож дротування FCM вмикає канал без правки воркера. Без цього прикладу
    # «push відсіяно» не відрізнити від «push видалили назавжди».
    it "enqueues a channel again once its transport appears" do
      create(:user, :admin, organization: organization)
      allow(Notifications::DeliveryChannels).to receive(:available?).and_call_original
      allow(Notifications::DeliveryChannels).to receive(:available?).with(:push).and_return(true)

      described_class.new.perform(alert.id)

      push_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "push" }
      expect(push_jobs.size).to eq(1)
    end

    it "uses Sidekiq::Client.push_bulk for batch enqueue (A-4 optimization)" do
      create(:user, :admin, organization: organization)
      create(:user, :forester, organization: organization)

      # Один живий канал × два стейкхолдери = 2 записи в ОДНОМУ push_bulk.
      expect(Sidekiq::Client).to receive(:push_bulk).with(
        hash_including(
          "class" => SingleNotificationWorker,
          "args" => a_collection_containing_exactly(
            [ anything, alert.id, "telegram" ],
            [ anything, alert.id, "telegram" ]
          )
        )
      ).and_call_original

      described_class.new.perform(alert.id)
    end

    it "does not call push_bulk when no stakeholders exist" do
      # ⚠️ Канал ЖИВИЙ (див. `before`) — інакше приклад проходив би з другої
      # причини й не розрізняв би «нема кому слати» від «нема чим слати».
      expect(Sidekiq::Client).not_to receive(:push_bulk)

      described_class.new.perform(alert.id)
    end

    # [E.33] Голос НУЛЮ: «каналів немає» ⊥ «стейкхолдерів немає» — два різні
    # світи, і мовчання злило б їх в один. Перший означає, що тривогу побачить
    # лише той, хто саме дивиться на дашборд.
    it "reports the silent world when no operational channel is live" do
      allow(Notifications::TelegramTransport).to receive(:configured?).and_return(false)
      create(:user, :admin, organization: organization)
      create(:user, :forester, organization: organization)
      allow(Rails.logger).to receive(:warn)

      expect(Sidekiq::Client).not_to receive(:push_bulk)
      described_class.new.perform(alert.id)

      expect(Rails.logger).to have_received(:warn).with(/Жодного оперативного каналу.*2 стейкхолдерів/)
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

    # 🔴 [ARCH.59] Вісь «стан судиться в момент ДОСТАВКИ, не постановки». Доти її
    # тримав лише `expires_in`, який на Sidekiq OSS не робить нічого — тобто
    # покриття не було взагалі, а не було слабким. Фікстура будує рівно той стан,
    # що виникає при затримці черги: алерт створено, стейкхолдери є, а до моменту
    # виконання його вже закрили.
    context "when the alert was resolved while the job sat in the queue" do
      it "does not enqueue any delivery" do
        create(:user, :admin, organization: organization)
        create(:user, :forester, organization: organization)
        alert.update!(status: :resolved)

        described_class.new.perform(alert.id)

        expect(SingleNotificationWorker.jobs).to be_empty
      end

      # Дзеркальна половина: без неї «нуль джоб» не відрізнити від «фікстура не
      # має кому слати». Той самий набір стейкхолдерів на АКТИВНОМУ алерті мусить
      # дати доставку — інакше приклад вище зелений вакуумно.
      it "still enqueues while the alert is active" do
        create(:user, :admin, organization: organization)
        create(:user, :forester, organization: organization)

        described_class.new.perform(alert.id)

        expect(SingleNotificationWorker.jobs).not_to be_empty
      end
    end
  end
end
