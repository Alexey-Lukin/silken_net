# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Fractions::OnboardingWizard, type: :view_component do
  def render_wizard(current_user:)
    helpers = ActionController::Base.helpers
    Class.new(described_class) do
      define_method(:helpers) { helpers }
      define_method(:api_v1_codex_fraction_picker_path) { "/api/v1/codex/fractions/picker" }
      define_method(:api_v1_codex_realms_path) { "/api/v1/codex/realms" }
    end.new(current_user: current_user).call
  end

  it "renders nothing when current_user is nil" do
    expect(render_wizard(current_user: nil)).to eq("")
  end

  it "renders the picker CTA, the realms browse link, and the SSOT DOM id" do
    user = build_stubbed(:user, first_name: "Alyona")
    html = render_wizard(current_user: user)
    expect(html).to include("codex_onboarding_wizard")
    expect(html).to include("/api/v1/codex/fractions/picker")
    expect(html).to include("/api/v1/codex/realms")
    expect(html).to include("Choose your Fraction")
    expect(html).to include("Browse the Codex")
  end

  it "personalises the greeting when the user has a first name" do
    user = build_stubbed(:user, first_name: "Marko")
    html = render_wizard(current_user: user)
    expect(html).to include("Welcome to the Codex, Marko.")
  end

  it "falls back to a neutral greeting when first_name is blank" do
    user = build_stubbed(:user, first_name: nil, last_name: nil)
    html = render_wizard(current_user: user)
    expect(html).to include("Welcome to the Codex.")
  end

  it "uses gaia-* / status-* tokens only — no raw bg-white / text-gray / bg-emerald" do
    user = build_stubbed(:user, first_name: "Inna")
    html = render_wizard(current_user: user)
    expect(html).not_to include("bg-white")
    expect(html).not_to include("text-gray-")
    expect(html).not_to include("bg-emerald-")
    expect(html).to include("bg-gaia-surface")
    expect(html).to include("text-gaia-text")
    expect(html).to include("border-gaia-border")
  end

  it "exposes accessible region semantics for screen readers" do
    user = build_stubbed(:user, first_name: "Inna")
    html = render_wizard(current_user: user)
    expect(html).to include('role="region"')
    expect(html).to include('aria-label="Codex onboarding"')
  end
end
