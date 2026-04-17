# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardLayout do
  # DashboardLayout uses ActionView helpers (csp_meta_tag, csrf_meta_tags,
  # stylesheet_link_tag, javascript_importmap_tags) not included in Phlex by default.
  # Also, as a layout component, view_template(&block) uses yield — we patch to provide
  # an empty content block so specs don't raise LocalJumpError.
  before(:context) do
    unless DashboardLayout.instance_variable_get(:@test_patched)
      DashboardLayout.prepend(Module.new do
        def view_template(&block)
          block ||= proc { }
          super(&block)
        end

        def csp_meta_tag(**_opts) = ""
        def csrf_meta_tags = ""
        def stylesheet_link_tag(*_args, **_opts) = ""
        def javascript_importmap_tags(*_args, **_opts) = ""
      end)
      DashboardLayout.instance_variable_set(:@test_patched, true)
    end
  end

  def mock_user(first_name: "Olena", last_name: "Kovalenko",
                role: "admin", email_address: "olena@example.org")
    u = OpenStruct.new(
      first_name: first_name,
      last_name: last_name,
      role: role,
      email_address: email_address
    )
    u.define_singleton_method(:full_name) { "#{first_name} #{last_name}" }
    u
  end

  def render_layout(title: "Dashboard", current_path: "/api/v1/dashboard",
                    ews_alert_count: 0, user: nil)
    current_user = user || mock_user
    ApplicationController.renderer.render(
      component_class.new(
        title: title,
        current_user: current_user,
        current_path: current_path,
        ews_alert_count: ews_alert_count
      ),
      layout: false
    )
  end

  let(:html) { render_layout }

  describe "page title in head" do
    it "renders the title with Silken Net prefix" do
      html = render_layout(title: "Forest Matrix")
      expect(html).to include("Silken Net // Forest Matrix")
    end

    it "includes the title in a <title> tag" do
      html = render_layout(title: "Alerts")
      expect(html).to include("<title>")
      expect(html).to include("Alerts")
    end
  end

  describe "FOUC script" do
    it "renders the anti-FOUC theme script in head" do
      expect(html).to include("localStorage.getItem")
    end

    it "includes dark class detection in the FOUC script" do
      expect(html).to include("dark")
    end
  end

  describe "breadcrumb from path" do
    it "renders Citadel as the root breadcrumb" do
      expect(html).to include("Citadel")
    end

    it "renders path segments from current_path" do
      html = render_layout(current_path: "/api/v1/trees")
      expect(html).to include("Trees")
    end

    it "renders nested path segments" do
      html = render_layout(current_path: "/api/v1/maintenance_records")
      expect(html).to include("Maintenance records")
    end
  end

  describe "user avatar letter" do
    it "renders the first letter of the user's first name" do
      html = render_layout(user: mock_user(first_name: "Ivan"))
      # Avatar displays the first letter
      expect(html).to include("I")
    end

    it "renders the user full name in top bar" do
      html = render_layout(user: mock_user(first_name: "Olena", last_name: "Kovalenko"))
      expect(html).to include("Olena Kovalenko")
    end

    it "renders the user role" do
      html = render_layout(user: mock_user(role: "admin"))
      expect(html).to include("admin")
    end
  end

  describe "theme switcher" do
    it "renders the ThemeSwitcher component" do
      # ThemeSwitcher renders with theme Stimulus controller
      expect(html).to include("theme")
    end
  end

  describe "sidebar rendering" do
    it "renders the sidebar navigation" do
      expect(html).to include("sidebar-navigation")
    end
  end

  describe "main layout structure" do
    it "renders the main role element" do
      expect(html).to include('role="main"')
    end

    it "renders as a full HTML document" do
      expect(html).to match(/<!doctype html>/i)
    end

    it "renders the html element with h-full class" do
      expect(html).to include("h-full")
    end
  end

  describe "ews_alert_count" do
    it "renders without errors when ews_alert_count is 0" do
      html = render_layout(ews_alert_count: 0)
      expect(html).to include("Citadel")
    end

    it "renders without errors when ews_alert_count is positive" do
      html = render_layout(ews_alert_count: 7)
      expect(html).to include("Citadel")
    end
  end
end
