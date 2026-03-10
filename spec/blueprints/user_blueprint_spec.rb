# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserBlueprint, type: :model do
  let(:organization) { create(:organization) }
  let(:user) do
    create(:user, first_name: "Taras", last_name: "Shevchenko",
                  role: :admin, organization: organization)
  end

  describe ":minimal view" do
    subject(:parsed) { JSON.parse(described_class.render(user, view: :minimal)) }

    it "includes identifier" do
      expect(parsed["id"]).to eq(user.id)
    end

    it "includes first_name and last_name" do
      expect(parsed["first_name"]).to eq("Taras")
      expect(parsed["last_name"]).to eq("Shevchenko")
    end

    it "includes computed full_name" do
      expect(parsed["full_name"]).to eq("Taras Shevchenko")
    end

    it "excludes fields from other views" do
      expect(parsed).not_to have_key("email_address")
      expect(parsed).not_to have_key("role")
      expect(parsed).not_to have_key("mfa_enabled")
    end
  end

  describe ":profile view" do
    subject(:parsed) { JSON.parse(described_class.render(user, view: :profile)) }

    it "includes identity fields" do
      expect(parsed["email_address"]).to eq(user.email_address)
      expect(parsed["first_name"]).to eq("Taras")
      expect(parsed["last_name"]).to eq("Shevchenko")
      expect(parsed["role"]).to eq("admin")
    end

    it "includes last_seen_at" do
      expect(parsed).to have_key("last_seen_at")
    end

    it "includes computed full_name" do
      expect(parsed["full_name"]).to eq("Taras Shevchenko")
    end

    it "includes mfa_enabled flag" do
      expect(parsed["mfa_enabled"]).to eq(user.mfa_enabled?)
    end

    it "includes has_password flag" do
      expect(parsed["has_password"]).to be true
    end

    context "when user has no password" do
      let(:user) do
        u = create(:user, first_name: "OAuth", last_name: "User", organization: organization)
        u.update_columns(password_digest: nil)
        u
      end

      it "returns false for has_password" do
        expect(parsed["has_password"]).to be false
      end
    end
  end

  describe ":crew view" do
    subject(:parsed) { JSON.parse(described_class.render(user, view: :crew)) }

    it "includes name and role fields" do
      expect(parsed["first_name"]).to eq("Taras")
      expect(parsed["last_name"]).to eq("Shevchenko")
      expect(parsed["role"]).to eq("admin")
    end

    it "includes last_seen_at" do
      expect(parsed).to have_key("last_seen_at")
    end

    it "includes computed full_name" do
      expect(parsed["full_name"]).to eq("Taras Shevchenko")
    end

    it "excludes email and security fields" do
      expect(parsed).not_to have_key("email_address")
      expect(parsed).not_to have_key("mfa_enabled")
      expect(parsed).not_to have_key("has_password")
    end
  end

  describe "full_name edge cases" do
    context "when last_name is blank" do
      let(:user) { create(:user, first_name: "Taras", last_name: "", organization: organization) }

      it "returns first_name only" do
        parsed = JSON.parse(described_class.render(user, view: :minimal))
        expect(parsed["full_name"]).to eq("Taras")
      end
    end

    context "when both names are blank" do
      let(:user) { create(:user, first_name: "", last_name: "", organization: organization) }

      it "falls back to email_address" do
        parsed = JSON.parse(described_class.render(user, view: :minimal))
        expect(parsed["full_name"]).to eq(user.email_address)
      end
    end
  end

  describe "collection rendering" do
    let!(:users) { create_list(:user, 3, organization: organization) }

    it "renders an array of users" do
      parsed = JSON.parse(described_class.render(users, view: :crew))
      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(3)
      expect(parsed.first).to have_key("full_name")
    end
  end
end
