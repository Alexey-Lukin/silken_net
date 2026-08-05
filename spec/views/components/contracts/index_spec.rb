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

  def mock_contract(id: 42, status: "active", org_name: "Cherkasy Forest Fund",
                    cluster_name: "Carpathian-Alpha", total_value: 10_000,
                    emitted_tokens: 350, performance: 50,
                    start_date: 6.months.ago, end_date: 6.months.from_now)
    c = OpenStruct.new(
      id: id,
      status: status,
      organization: mock_org(name: org_name),
      cluster: mock_cluster(name: cluster_name),
      total_value: total_value,
      emitted_tokens: emitted_tokens,
      current_yield_performance: performance,
      start_date: start_date,
      end_date: end_date
    )
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(NaasContract) }
    c.define_singleton_method(:to_key) { [ id ] }
    c.define_singleton_method(:to_param) { id.to_s }
    c
  end

  # ⚠️ Ключі — це КОНТРАКТ із `Api::V1::ContractsController#index`, а не вигадка спеки.
  # Доти тут стояв `avg_health:`, якого контролер не кладе ніде: фікстура вигадувала
  # рівно той ключ, що читав зламаний компонент, тож обидві половини узгоджувались
  # між собою й лишались зеленими, поки картка рендерила голе «%» ([UI.7]).
  # `cluster_health` — шкала 0..1 (`health_index` = 1.0 - stress_index), відсоток робить в'ю.
  def mock_stats(total_contracted: 50_000, total_minted: 1234.5, cluster_health: 0.873)
    { total_contracted: total_contracted, total_minted: total_minted, cluster_health: cluster_health }
  end

  def render_component(contracts:, stats:, pagy:)
    ApplicationController.renderer.render(
      component_class.new(contracts: contracts, stats: stats, pagy: pagy),
      layout: false
    )
  end

  let(:contract) { mock_contract }
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

    it "renders the investment total_value with SCC" do
      expect(html).to include("10000 SCC")
    end

    it "renders emitted_tokens with SCC" do
      expect(html).to include("350 SCC")
    end

    it "renders the performance gauge" do
      expect(html).to include("50%")
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
      html = render_component(contracts: [ mock_contract(status: "active") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-success")
    end

    it "colors fulfilled contracts with the success token" do
      html = render_component(contracts: [ mock_contract(status: "fulfilled") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-success")
    end

    it "colors breached contracts with the danger token" do
      html = render_component(contracts: [ mock_contract(status: "breached") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-danger")
    end

    it "dims cancelled contracts with the neutral token" do
      html = render_component(contracts: [ mock_contract(status: "cancelled") ], stats: mock_stats, pagy: mock_pagy(last: 1))
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
    it "falls back to the neutral token" do
      html = render_component(contracts: [ mock_contract(status: "expired") ], stats: mock_stats, pagy: mock_pagy(last: 1))
      expect(html).to include("bg-status-neutral")
    end
  end

  describe "pagination rendering" do
    it "renders pagination component" do
      pagy = mock_pagy(count: 50, page: 1, last: 3)
      html = render_component(contracts: [ mock_contract ], stats: mock_stats, pagy: pagy)
      expect(html).to be_present
    end
  end

  describe "contract row with missing optional fields" do
    it "renders em-dash org, unassigned cluster and blank dates" do
      contract = mock_contract
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
