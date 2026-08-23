# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe NaasContract, type: :model do
  before do
    silence_broadcasts!(:tree_map)
  end

  describe "#check_cluster_health!" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }
    let(:target_date) { Time.current.utc.to_date - 1 }

    context "when contract is not active" do
      it "returns early without checking" do
        contract.update_column(:status, described_class.statuses[:draft])
        expect { contract.check_cluster_health!(target_date) }.not_to change { contract.reload.status }
      end
    end

    context "when cluster has no active trees" do
      it "returns early" do
        expect { contract.check_cluster_health!(target_date) }.not_to change { contract.reload.status }
      end
    end

    # [SLASH-1] Cluster-wide blackout = gateway-fault / force-majeure signature,
    # NOT negligence → must NOT auto-burn (05_05 §6). Route to Field Audit.
    context "when Oracle is silent (no daily insights) — cluster-wide blackout" do
      it "does NOT slash (no breach, no burn)" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_active
        expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
      end

      it "raises a :field_audit escalation for the cluster (NOT :system_fault — gap-D)" do
        create(:tree, cluster: cluster, status: :active)
        cluster.reload

        expect { contract.check_cluster_health!(target_date) }
          .to change { EwsAlert.where(cluster: cluster, alert_type: :field_audit).count }.by(1)
      end
    end

    context "when health is within threshold" do
      it "does not trigger slashing" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        trees.each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.2)
        end

        cluster.reload
        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "when critical anomalies exceed 20% threshold" do
      it "routes to the chokepoint (:degraded) without pre-breaching [SLASH-1]" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        # 3 out of 10 trees with stress >= 1.0 (30% > 20% threshold)
        trees[0..2].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 1.0)
        end
        trees[3..9].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload

        expect(contract.check_cluster_health!(target_date)).to eq(:degraded)
        expect(contract.reload).to be_status_active # breach is async (chokepoint), not pre-set
      end
    end

    context "when critical anomalies are exactly at 20% threshold" do
      it "does not trigger slashing" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)

        # 2 out of 10 trees (20% = threshold, not exceeded)
        trees[0..1].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 1.0)
        end
        trees[2..9].each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload
        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "when deceased trees are present" do
      it "ignores deceased trees in calculations (Active Soul Counting)" do
        active_trees = create_list(:tree, 5, cluster: cluster, status: :active)
        create_list(:tree, 5, cluster: cluster, status: :deceased)

        active_trees.each do |tree|
          create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
        end

        cluster.reload
        contract.check_cluster_health!(target_date)

        expect(contract.reload).to be_status_active
      end
    end

    context "when SQL subquery optimization" do
      it "uses subquery instead of loading all tree IDs into memory" do
        create(:tree, cluster: cluster, status: :active)
        create(:ai_insight,
          analyzable: cluster.trees.active.first,
          target_date: target_date,
          stress_index: 0.1
        )

        # Verify the query uses a subquery (WHERE analyzable_id IN (SELECT ...))
        # rather than loading IDs into an array (WHERE analyzable_id IN (1, 2, 3, ...))
        queries = []
        callback = ->(_name, _start, _finish, _id, payload) {
          queries << payload[:sql] if payload[:sql]&.include?("ai_insights")
        }

        cluster.reload
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          contract.check_cluster_health!(target_date)
        end

        insight_query = queries.find { |q| q.include?("analyzable_type") }
        expect(insight_query).to be_present
        # The subquery should contain SELECT "trees"."id" FROM "trees"
        expect(insight_query).to include("SELECT")
        expect(insight_query).to include("trees")
      end
    end
  end

  # [ARCH.100] Доти цей блок звався «cluster timezone integration» і мав ДОВОДИТИ, що пояс
  # кластера обирає добу аудиту. Він нічого не доводив: єдине його твердження стояло під
  # `if nz_yesterday != utc_yesterday`, тобто мовчало більшу частину доби, а всередині
  # умови перевіряло `be_status_active` — стан, у якому контракт і так народжується.
  # Тепер пін стереже властивість, від якої залежать гроші: пояс НЕ впливає на присуд.
  describe "reporting-date anchor vs cluster timezone" do
    let(:organization) { create(:organization) }
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }

    # ⚠️ Час заморожено на реальному моменті крона (02:00 UTC) НАВМИСНО: локальна доба
    # розходиться з добою звіту лише у вікні `UTC-година < |offset|`, тож без заморозки
    # обидва приклади дві третини доби були б зелені на зламаному коді.
    let(:cron_moment) { Time.utc(2026, 8, 13, 2, 0, 0) }

    def seed_healthy_day!
      tree = create(:tree, cluster: cluster, status: :active)
      create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
                          target_date: AiInsight.reporting_date, stress_index: 0.05)
      cluster.reload
    end

    context "when the cluster sits west of UTC-2 (the whole of the Americas)" do
      let(:cluster) { create(:cluster, organization: organization, environmental_settings: { "timezone" => "America/Manaus" }) }

      # 🔴 Регрес ARCH.100. Доти дефолт брав «вчора» в поясі кластера, а інсайт лежав за
      # UTC-добою агрегатора — і здоровий ліс щоночі діставав `:blackout`, тобто виклик
      # людини в поле й невиплачену Celo-винагороду.
      it "returns :healthy on a healthy day instead of a fabricated blackout" do
        travel_to(cron_moment) do
          # ліхтар: без розходження дат приклад стеріг би порожнечу
          expect(Time.use_zone("America/Manaus") { Date.yesterday }).not_to eq(AiInsight.reporting_date)
          seed_healthy_day!

          expect(contract.check_cluster_health!).to eq(:healthy)
        end
      end
    end

    context "when the cluster sits east of UTC" do
      let(:cluster) { create(:cluster, organization: organization, environmental_settings: { "timezone" => "Pacific/Auckland" }) }

      it "returns the same verdict on the same data" do
        travel_to(cron_moment) do
          seed_healthy_day!

          expect(contract.check_cluster_health!).to eq(:healthy)
        end
      end
    end
  end

  describe "#terminate_early!" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster, status: :active) }

    it "changes status to cancelled and sets cancelled_at" do
      contract.terminate_early!
      contract.reload

      expect(contract).to be_status_cancelled
      expect(contract.cancelled_at).to be_present
    end

    it "raises when contract is not active" do
      contract.update_column(:status, described_class.statuses[:draft])

      expect { contract.terminate_early! }.to raise_error(RuntimeError, /не активний/)
    end

    it "raises when minimum days before exit not met" do
      contract.update!(start_date: 10.days.ago, min_days_before_exit: 60)

      expect { contract.terminate_early! }.to raise_error(RuntimeError, /Мінімальний термін/)
    end

    it "enqueues BurnCarbonTokensWorker when burn_accrued_points is true" do
      contract.update!(burn_accrued_points: true)

      contract.terminate_early!

      expect(BurnCarbonTokensWorker.jobs.size).to eq(1)
    end

    it "does not enqueue BurnCarbonTokensWorker when burn_accrued_points is false" do
      contract.update!(burn_accrued_points: false)

      contract.terminate_early!

      expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
    end

    it "returns refund and fee details" do
      contract.update!(early_exit_fee_percent: 10, burn_accrued_points: false)

      result = contract.terminate_early!

      expect(result).to include(:refund, :fee, :burned)
      expect(result[:burned]).to be(false)
    end
  end

  describe "#calculate_early_exit_fee" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "calculates fee based on early_exit_fee_percent" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000, early_exit_fee_percent: 15)

      expect(contract.calculate_early_exit_fee).to eq(BigDecimal("7500.0"))
    end

    it "returns 0 when no fee percent is set" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000)

      expect(contract.calculate_early_exit_fee).to eq(BigDecimal("0"))
    end
  end

  describe "#calculate_prorated_refund" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "calculates prorated refund minus fee" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000, start_date: 6.months.ago, end_date: 6.months.from_now,
        status: :active, early_exit_fee_percent: 10)

      refund = contract.calculate_prorated_refund

      expect(refund).to be > 0
      expect(refund).to be < 50_000
    end

    it "returns 0 when contract is not active" do
      contract = create(:naas_contract, organization: organization, cluster: cluster,
        total_funding: 50_000, status: :draft)

      expect(contract.calculate_prorated_refund).to eq(BigDecimal("0"))
    end
  end

  describe "cancellation_terms store_accessor" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }

    it "reads and writes early_exit_fee_percent" do
      contract.update!(early_exit_fee_percent: 15)

      expect(contract.reload.early_exit_fee_percent).to eq(15)
    end

    it "reads and writes burn_accrued_points" do
      contract.update!(burn_accrued_points: true)

      expect(contract.reload.burn_accrued_points).to be(true)
    end

    it "reads and writes min_days_before_exit" do
      contract.update!(min_days_before_exit: 30)

      expect(contract.reload.min_days_before_exit).to eq(30)
    end
  end

  # [UI.10] Пʼять прикладів `#current_yield_performance` знято разом із методом
  # (присуд власника 2026-08-14). 🔴 Варте перенесення: жоден із них не міг
  # спіймати дефект, бо всі пінили АРИФМЕТИКУ (`2500/10000 → 25`) — вона була
  # бездоганна. Хибними були ОДИНИЦІ операндів (SCC ÷ USD) і підпис колонки, а
  # питання «що це число означає» не ставив жоден приклад. Приклад на `.clamp`
  # навіть цементував маскування: він доводив, що 200% стають 100%, тобто
  # стверджував як контракт саме те, що ховало безглуздя.
  describe "#current_yield_performance" do
    it "більше не існує — величина не мала одиниці, а датчик мав чужий підпис" do
      expect(described_class.new).not_to respond_to(:current_yield_performance)
    end
  end

  describe "scopes" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    describe ".active" do
      it "returns only active contracts" do
        active = create(:naas_contract, organization: organization, cluster: cluster, status: :active)
        draft = create(:naas_contract, organization: organization, cluster: cluster, status: :draft)

        expect(described_class.active).to include(active)
        expect(described_class.active).not_to include(draft)
      end
    end

    describe ".pending_completion" do
      it "returns active contracts past their end date" do
        expired = create(:naas_contract, organization: organization, cluster: cluster,
          status: :active, end_date: 1.day.ago)
        ongoing = create(:naas_contract, organization: organization, cluster: cluster,
          status: :active, end_date: 1.month.from_now)

        expect(described_class.pending_completion).to include(expired)
        expect(described_class.pending_completion).not_to include(ongoing)
      end
    end
  end

  describe "validations" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "requires total_funding to be positive" do
      contract = build(:naas_contract, organization: organization, cluster: cluster, total_funding: -1)
      expect(contract).not_to be_valid
    end

    it "requires start_date" do
      contract = build(:naas_contract, organization: organization, cluster: cluster, start_date: nil)
      expect(contract).not_to be_valid
    end

    it "requires end_date" do
      contract = build(:naas_contract, organization: organization, cluster: cluster, end_date: nil)
      expect(contract).not_to be_valid
    end

    it "requires end_date after start_date" do
      contract = build(:naas_contract, organization: organization, cluster: cluster,
        start_date: 1.month.from_now, end_date: 1.month.ago)
      expect(contract).not_to be_valid
      expect(contract.errors[:end_date]).to be_present
    end
  end

  describe "#calculate_prorated_refund when total_days is zero" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "returns 0 when start_date equals end_date" do
      contract = create(:naas_contract,
        organization: organization,
        cluster: cluster,
        status: :active,
        start_date: Date.current,
        end_date: Date.current
      )
      contract.update_columns(start_date: Date.current, end_date: Date.current)

      expect(contract.calculate_prorated_refund).to eq(BigDecimal("0"))
    end
  end

  describe "cluster health verdict (via ContractHealthCheckService)" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "routes absence-of-data to Field Audit (:blackout) without enqueuing a burn" do
      contract = create(:naas_contract, organization: organization, cluster: cluster, status: :active)
      create(:tree, cluster: cluster, status: :active)
      cluster.reload

      expect(contract.check_cluster_health!(Time.current.utc.to_date - 1)).to eq(:blackout)

      expect(BurnCarbonTokensWorker.jobs.size).to eq(0)
      expect(contract.reload).to be_status_active
    end

    it "enqueues the burn worker (:degraded) on >20% critical stress, without pre-breaching" do
      contract = create(:naas_contract, organization: organization, cluster: cluster, status: :active)
      trees = create_list(:tree, 10, cluster: cluster, status: :active)
      # [SLASH-1] >20% critical stress (data present, NOT a blackout) → chokepoint adjudicates
      # slash-vs-freeze. Breach is async (set only by a real positive-A slash), so NOT pre-set.
      target = Time.current.utc.to_date - 1
      trees[0..2].each { |t| create(:ai_insight, analyzable: t, target_date: target, stress_index: 1.0) }
      trees[3..9].each { |t| create(:ai_insight, analyzable: t, target_date: target, stress_index: 0.1) }
      cluster.reload

      expect(contract.check_cluster_health!(target)).to eq(:degraded)

      expect(BurnCarbonTokensWorker.jobs.size).to eq(1)
      expect(contract.reload).to be_status_active
    end
  end

  # =========================================================================
  # AASM STATE MACHINE
  # =========================================================================
  describe "AASM state machine" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    describe "initial state" do
      it "starts as draft" do
        contract = build(:naas_contract, organization: organization, cluster: cluster, status: :draft)
        expect(contract).to be_draft
      end
    end

    describe "#activate!" do
      it "transitions from draft to active" do
        contract = create(:naas_contract, organization: organization, cluster: cluster, status: :draft)
        contract.activate!
        expect(contract.reload).to be_status_active
      end

      it "rejects transition from fulfilled" do
        contract = create(:naas_contract, organization: organization, cluster: cluster, status: :fulfilled)
        expect { contract.activate! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#fulfill!" do
      it "transitions from active to fulfilled" do
        contract = create(:naas_contract, organization: organization, cluster: cluster, status: :active)
        contract.fulfill!
        expect(contract.reload).to be_status_fulfilled
      end
    end

    describe "#breach!" do
      it "transitions from active to breached" do
        contract = create(:naas_contract, organization: organization, cluster: cluster, status: :active)
        contract.breach!
        expect(contract.reload).to be_status_breached
      end
    end

    describe "#cancel!" do
      it "transitions from draft to cancelled" do
        contract = create(:naas_contract, organization: organization, cluster: cluster, status: :draft)
        contract.cancel!
        expect(contract.reload).to be_status_cancelled
      end

      it "transitions from active to cancelled" do
        contract = create(:naas_contract, organization: organization, cluster: cluster, status: :active)
        contract.cancel!
        expect(contract.reload).to be_status_cancelled
      end
    end

    describe "may_ query methods" do
      it "reports valid transitions from draft" do
        contract = build(:naas_contract, organization: organization, cluster: cluster, status: :draft)
        expect(contract.may_activate?).to be true
        expect(contract.may_fulfill?).to be false
        expect(contract.may_cancel?).to be true
      end
    end
  end

  # =========================================================================
  # HYBRID PROTOCOL GAIA: Corporate Premium (Insurance Pool Funding)
  # =========================================================================
  describe "INSURANCE_PREMIUM_RATE constant" do
    it "is defined as BigDecimal 0.05" do
      expect(described_class::INSURANCE_PREMIUM_RATE).to eq(BigDecimal("0.05"))
      expect(described_class::INSURANCE_PREMIUM_RATE).to be_a(BigDecimal)
    end
  end

  describe "#insurance_premium_amount" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "returns 5% of total_funding" do
      contract = create(:naas_contract, organization: organization, cluster: cluster, total_funding: 100_000)
      expect(contract.insurance_premium_amount).to eq(BigDecimal("5000.0"))
    end

    it "returns correct premium for small amounts" do
      contract = create(:naas_contract, organization: organization, cluster: cluster, total_funding: 1)
      expect(contract.insurance_premium_amount).to eq(BigDecimal("0.05"))
    end

    it "uses BigDecimal precision" do
      contract = create(:naas_contract, organization: organization, cluster: cluster, total_funding: 33_333)
      expect(contract.insurance_premium_amount).to eq(BigDecimal("1666.65"))
    end
  end

  describe "#forester_share_amount" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "returns 95% of total_funding" do
      contract = create(:naas_contract, organization: organization, cluster: cluster, total_funding: 100_000)
      expect(contract.forester_share_amount).to eq(BigDecimal("95000.0"))
    end

    it "sums to total_funding with insurance_premium_amount" do
      contract = create(:naas_contract, organization: organization, cluster: cluster, total_funding: 77_777)
      expect(contract.insurance_premium_amount + contract.forester_share_amount).to eq(contract.total_funding)
    end
  end

  describe ".total_insurance_premiums" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "is 5% of total_funding across activated (active/fulfilled/breached) contracts" do
      create(:naas_contract, status: :active, organization: organization, cluster: cluster, total_funding: 100_000)
      create(:naas_contract, status: :fulfilled, organization: organization, cluster: cluster, total_funding: 200_000)
      create(:naas_contract, status: :breached, organization: organization, cluster: cluster, total_funding: 100_000)
      # (100k + 200k + 100k) × 5% = 20_000
      expect(described_class.total_insurance_premiums).to eq(BigDecimal("20000.0"))
    end

    it "excludes draft (premium not yet paid) and cancelled (refunded)" do
      create(:naas_contract, status: :draft, organization: organization, cluster: cluster, total_funding: 500_000)
      create(:naas_contract, status: :cancelled, organization: organization, cluster: cluster, total_funding: 500_000)
      expect(described_class.total_insurance_premiums).to eq(BigDecimal("0.0"))
    end

    it "returns zero when there are no contracts" do
      expect(described_class.total_insurance_premiums).to eq(BigDecimal("0"))
    end

    # [ARCH.90] Вісь, від якої залежить фінзвіт: той самий метод, викликаний на
    # RELATION, мусить рахувати внесок ОДНІЄЇ організації, а не платформи. Доти
    # `reports#financial_summary` брав класову форму, тобто клав у звіт орендаря
    # агрегат по ВСІХ орендарях — а це саме та pooled-величина, яку
    # `protocols/legal/securities_review.md` F8 називає фактором Howey prong 2.
    # Пін навмисно має ДВА тенанти з різними сумами: з одним «своє» і «все»
    # збігаються, і перевірка не здатна виразити дефект (`04_06 §B.2` BP #21).
    it "scopes to a single organization when called on a relation" do
      other_organization = create(:organization)
      other_cluster = create(:cluster, organization: other_organization)
      create(:naas_contract, status: :active, organization: organization, cluster: cluster, total_funding: 100_000)
      create(:naas_contract, status: :active, organization: other_organization, cluster: other_cluster, total_funding: 900_000)

      expect(described_class.total_insurance_premiums).to eq(BigDecimal("50000.0"))
      expect(organization.naas_contracts.total_insurance_premiums).to eq(BigDecimal("5000.0"))
      expect(other_organization.naas_contracts.total_insurance_premiums).to eq(BigDecimal("45000.0"))
    end
  end

  # [ARCH.57] Кожна зміна статусу контракту → audit-ланцюг організації, chain-only.
  # Хук = saved_change_to_status? — МУСИТЬ ловити і raw update!-шляхи (breach у
  # BlockchainBurningService, cancel у ContractTerminationService йдуть повз AASM).
  describe "contract audit-trail [ARCH.57]" do
    let!(:oracle) do
      create(:user, :super_admin, email_address: "oracle.executioner@system.silken.net",
                                  first_name: "Oracle", last_name: "Executioner")
    end
    let(:contract) { create(:naas_contract, status: :draft) }

    it "records an AASM transition into the org chain, chain-only" do
      expect { contract.activate! }.to change { AuditLogWorker.jobs.size }.by(1)

      job = AuditLogWorker.jobs.last
      attrs = job["args"].first
      expect(attrs["action"]).to eq("naas_contract_to_active")
      expect(attrs["organization_id"]).to eq(contract.organization_id)
      expect(attrs["metadata"]).to include("from" => "draft", "to" => "active")
      expect(job["args"][1]).to be false
    end

    it "records a raw update!(status:) that bypasses AASM (the production breach/cancel path)" do
      contract.update!(status: :active)
      AuditLogWorker.jobs.clear

      expect { contract.update!(status: :breached) }
        .to change { AuditLogWorker.jobs.size }.by(1)

      attrs = AuditLogWorker.jobs.last["args"].first
      expect(attrs["action"]).to eq("naas_contract_to_breached")
      expect(attrs["metadata"]).to include("from" => "active", "to" => "breached")
    end

    it "does not record non-status updates" do
      expect { contract.update!(total_funding: contract.total_funding + 1) }
        .not_to change { AuditLogWorker.jobs.size }
    end
  end
end
