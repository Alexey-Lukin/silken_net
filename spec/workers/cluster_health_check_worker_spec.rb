# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClusterHealthCheckWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let!(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }

  before do
    silence_side_effects!(:cluster_health_recalc)
    silence_side_effects!(:naas_health_check)
  end

  describe "#perform" do
    it "processes all active NaaS contracts without errors" do
      expect { described_class.new.perform }.not_to raise_error
    end

    # 🔴 [SLASH-1] Денормалізований `active_trees_count` годує ЗНАМЕННИК тригера слешингу
    # (поріг `> N × slash_fraction` І межу виродження `N < 1/slash_fraction`), а тримають
    # його `Tree`-колбеки — тож `update_all`/`update_columns` їх обходять. Розмір спалення
    # з цієї залежності знято [⚖️ 2026-07-30], тригер лишався сліпим. Звірка їде в проході,
    # що вже обходить кластери, — нуль воркерів, нуль розкладу.
    describe "active_trees_count drift audit" do
      it "stays silent while the counter matches the live COUNT" do
        create(:tree, cluster: cluster)
        allow(Rails.logger).to receive(:error)

        described_class.new.perform

        expect(Rails.logger).not_to have_received(:error).with(/SLASH-1 drift/)
      end

      # Мутація писача — рівно та форма, що обходить колбеки й через яку клас існує.
      it "names the cluster when the counter drifted from the live COUNT" do
        create(:tree, cluster: cluster)
        Cluster.where(id: cluster.id).update_all(active_trees_count: 99)
        allow(Rails.logger).to receive(:error)

        described_class.new.perform

        expect(Rails.logger).to have_received(:error).with(/SLASH-1 drift.*##{cluster.id}/)
      end

      # 🔴 Прилад не сміє валити добовий аудит контрактів: звірка — спостережність,
      # а навколо неї йде вирок про гроші. Без цього гарду збій метрики (Redis/registry)
      # зупиняв би перевірку ВСІХ наступних кластерів.
      it "never lets a broken probe abort the contract audit" do
        create(:tree, cluster: cluster)
        Cluster.where(id: cluster.id).update_all(active_trees_count: 99)
        allow(SilkenNet::Metrics::CLUSTER_TREE_COUNT_DRIFT).to receive(:set).and_raise(StandardError, "registry down")
        allow(Rails.logger).to receive(:warn)

        expect { described_class.new.perform }.not_to raise_error

        expect(Rails.logger).to have_received(:warn).with(/SLASH-1 drift.*не вдалась/)
      end
    end

    it "passes date_string to NaasContract health check" do
      date = "2026-03-06"

      expect { described_class.new.perform(date) }.not_to raise_error
    end

    # 🔴 [ARCH.100] Регрес. Доти цей приклад звався «handles nil date_string gracefully» і
    # стверджував лише `not_to raise_error` — тобто НІЧОГО: саме nil-гілка й несла дефект,
    # а єдиний пін на дату стеріг протилежну, явну гілку (нижче). Дефолтна доба мусить бути
    # тією, якою інсайти ЗАПИСАНО, а не «вчора» в поясі кластера.
    #
    # ⚠️ Час заморожено НАВМИСНО: дві дати розходяться лише у вікні `UTC-година < |offset|`,
    # тож на живому годиннику цей пін дві третини доби був би зеленим на зламаному коді.
    context "with no date_string (the nightly cron path)" do
      let(:cluster) do
        create(:cluster, organization: organization,
                         environmental_settings: { "timezone" => "America/Manaus" })
      end

      it "anchors both consumers on the reporting date, not the cluster's local yesterday" do
        travel_to(Time.utc(2026, 8, 13, 2, 0, 0)) do
          expected = AiInsight.reporting_date
          stale = Time.use_zone("America/Manaus") { Date.yesterday }
          expect(stale).not_to eq(expected) # ліхтар: інакше приклад стереже порожнечу

          expect_any_instance_of(Cluster).to receive(:recalculate_health_index!).with(expected)
          expect_any_instance_of(NaasContract).to receive(:check_cluster_health!).with(expected)

          described_class.new.perform(nil)
        end
      end
    end

    it "continues processing when a single contract errors" do
      contract2 = create(:naas_contract, organization: organization, cluster: cluster, status: :active)

      call_count = 0
      allow_any_instance_of(NaasContract).to receive(:check_cluster_health!) do
        call_count += 1
        raise "DB Error" if call_count == 1
      end

      expect { described_class.new.perform }.not_to raise_error
    end

    it "logs flagged (degraded) contracts" do
      allow_any_instance_of(NaasContract).to receive(:check_cluster_health!).and_return(:degraded)

      allow(Rails.logger).to receive(:warn).with(/ФЛАГОВАНО/)

      described_class.new.perform

      expect(Rails.logger).to have_received(:warn).with(/ФЛАГОВАНО/).at_least(:once)
    end

    context "with explicit date_string parameter" do
      it "parses the date_string and passes it to health check" do
        date_string = "2026-06-15"
        expected_date = Date.parse(date_string)

        expect_any_instance_of(Cluster).to receive(:recalculate_health_index!).with(expected_date)
        expect_any_instance_of(NaasContract).to receive(:check_cluster_health!).with(expected_date)

        described_class.new.perform(date_string)
      end
    end

    context "when branching on the health verdict (SLASH-1)" do
      before { allow(CeloRewardWorker).to receive(:perform_async) }

      it "counts a flagged (:degraded) contract and does NOT reward it" do
        allow_any_instance_of(NaasContract).to receive(:check_cluster_health!).and_return(:degraded)
        allow(Rails.logger).to receive(:info).and_call_original
        allow(Rails.logger).to receive(:warn).and_call_original

        described_class.new.perform

        expect(Rails.logger).to have_received(:warn).with(/ФЛАГОВАНО/).at_least(:once)
        expect(Rails.logger).to have_received(:info).with(/Флаговано: 1/)
        expect(CeloRewardWorker).not_to have_received(:perform_async)
      end

      it "rewards a :healthy cluster via CeloRewardWorker" do
        allow_any_instance_of(NaasContract).to receive(:check_cluster_health!).and_return(:healthy)

        described_class.new.perform

        expect(CeloRewardWorker).to have_received(:perform_async).with(cluster.id, anything)
      end

      it "does NOT reward a :blackout cluster (force-majeure under audit)" do
        allow_any_instance_of(NaasContract).to receive(:check_cluster_health!).and_return(:blackout)

        described_class.new.perform

        expect(CeloRewardWorker).not_to have_received(:perform_async)
      end
    end

    # [INS.1 / ARCH.59] Fan-out страхового оракула переїхав сюди з мертвого
    # Batch-колбека — цей воркер має власний cron, тож ланка дістала пускача.
    context "with the insurance oracle fan-out (gated)" do
      let!(:insurance) do
        create(:parametric_insurance, organization: organization, cluster: cluster, status: :active)
      end

      def flag!(enabled)
        allow(SystemParameter).to receive(:current).and_call_original
        allow(SystemParameter).to receive(:current)
          .with(:parametric_insurance_oracle_enabled, default: false).and_return(enabled)
      end

      it "enqueues InsuranceOracleWorker per active-insurance cluster when the flag is on" do
        flag!(true)

        expect { described_class.new.perform("2026-03-06") }
          .to change { InsuranceOracleWorker.jobs.size }.by(1)

        expect(InsuranceOracleWorker.jobs.first["args"]).to eq([ cluster.id, "2026-03-06" ])
      end

      it "does NOT enqueue the insurance oracle when the flag is off (default)" do
        expect { described_class.new.perform("2026-03-06") }
          .not_to change { InsuranceOracleWorker.jobs.size }
      end

      # 🔴 Доба fan-out'у мусить бути ТІЄЮ, якою судився контракт — інакше оракул
      # оцінює іншу добу, ніж аудит, і порожня вибірка читається як «даних немає»
      # [ARCH.100]. На cron-шляху (без аргументу) якір — `AiInsight.reporting_date`.
      it "passes the audit's own reporting date on the cron path" do
        flag!(true)

        described_class.new.perform

        expect(InsuranceOracleWorker.jobs.first["args"])
          .to eq([ cluster.id, AiInsight.reporting_date.to_s ])
      end
    end
  end
end
