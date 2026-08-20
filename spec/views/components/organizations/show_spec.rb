# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::Show do
  # 🔴 [TEST.12] Реальний незбережений `Cluster`. Цей мок стояв за два рядки над
  # надгробком, який описує конверсію `Organization` — тобто напис про ОДИН
  # обʼєкт прочитався як звіт про файл (`00_07` UI.17).
  # Що міняє конверсія предметно: `total_active_trees` не колонка, а ридер
  # `active_trees_count` — фікстура годувала ПОХІДНЕ замість джерела, тож
  # розходження ридера з колонкою було невидиме за побудовою. Метадані
  # фреймворку віддає модель (компонент будує `cluster_path`).
  # ⚠️ `health_index` навмисно лишається Float: колонка `double precision`, тож
  # тут фікстура типом НЕ брехала — і це варто сказати, щоб наступний прохід не
  # «полагодив» коректне на BigDecimal за аналогією з грошовими колонками.
  def mock_cluster(id: 1, name: "Carpathian-Alpha", health_index: 0.85, total_active_trees: 24)
    Cluster.new(id: id, name: name, health_index: health_index,
                active_trees_count: total_active_trees)
  end

  # [TEST.12] Реальний незбережений `Organization`: метадані фреймворку (потрібні
  # перемикачу контексту — `button_to` будує шлях через `to_param`) віддає модель, а не
  # фікстура. `total_contracted` — АГРЕГАТ по асоціації (`naas_contracts.sum(...).to_f`),
  # тож на незбереженому записі він чесно дає 0.0; стабимо сам ридер — метод існує,
  # підміняється лише значення. 🔴 І він віддає **Float**, а не String: доти фікстура
  # подавала рядок, тож десяткова частка, яку прод друкує завжди, була невидима.
  def build_org(id: 1, name: "Cherkasy Forest Fund", created_at: 2.years.ago,
                crypto_public_address: "0xABCD1234", billing_email: "billing@forest.org",
                total_contracted: 50_000.0)
    org = Organization.new(
      id: id,
      name: name,
      created_at: created_at,
      crypto_public_address: crypto_public_address,
      billing_email: billing_email
    )
    allow(org).to receive(:total_contracted).and_return(total_contracted)
    org
  end

  def render_component(organization:, clusters:, performance:, acting_organization: nil)
    ApplicationController.renderer.render(
      component_class.new(
        organization: organization,
        clusters: clusters,
        performance: performance,
        acting_organization: acting_organization
      ),
      layout: false
    )
  end

  let(:org) { build_org }
  let(:clusters) { [ mock_cluster ] }
  # 🔴 Значення взято з рядка контролера, що його будує (`organizations_controller`
  # `#show`: `naas_contracts.sum(:emitted_tokens).to_f.round(2)`) — тобто ГОЛИЙ Float.
  # Доти фікстура несла одиницю ВСЕРЕДИНІ значення («1234 SCC»), і пін шукав власний
  # вигаданий рядок: `StatCard` рендерить число й підпис у РІЗНИХ вузлах, тож така
  # послідовність не з'являється в розмітці ніколи, хай би що робив компонент.
  let(:performance) { { total_trees: 42, carbon_minted: 1234.56 } }
  let(:html) { render_component(organization: org, clusters: clusters, performance: performance) }

  # [UI.6] Четверта посадка «права без переходу»: з рядка реєстру ведуть ДВІ дії, а
  # профіль клану — саме те місце, де super_admin вирішує, чи входити в цей контекст.
  describe "перемикач контексту" do
    it "дає кнопку, коли дивимось на чужий клан" do
      switch_path = Rails.application.routes.url_helpers.switch_organization_path(1)

      expect(html).to include(%(action="#{switch_path}"))
      expect(html).to include("SWITCH_TO")
      expect(html).to include("Switch acting context to Cherkasy Forest Fund")
    end

    it "на власному контексті показує маркер замість кнопки" do
      html = render_component(
        organization: org, clusters: clusters, performance: performance, acting_organization: org
      )
      switch_path = Rails.application.routes.url_helpers.switch_organization_path(1)

      expect(html).to include("ACTIVE_CONTEXT")
      expect(html).to include('aria-current="true"')
      expect(html).not_to include(%(action="#{switch_path}"))
    end
  end

  describe "org name display" do
    it "renders the organization name" do
      expect(html).to include("Cherkasy Forest Fund")
    end

    it "renders Member Since with creation date" do
      expect(html).to include("Member Since:")
    end
  end

  # 🔴 [ARCH.84] Обидва приклади тут ЦЕМЕНТУВАЛИ дефект як контракт: вони
  # вимагали, щоб сторінка друкувала «FULLY_SYNCED» і зелену лампу — а обидва
  # були безумовними літералами над колонкою, якої в `Organization` НЕМАЄ.
  # Тобто сюїта вимагала твердження без джерела.
  #
  # ⚠️ Пін тримає ВІДСУТНІСТЬ, а не лише зняття: заява без виміру виглядає як
  # нешкідлива прикраса й вертається першим же редизайном (той самий носій-
  # надгробок, що для декоративного canvas).
  describe "operational status (знято — ARCH.84)" do
    it "не стверджує стану синхронізації, якого нічим не виміряти" do
      expect(html).not_to include("FULLY_SYNCED")
      expect(html).not_to include("Operational Status")
    end

    it "не малює зеленої лампи над порожнечею" do
      # Ліхтар: цілимось у САМ вузол лампи (тінь + розмір), а не в клас
      # `bg-emerald-500`, який на цій сторінці несуть ще кілька живих елементів —
      # широкий матч зробив би приклад вакуумним.
      expect(html).not_to include("h-3 w-3 rounded-full bg-emerald-500")
    end
  end

  describe "StatCards for 3 metrics" do
    it "renders Monitored Trees stat card" do
      expect(html).to include("Monitored Trees")
    end

    it "renders Soldier Trees sub-label" do
      expect(html).to include("Soldier Trees")
    end

    it "renders SCC Minted stat card" do
      expect(html).to include("SCC Minted")
    end

    # Число й одиниця живуть у РІЗНИХ вузлах `StatCard`, тож пін на «<число> SCC»
    # не міг пройти ніколи — він шукав рядок, який фікстура сама ж і вигадала.
    it "renders the carbon value the controller actually passes" do
      expect(html).to include("1234.56")
      expect(html).not_to include("1234 SCC")
    end

    it "renders Contracted Amount stat card" do
      expect(html).to include("Contracted Amount")
    end

    # 🔴 Значення картки доти не пінив ніхто — приклад вище перевіряє лише ЗАГОЛОВОК.
    # `total_contracted` віддає Float, тож прод завжди друкує десяткову частку.
    it "renders the contracted amount with the decimal its Float really carries" do
      expect(html).to include("50000.0")
    end

    it "renders total_trees count" do
      expect(html).to include("42")
    end
  end

  describe "cluster table" do
    it "renders Assigned Sectors heading" do
      expect(html).to include("Assigned Sectors")
    end

    it "renders the cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "renders the active soldiers count" do
      expect(html).to include("24 Soldiers")
    end

    it "renders the health index as percentage" do
      expect(html).to include("85%")
    end

    # 🔴 [ARCH.84] Тут стан несе ще й СМУГА, і саме вона не вміє сказати «не знаю»:
    # тире в CSS-довжину не покласти, а нульова ширина читалась би як виміряні 0%,
    # тобто як мертвий ліс. Тому смуги просто немає — пін стереже її ВІДСУТНІСТЬ.
    it "drops the vitality bar entirely for an unmeasured cluster instead of drawing it empty" do
      unmeasured = render_component(organization: org, clusters: [ mock_cluster(health_index: nil) ],
                                    performance: performance)

      expect(unmeasured).to include(I18n.t("ui.measurement.not_measured"))
      expect(unmeasured).not_to include("width: 0%")
      # ⚠️ Цілимось у САМ вузол смуги (`w-16 h-1 …`), не в колір: `bg-emerald-500`
      # живе на сторінці й поза смугою, тож матчер по всьому документу проходив би
      # через сусідній зелений вузол і нічого не доводив (`04_04` · Guard-craft #17).
      expect(unmeasured).not_to include("w-16 h-1 bg-gaia-surface-sunken")
      expect(html).to include("w-16 h-1 bg-gaia-surface-sunken")
    end

    it "renders the Open Matrix link" do
      expect(html).to include("Open Matrix →")
    end
  end

  describe "identity vault" do
    it "renders On-Chain Identity Vault heading" do
      expect(html).to include("On-Chain Identity Vault")
    end

    it "renders the crypto public address" do
      expect(html).to include("0xABCD1234")
    end

    it "renders billing contact" do
      expect(html).to include("billing@forest.org")
    end
  end

  describe "with multiple clusters" do
    it "renders all clusters" do
      clusters = [
        mock_cluster(id: 1, name: "Alpha"),
        mock_cluster(id: 2, name: "Beta")
      ]
      html = render_component(organization: org, clusters: clusters, performance: performance)
      expect(html).to include("Alpha")
      expect(html).to include("Beta")
    end
  end
end
