# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::Index do
  def mock_org(id: 1, name: "EcoInvest DAO", total_clusters: 5, total_contracted: 12_000,
               crypto_public_address: "0xAbCD1234ABCD1234AbCD1234ABcD1234ABCD1234")
    org = OpenStruct.new(
      id: id,
      name: name,
      total_clusters: total_clusters,
      total_contracted: total_contracted,
      crypto_public_address: crypto_public_address
    )
    org.define_singleton_method(:model_name) { ActiveModel::Name.new(Organization) }
    org.define_singleton_method(:to_key) { [ id ] }
    org.define_singleton_method(:to_param) { id.to_s }
    org
  end

  let(:org)           { mock_org }
  let(:organizations) { [ org, mock_org(id: 2, name: "GreenFund Ltd", total_contracted: 5_000) ] }
  let(:html)          { render_component(organizations: organizations, pagy: mock_pagy(count: 63)) }

  describe "header section" do
    it "renders the Global Clan Registry heading" do
      expect(html).to include("Global Clan Registry")
    end

    it "renders the subtitle" do
      expect(html).to include("multi-tenant entities")
    end
  end

  describe "table headers" do
    it "renders Organization Name column" do
      expect(html).to include("Organization Name")
    end

    it "renders Contracted column" do
      expect(html).to include("Contracted")
    end

    it "renders On-Chain Identity column" do
      expect(html).to include("On-Chain Identity")
    end

    it "renders Audit column" do
      expect(html).to include("Audit")
    end
  end

  describe "organization rows" do
    it "renders organization name" do
      expect(html).to include("EcoInvest DAO")
    end

    it "renders total contracted with SCC suffix" do
      expect(html).to include("12000 SCC")
    end

    it "renders cluster count" do
      expect(html).to include("5")
    end

    it "renders VIEW_PROFILE link" do
      expect(html).to include("VIEW_PROFILE")
    end

    it "renders link with aria-label for org name" do
      expect(html).to include("View EcoInvest DAO profile")
    end

    it "renders second organization name" do
      expect(html).to include("GreenFund Ltd")
    end
  end

  # [UI.6] Двері в чужий контекст. Дефолт `nil` тут НЕ fail-closed у сенсі прав
  # (сторінка вся під `authorize_super_admin!`), а точне представлення стану
  # «контекст ще не обрано» — тому забуту проводку ловить не ці приклади, а
  # request-пін на маркер.
  describe "перемикач контексту" do
    it "дає кнопку на організацію, в якій зараз не стоїмо" do
      switch_path = Rails.application.routes.url_helpers.switch_organization_path(2)

      # Повний шлях, не префікс: `switch_organization_path(1)` — теж
      # валідний початок для будь-якого сусіднього id.
      expect(html).to include(%(action="#{switch_path}"))
      expect(html).to include("SWITCH_TO")
      expect(html).to include("Switch acting context to GreenFund Ltd")
    end

    # [UI.11] Дзеркальна зміна 2026-08-01: доти цей приклад вимагав
    # `data-turbo="false"` з причиною «інакше permanent-сайдбар лишиться з чужим
    # лічильником». Причину знято — `data-turbo-permanent` більше не стоїть на
    # сайдбарі, тож Turbo-візит віддає свіжу розмітку сам, і повне перезавантаження
    # стало чистим надміром. Пін лишається, але з протилежним знаком: він стереже,
    # щоб атрибут не повернувся «про всяк випадок», коли його підстава вже мертва.
    #
    # ⚠️ Ризик, який довелось перевірити окремо, бо він неочевидний: `switch` кличе
    # `drop_open_sockets!` → `disconnect(reconnect: false)`. Джерело `actioncable`:
    # `Subscriptions#add` кличе `ensureActiveConnection` → `connection.open()`, якщо
    # зʼєднання неактивне — тобто новий `<turbo-cable-stream-source>` у заміненому
    # body піднімає сокет сам, і живі оновлення не гинуть.
    it "НЕ вимикає Turbo — підстава (permanent-сайдбар) знята разом з атрибутом" do
      expect(html).not_to include('data-turbo="false"')
    end

    it "на поточному контексті показує маркер замість кнопки" do
      html = render_component(
        organizations: organizations,
        pagy: mock_pagy(count: 63),
        acting_organization: org
      )
      own_switch = Rails.application.routes.url_helpers.switch_organization_path(1)

      expect(html).to include("ACTIVE_CONTEXT")
      expect(html).to include('aria-current="true"')
      expect(html).not_to include(%(action="#{own_switch}"))
      # 🔴 Без цього рядка предикат переживає мутацію: `== org.id` → `.present?`
      # дало б маркер у ВСІХ рядках і кнопку в жодному, а три асерти вище лишились
      # би зеленими. Твердження «не пропонуй перемкнутись туди, де стоїш» має
      # ДРУГУ половину — «пропонуй там, де не стоїш», і пінити треба обидві.
      other_switch = Rails.application.routes.url_helpers.switch_organization_path(2)
      expect(html).to include(%(action="#{other_switch}"))
    end

    it "без обраного контексту маркера немає в жодному рядку" do
      expect(html).not_to include("ACTIVE_CONTEXT")
    end
  end

  describe "pagination" do
    it "renders pagination" do
      expect(html).to include("page=")
    end
  end
end
