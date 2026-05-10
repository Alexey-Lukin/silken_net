# frozen_string_literal: true

require "rails_helper"

RSpec.describe Navigation::Sidebar do
  # All hardcoded English strings come from `config/locales/navigation/en.yml`
  # since UA is the application default. Wrap render calls in
  # `I18n.with_locale(:en)` whenever asserting on English copy.
  def render_en(**kwargs)
    I18n.with_locale(:en) { render_component(**kwargs) }
  end

  describe "logo section" do
    let(:html) { render_en }

    it "renders the Silken Net logo text" do
      expect(html).to include("Silken Net")
    end

    it "renders the subtitle in English when locale is :en" do
      expect(html).to include("Central Command Citadel")
    end

    it "renders the subtitle in Ukrainian by default" do
      expect(render_component).to include("Центральна Цитадель Управління")
    end

    it "uses gaia primary color for logo" do
      expect(html).to include("text-gaia-primary")
    end
  end

  describe "status pulse" do
    let(:html) { render_en }

    it "renders sync frequency text" do
      expect(html).to include("Sync: 1.12 THz")
    end

    it "renders version label" do
      expect(html).to include("v8.0.ocean")
    end

    it "includes animate-pulse for the status dot" do
      expect(html).to include("animate-pulse")
    end
  end

  describe "section groups" do
    let(:html) { render_en }

    it "renders Strategic Insight section" do
      expect(html).to include("Strategic Insight")
    end

    it "renders Forest Operations section" do
      expect(html).to include("Forest Operations")
    end

    it "renders Neural Network section" do
      expect(html).to include("Neural Network")
    end

    it "renders Administration section" do
      expect(html).to include("Administration")
    end
  end

  describe "navigation items" do
    let(:html) { render_en }

    it "renders Strategic Insight nav items" do
      expect(html).to include("Oracle Visions")
      expect(html).to include("Treasury Matrix")
      expect(html).to include("NaaS Contracts")
      expect(html).to include("Blockchain Ledger")
      expect(html).to include("Reports Archive")
    end

    it "renders Forest Operations nav items" do
      expect(html).to include("Threat Alerts")
      expect(html).to include("Soldier Fleet")
      expect(html).to include("Maintenance Log")
      expect(html).to include("Crew Registry")
      expect(html).to include("Clan Hierarchy")
    end

    it "renders Neural Network nav items" do
      expect(html).to include("Queen Relays")
      expect(html).to include("Species DNA")
      expect(html).to include("Firmware OTA")
      expect(html).to include("Live Telemetry")
      expect(html).to include("Initiate Node")
    end

    it "renders Administration nav items" do
      expect(html).to include("Account Security")
      expect(html).to include("Notifications")
      expect(html).to include("Org Settings")
      expect(html).to include("Audit Log")
      expect(html).to include("System Audits")
      expect(html).to include("System Health")
    end
  end

  describe "icon rendering" do
    let(:html) { render_en }

    it "renders icon symbols for known icon names" do
      expect(html).to include("⊙")   # eye
      expect(html).to include("⬢")   # bank
      expect(html).to include("⚡")  # zap
      expect(html).to include("◈")   # users
      expect(html).to include("📡")  # radio
      expect(html).to include("⚙")   # cpu
      expect(html).to include("〰")  # activity
      expect(html).to include("🌳")  # tree
      expect(html).to include("▤")   # clipboard
    end
  end

  describe "active nav highlighting" do
    it "sets aria_current='page' on the active item" do
      html = render_en(current_path: "/api/v1/alerts")
      expect(html).to include('aria-current="page"')
    end

    it "applies the active token classes to the matching nav item" do
      html = render_en(current_path: "/api/v1/alerts")
      expect(html).to include("bg-gaia-primary-soft")
      expect(html).to include("border-gaia-primary")
    end

    it "does not set aria_current on non-matching items by default" do
      html = render_en(current_path: "/nonexistent")
      expect(html).not_to include('aria-current="page"')
    end
  end

  describe "badge rendering" do
    context "when ews_alert_count is positive" do
      let(:html) { render_en(ews_alert_count: 5) }

      it "renders the badge with the count" do
        expect(html).to include("5")
      end

      it "applies status-danger token classes (theme-aware)" do
        expect(html).to include("bg-status-danger")
        expect(html).to include("text-status-danger-text")
      end
    end

    context "when ews_alert_count is zero" do
      let(:html) { render_en(ews_alert_count: 0) }

      it "does not render a badge" do
        expect(html).not_to include("bg-status-danger")
      end
    end
  end

  describe "live telemetry pulse" do
    let(:html) { render_en }

    it "renders animate-ping for the live telemetry indicator" do
      expect(html).to include("animate-ping")
    end
  end

  describe "aria attributes" do
    let(:html) { render_en }

    it "includes role=navigation on the aside element" do
      expect(html).to include('role="navigation"')
    end

    it "includes aria-label for main navigation" do
      expect(html).to include('aria-label="Silken Net"')
    end

    it "includes aria-label on nav items" do
      expect(html).to include('aria-label="Oracle Visions"')
      expect(html).to include('aria-label="Threat Alerts"')
    end

    it "includes aria-hidden on icon spans" do
      expect(html).to include('aria-hidden="true"')
    end
  end

  describe "user footer section" do
    let(:html) { render_en }

    it "renders the user avatar placeholder" do
      expect(html).to include("A")
    end

    it "renders the user role label" do
      expect(html).to include("Architect")
    end

    it "renders access level text" do
      expect(html).to include("Full Access Link")
    end

    it "translates the footer role into Ukrainian by default" do
      expect(render_component).to include("Архітектор")
    end
  end

  describe "focus-visible accessibility" do
    let(:html) { render_en }

    it "includes focus-visible ring on nav items" do
      expect(html).to include("focus-visible:ring-2")
    end

    it "uses the gaia primary token for the focus ring" do
      expect(html).to include("focus-visible:ring-gaia-primary")
    end
  end

  describe "design system compliance" do
    let(:html) { render_en }

    it "uses gaia surface tokens, not raw Tailwind colors" do
      # Body of the sidebar should not leak raw bg-white/bg-black either.
      expect(html).not_to include("bg-white")
      expect(html).not_to include("bg-black")
      expect(html).not_to include("text-gray-900")
    end

    it "uses gaia border tokens for separators" do
      expect(html).to include("border-gaia-border")
    end
  end
end
