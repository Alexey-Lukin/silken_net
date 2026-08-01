# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Errors::NoOrganization do
  describe "rendering" do
    let(:html) { render_component }

    it "renders the page heading" do
      expect(html).to include("Quarantine")
    end

    it "renders the auth-page subtitle" do
      expect(html).to include("No Organization Assigned")
    end

    it "renders an explanatory message about the Forest Matrix" do
      expect(html).to include("Forest Matrix")
    end

    it "instructs the user to contact an administrator" do
      expect(html).to include("Contact your administrator")
    end

    it "renders a sign-out form" do
      expect(html).to include("Sign Out")
      expect(html).to include('action="/api/v1/logout"')
      expect(html).to include('name="_method" value="delete"')
    end

    it "wraps content in main with role=main" do
      expect(html).to include('role="main"')
    end
  end

  # [UI.6] Карантин — перший екран платформеного адміністратора (за seeds обидва
  # super_admin без організації), тож питання «чи є звідси вихід» роле-залежне.
  describe "роле-залежний вихід" do
    it "дає super_admin лінк на реєстр кланів" do
      html = render_component(current_user: build_stubbed(:user, :super_admin))

      # Повний шлях, не префікс: пін на початок рядка пропустив би будь-яку
      # сусідню адресу, що з нього починається.
      expect(html).to include(%(href="#{Rails.application.routes.url_helpers.api_v1_organizations_path}"))
      expect(html).to include("Choose an organization")
    end

    it "каже super_admin про КОНТЕКСТ, а не про членство" do
      html = render_component(current_user: build_stubbed(:user, :super_admin))

      expect(html).to include("Choose the context you want to act in")
      expect(html).not_to include("Contact your administrator")
    end

    it "не пропонує реєстр звичайному користувачеві — там 403" do
      html = render_component(current_user: build_stubbed(:user))

      expect(html).not_to include(%(href="#{Rails.application.routes.url_helpers.api_v1_organizations_path}"))
      expect(html).to include("Contact your administrator")
    end

    it "без актора виходу не показує (fail-closed)" do
      expect(render_component).not_to include("Choose an organization")
    end
  end

  describe "accessibility" do
    let(:html) { render_component }

    it "marks the decorative diamond logo with aria-hidden" do
      expect(html).to include('aria-hidden="true"')
    end

    it "labels the sign-out button for screen readers" do
      expect(html).to include('aria-label="Sign out"')
    end

    it "applies focus-visible ring on the sign-out button" do
      expect(html).to include("focus-visible:ring-2")
      expect(html).to include("focus-visible:ring-emerald-500")
    end
  end

  describe "design system compliance" do
    let(:html) { render_component }

    it "uses the custom text scale (text-tiny / text-compact)" do
      expect(html).to include("text-tiny")
      expect(html).to include("text-compact")
    end

    it "uses semantic status-danger-accent token for the danger LED" do
      # NoOrganization сигналізує denied/quarantined-стан — позначаємо
      # семантичним status-danger-accent (docs/04_04 §3.2). Решта auth-сторінок
      # використовує raw emerald-палітру за §3.5 (виняток для page-components).
      expect(html).to include("border-status-danger-accent")
      expect(html).to include("bg-status-danger-accent")
    end

    it "matches the Sessions::New / Passwords::Forgot card chrome" do
      expect(html).to include("border-emerald-900")
      expect(html).to include("bg-black/80")
      expect(html).to include("backdrop-blur-xl")
    end
  end
end
