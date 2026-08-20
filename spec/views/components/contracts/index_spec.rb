# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::Index do
  # [TEST.12] Реальний незбережений `NaasContract`. Емісії в контракту НЕМАЄ свідомо
  # ([ARCH.103]: величина кластерна, компонент бере її з `cluster_emissions:`-хешу за
  # `cluster_id`), тож фікстура, що клала б її полем контракту, вигадувала б знятий
  # ⚖️-присудом контракт зі значенням.
  #
  # 🔴 `total_value` (alias на `total_funding`) — колонка `numeric`, тобто BigDecimal:
  # прод друкує десяткову частку, а Integer у фікстурі її ховав.
  def build_contract(id: 42, status: :active, org_name: "Cherkasy Forest Fund",
                     cluster_id: 77, cluster_name: "Carpathian-Alpha", total_funding: 10_000,
                     start_date: 6.months.ago, end_date: 6.months.from_now)
    NaasContract.new(
      id: id,
      status: status,
      organization: Organization.new(name: org_name),
      cluster: Cluster.new(id: cluster_id, name: cluster_name),
      total_funding: total_funding,
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

  def render_component(contracts:, stats:, pagy:, cluster_emissions: {})
    ApplicationController.renderer.render(
      component_class.new(contracts: contracts, stats: stats, pagy: pagy,
                          cluster_emissions: cluster_emissions),
      layout: false
    )
  end

  let(:contract) { build_contract }
  let(:html) do
    render_component(contracts: [ contract ], stats: mock_stats, pagy: mock_pagy(last: 1),
                     cluster_emissions: { 77 => 350 })
  end

  describe "header" do
    it "renders Monitored Clusters heading" do
      expect(html).to include("Monitored Clusters")
    end
  end

  describe "StatCards" do
    it "renders Total Service Fees stat card" do
      expect(html).to include("Total Service Fees")
    end

    # 🔴 [ARCH.103] Мітка мусила поїхати РАЗОМ зі значенням: агрегат тепер ЧИСТА
    # емісія (мінти − спалення) по ДЕДУПЛІКОВАНИХ кластерах, а «SCC Issued»
    # обіцяла gross-емісію за контрактами. Дві незалежні брехні, і обидві жили
    # доти, доки цей пін тримав старий текст.
    it "renders the Net Cluster Emission stat card" do
      expect(html).to include("Net Cluster Emission")
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
    # USD (07_01 §5 + вся юніт-економіка §11-§20 в $), тоді як кластерна емісія — справжні
    # SCC. Доти обидві казали «SCC», тобто фіат малювався карбоновим токеном.
    it "renders the contracted service fee in USD, not in the carbon token" do
      expect(html).to include("10000.0 USD")
      expect(html).not_to include("10000.0 SCC")
    end

    # [ARCH.103] 350 приходить із `cluster_emissions:`-хешу (ключ 77 = cluster_id
    # фікстури), НЕ з контракту — колонки емісії в контракту більше немає.
    it "renders the cluster emission with SCC" do
      expect(html).to include("350.0 SCC")
    end

    # [UI.10] Датчик знято разом із колонкою (присуд власника 2026-08-14): він
    # ділив SCC на USD і стояв під підписом «Cluster Health».
    #
    # 🔴 Урок попереднього піна переживає свій приклад і варте перечитування:
    # доти мок задавав відсоток НЕЗАЛЕЖНО від двох полів, з яких модель його
    # виводить, і пінив смугу наполовину заповненою, тоді як формула на тих
    # самих числах давала майже порожню. Фікс зробив пін чесним щодо ДЕРИВАЦІЇ —
    # і саме тому не міг помітити, що деривація безглузда: він звіряв число з
    # формулою, а не величину з її підписом.
    # ⚠️ Пін цілить у ВІДБИТОК датчика (єдиний інлайн-`width` на сторінці), а не
    # в підпис: перша редакція робила `not_to include("Cluster Health")` і
    # червоніла на сусідові — герой правомірно друкує «Avg Cluster Health».
    # Той самий клас вакуумного матчера, що ловив цей файл раніше, лише
    # дзеркальний: там пін не вмів упасти, тут — не вмів пройти.
    it "більше не малює датчик під чужим підписом" do
      expect(html).to include("350.0 SCC") # ліхтар: рядок таки відрендерився
      expect(html).not_to include('style="width:')
      expect(html).not_to include("4%")
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

    # 🔴 [UI.3] Назва казала «dims», і пін вимагав саме приглушення — `opacity-50`,
    # яка давала 2.25:1 на бейджі `text-tiny` (поріг 4.5:1). Але `bg-status-neutral`
    # тут НЕ дискримінатор: його носять і `draft`, і `idle`, і дефолтний фолбек,
    # тож приклад «cancelled ⊥ решта» тримала виключно та сама прозорість, що була
    # дефектом. Роль перебрав `line-through` — сусідній рядок тієї ж мапи
    # (`deceased`) уже вживав його для завершеного стану.
    it "розрізняє скасований контракт неколірним дискримінатором, не приглушенням" do
      html = render_component(contracts: [ build_contract(status: "cancelled") ], stats: mock_stats, pagy: mock_pagy(last: 1))

      expect(html).to include("bg-status-neutral")
      expect(html).to include("line-through")
      expect(html).not_to include("opacity-")
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
