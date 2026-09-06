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
    # 🔴 [E.33 · ARCH.60] Доти тут стояв стаб `TelegramTransport.configured?` — єдиний
    # спосіб дати воркерові ЖИВИЙ канал, не стабуючи предикат. ⚫ Канал зрізано
    # ⚖️ 2026-09-06, і з ним пішла ця можливість: `available?(:push)` — жорсткий
    # `false`, `:email` має власний шлях повз фан-аут. **Оголошена деградація:**
    # відтепер КОЖЕН приклад, якому потрібен живий канал, стабить сам предикат
    # `DeliveryChannels.available?`, тобто реальну диспетчеризацію end-to-end уже
    # не проганяє НІХТО. Носій повернеться в день дротування FCM [ARCH.108] —
    # тоді стаб транспорту стане можливим знову, і цей коментар має піти.
  end

  describe "#perform" do
    it "enqueues SingleNotificationWorker for each admin/forester" do
      admin = create(:user, :admin, organization: organization)
      forester = create(:user, :forester, organization: organization)
      _subscriber = create(:user, :subscriber, organization: organization)
      # ⚫ Живий канал доводиться СТАБИТИ предикатом — див. `before`: після зняття
      # Telegram транспорту, який можна застабити, у платформи не лишилось.
      allow(Notifications::DeliveryChannels).to receive(:available?).and_call_original
      allow(Notifications::DeliveryChannels).to receive(:available?).with(:push).and_return(true)

      described_class.new.perform(alert.id)

      # [ARCH.78] SMS-джоб немає навіть для critical — канал відкинуто присудом.
      # [ARCH.60] Telegram-джоб немає — канал зрізано ⚖️ 2026-09-06.
      sms_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "sms" }
      telegram_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "telegram" }
      push_jobs = SingleNotificationWorker.jobs.select { |j| j["args"][2] == "push" }

      expect(sms_jobs).to be_empty
      expect(telegram_jobs).to be_empty
      expect(push_jobs.size).to eq(2)
      expect(push_jobs.map { |j| j["args"][0] }).to contain_exactly(admin.id, forester.id)
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
      allow(Notifications::DeliveryChannels).to receive(:available?).and_call_original
      allow(Notifications::DeliveryChannels).to receive(:available?).with(:push).and_return(true)
      allow(Sidekiq::Client).to receive(:push_bulk).and_call_original

      described_class.new.perform(alert.id)

      expect(Sidekiq::Client).to have_received(:push_bulk).with(
        hash_including(
          "class" => SingleNotificationWorker,
          "args" => a_collection_containing_exactly(
            [ anything, alert.id, "push" ],
            [ anything, alert.id, "push" ]
          )
        )
      )
    end

    it "does not call push_bulk when no stakeholders exist" do
      # ⚠️ Канал мусить бути ЖИВИЙ — інакше приклад проходить із ДРУГОЇ причини
      # й перестає розрізняти «нема кому слати» від «нема чим слати», тобто рівно
      # те, заради чого існує.
      # 🔴 Саме це й сталося 2026-09-06: зняття Telegram [ARCH.60] забрало стаб
      # транспорту з `before`, приклад лишився ЗЕЛЕНИМ і почав доводити інше.
      # Мовчазно — бо зелений колір однаковий в обох світах. Спіймала не сюїта,
      # а ПІДЛОГА ПОКРИТТЯ: гілка `push_bulk … if bulk_args.any?` перестала
      # виконуватись, і група Workers просіла нижче 99%. Тепер передумова стоїть
      # У ПРИКЛАДІ, а не в успадкованому `before`, який може змінитись під ним.
      allow(Notifications::DeliveryChannels).to receive(:available?).and_call_original
      allow(Notifications::DeliveryChannels).to receive(:available?).with(:push).and_return(true)
      allow(Sidekiq::Client).to receive(:push_bulk)

      described_class.new.perform(alert.id)

      expect(Sidekiq::Client).not_to have_received(:push_bulk)
    end

    # [E.33] Голос НУЛЮ: «каналів немає» ⊥ «стейкхолдерів немає» — два різні
    # світи, і мовчання злило б їх в один. Перший означає, що тривогу побачить
    # лише той, хто саме дивиться на дашборд.
    it "reports the silent world when no operational channel is live" do
      # ⚫ Стабити нічого не треба: після зняття Telegram [ARCH.60] набір
      # оперативних каналів порожній ЗА ЗАДУМОМ — саме тому й рівень `info`.
      create(:user, :admin, organization: organization)
      create(:user, :forester, organization: organization)
      allow(Rails.logger).to receive(:info)

      allow(Sidekiq::Client).to receive(:push_bulk)

      described_class.new.perform(alert.id)

      expect(Sidekiq::Client).not_to have_received(:push_bulk)
      expect(Rails.logger).to have_received(:info).with(/Оперативних каналів немає ЗА ЗАДУМОМ.*2 стейкхолдерів/)
    end

    it "sends email for critical alerts with billing email" do
      mailer_double = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
      notification_double = double(critical_notification: mailer_double) # rubocop:disable RSpec/VerifiedDoubles -- проксі від `.with(...)` віддає ActionMailer::Parameterized::Mailer, а той не ВИЗНАЧАЄ mailer-методів (method_missing) — verifying double їх не бачить за побудовою; звірено `public_method_defined?`
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
        allow(Notifications::DeliveryChannels).to receive(:available?).and_call_original
        allow(Notifications::DeliveryChannels).to receive(:available?).with(:push).and_return(true)

        described_class.new.perform(alert.id)

        expect(SingleNotificationWorker.jobs).not_to be_empty
      end
    end
  end
end
