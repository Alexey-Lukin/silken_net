# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::Index do
  def mock_org(name: "Cherkasy Forest Fund")
    OpenStruct.new(name: name)
  end

  def mock_cluster(name: "Carpathian-Alpha")
    c = OpenStruct.new(name: name)
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    c.define_singleton_method(:to_key) { [ 1 ] }
    c.define_singleton_method(:to_param) { "1" }
    c
  end

  # [TEST.12] Реальний незбережений `NaasContract`, і `current_yield_performance` більше
  # НЕ задається: модель виводить його з `emitted_tokens` та `total_funding` — тобто з
  # двох полів, які мок задавав поруч і незалежно. Доти спека пінила смугу прогресу
  # наполовину заповненою, тоді як формула на тих самих числах дає майже порожню.
  #
  # 🔴 `total_value` (alias на `total_funding`) і `emitted_tokens` — колонки `numeric`,
  # тобто BigDecimal: прод друкує десяткову частку, а Integer у фікстурі її ховав.
  def build_contract(id: 42, status: :active, org_name: "Cherkasy Forest Fund",
                     cluster_name: "Carpathian-Alpha", total_funding: 10_000,
                     emitted_tokens: 350,
                     start_date: 6.months.ago, end_date: 6.months.from_now)
    NaasContract.new(
      id: id,
      status: status,
      organization: Organization.new(name: org_name),
      cluster: Cluster.new(name: cluster_name),
      total_funding: total_funding,
      emitted_tokens: emitted_tokens,
      start_date: start_date,
      end_date: end_date
    )
  end

  # ⚠️ Ключі — це КОНТРАКТ із `Api::V1::ContractsController#index`, а не вигадка спеки.
  # Доти тут стояв `avg_health:`, якого контролер не кладе ніде: фікстура вигадувала
  # рівно той ключ, що читав зламаний компонент, тож обидві половини узгоджувались
  # між собою й лишались зеленими, поки картка рендерила голе «%» ([UI.7]).
  # `cluster_health` — шкала 0..1 (`health_index` = 1.0 - stress_index), відсоток робить в'ю.
  # [ARCH.84] Фікстура будує СПРАВЖНІЙ `Cluster::HealthCoverage`, а не власний скаляр:
  # контролер кладе саме його, і мок-скаляр оголошував би світ, у якому «виміряно
  # частину» не існує як стан (`04_06 §B.2` BP #14).
  def mock_stats(total_contracted: 50_000, total_minted: 1234.5,
                 cluster_health: 0.873, measured: 4, total: 4)
    {
      total_contracted: total_contracted,
      total_minted: total_minted,
      cluster_health: Cluster::HealthCoverage.new(average: cluster_health, measured: measured, total: total)
    }
  end

  def render_component(contracts:, stats:, pagy:)
    ApplicationController.renderer.render(
      component_class.new(contracts: contracts, stats: stats, pagy: pagy),
      layout: false
    )
  end

  let(:contract) { build_contract }
  let(:html) { render_component(contracts: [ contract ], stats: mock_stats, pagy: mock_pagy(last: 1)) }

  describe "header" do
    it "renders Monitored Clusters heading" do
      expect(html).to include("Monitored Clusters")
    end
  end

  describe "StatCards" do
    it "renders Total Service Fees stat card" do
      expect(html).to include("Total Service Fees")
    end

    it "renders SCC Issued stat card" do
      expect(html).to include("SCC Issued")
    end

    it "renders Network Health stat card" do
      expect(html).to include("Network Health")
    end

    # Один пін тримає ОБИДВІ осі, і це виміряно двома мутаціями: підміна ключа
    # (`avg_health`) і зняття множника (`* 100`) червонять саме його. Негативна
    # половина `not_to include("0.873%")` тут була б декорацією — вона падає рівно
    # на тих самих мутаціях і не додає жодної, тому її знято.
    it "renders cluster_health as a percentage, not the raw 0..1 index" do
      expect(html).to include("87.3%")
    end
  end

  describe "contract rows" do
    it "renders the contract id" do
      expect(html).to include("#42")
    end

    it "renders the organization name" do
      expect(html).to include("Cherkasy Forest Fund")
    end

    it "renders the cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    # 🔴 Дві сусідні комірки НАВМИСНО в різних валютах, і плутати їх не можна в жоден бік:
    # `total_value` = alias на `total_funding` — плата клієнта за послугу, деномінована в
    # USD (07_01 §5 + вся юніт-економіка §11-§20 в $), тоді як `emitted_tokens` — справжня
    # SCC-емісія. Доти обидві казали «SCC», тобто фіат малювався карбоновим токеном.
    it "renders the contracted service fee in USD, not in the carbon token" do
      expect(html).to include("10000.0 USD")
      expect(html).not_to include("10000.0 SCC")
    end

    it "renders emitted_tokens with SCC" do
      expect(html).to include("350.0 SCC")
    end

    # 🔴 Відсоток ВИВОДИТЬСЯ з двох сусідніх комірок того ж рядка, а не задається:
    # доти мок клав його незалежно й пінив смугу наполовину заповненою, тоді як
    # формула на тих самих числах дає майже порожню — тобто сюїта стверджувала
    # протилежний стан прогресу.
    it "derives the performance gauge from the two cells it renders beside it" do
      expect(html).to include("4%")
      expect(html).not_to include("50%")
    end

    it "renders audit details link" do
      expect(html).to include("AUDIT_DETAILS")
    end
  end

  # Статус іде через спільний `StatusBadge` (I18N.1, 2026-08-05) — приватна
  # `status_color` знесена. ⚠️ Її `draft` падав у `else` і фарбувався як
  # warning; централізована мапа дає йому власний neutral.
  describe "status colors" do
    it "colors active contracts with the success token" do
      html = render_component(contracts: [ build_contract(status: "active") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-success")
    end

    it "colors fulfilled contracts with the success token" do
      html = render_component(contracts: [ build_contract(status: "fulfilled") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-success")
    end

    it "colors breached contracts with the danger token" do
      html = render_component(contracts: [ build_contract(status: "breached") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-danger")
    end

    it "dims cancelled contracts with the neutral token" do
      html = render_component(contracts: [ build_contract(status: "cancelled") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-neutral")
      expect(html).to include("opacity-50")
    end
  end

  describe "empty state" do
    it "renders table even with no contracts" do
      html = render_component(contracts: [], stats: mock_stats, pagy: mock_pagy(count: 0, last: 1))
      expect(html).to include("Monitored Clusters")
    end
  end

  # ⚠️ `expired` — значення ЧУЖОЇ родини (`ParametricInsurance`), тобто для
  # контракту це справді нерозпізнаний стан; після переходу на спільну мапу він
  # дістає `DEFAULT_STYLE`, а не бурштин попередньої `else`-гілки.
  describe "unrecognised status" do
    # ⚠️ Вхід досяжний лише стабом РИДЕРА: на реальному записі enum кидає
    # `ArgumentError` просто в конструкторі, тож доти цю гілку «перевіряло»
    # значення, якого в проді не буває.
    it "falls back to the neutral token" do
      contract = build_contract
      allow(contract).to receive(:status).and_return("expired")

      html = render_component(contracts: [ contract ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-neutral")
    end
  end

  describe "pagination rendering" do
    it "renders pagination component" do
      pagy = mock_pagy(count: 50, page: 1, last: 3)
      html = render_component(contracts: [ build_contract ], stats: mock_stats, pagy: pagy)
      expect(html).to be_present
    end
  end

  describe "contract row with missing optional fields" do
    it "renders em-dash org, unassigned cluster and blank dates" do
      contract = build_contract
      contract.organization = nil
      contract.cluster = nil
      contract.start_date = nil
      contract.end_date = nil
      html = render_component(contracts: [ contract ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("—")          # organization&.name || "—"
      expect(html).to include("UNASSIGNED")  # cluster&.name || unassigned
    end
  end
end
