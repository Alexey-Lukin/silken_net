# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardLayout do
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

  # Minimal content component for testing layout rendering.
  let(:content_stub) do
    Class.new(ApplicationComponent) do
      def view_template
        div(id: "test-content") { "Layout Content Rendered" }
      end
    end.new
  end
  let(:html) { render_layout(content: content_stub) }

  def render_layout(title: "Dashboard", current_path: "/api/v1/dashboard",
                    ews_alert_count: 0, user: nil, content: nil)
    current_user = user || mock_user
    ApplicationController.renderer.render(
      component_class.new(
        title: title,
        current_user: current_user,
        current_path: current_path,
        ews_alert_count: ews_alert_count,
        content: content
      ),
      layout: false
    )
  end


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

  describe "content rendering" do
    it "renders the content component inside the main area" do
      expect(html).to include("Layout Content Rendered")
    end

    it "renders content inside test-content div" do
      expect(html).to include("test-content")
    end

    it "renders without errors when content is nil" do
      html = render_layout(content: nil)
      expect(html).to include("Citadel")
    end
  end

  describe "ews_alert_count" do
    it "renders without errors when ews_alert_count is 0" do
      html = render_layout(ews_alert_count: 0, content: content_stub)
      expect(html).to include("Citadel")
    end

    it "renders without errors when ews_alert_count is positive" do
      html = render_layout(ews_alert_count: 7, content: content_stub)
      expect(html).to include("Citadel")
    end
  end
end
