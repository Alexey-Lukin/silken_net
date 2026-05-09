# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Realm do
  describe "validations" do
    it "is valid with required attributes" do
      realm = build(:codex_realm)
      expect(realm).to be_valid
    end

    it "requires a slug" do
      realm = build(:codex_realm, slug: nil)
      expect(realm).not_to be_valid
    end

    it "requires bilingual names" do
      realm = build(:codex_realm, name_uk: nil, name_en: nil)
      expect(realm).not_to be_valid
      expect(realm.errors[:name_uk]).to be_present
      expect(realm.errors[:name_en]).to be_present
    end

    it "requires a glyph and accent_token" do
      realm = build(:codex_realm, glyph: nil, accent_token: nil)
      expect(realm).not_to be_valid
    end

    it "rejects malformed slug" do
      realm = build(:codex_realm, slug: "Bad Slug!")
      expect(realm).not_to be_valid
      expect(realm.errors[:slug]).to be_present
    end

    it "enforces slug uniqueness" do
      create(:codex_realm, slug: "ecosystem")
      dup = build(:codex_realm, slug: "ecosystem")
      expect(dup).not_to be_valid
    end

    it "rejects negative position" do
      realm = build(:codex_realm, position: -1)
      expect(realm).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:active)   { create(:codex_realm, is_active: true,  position: 2) }
    let!(:archived) { create(:codex_realm, is_active: false, position: 1) }

    it ".active returns only active realms" do
      expect(described_class.active).to contain_exactly(active)
    end

    it ".ordered orders by position then id" do
      expect(described_class.ordered.first).to eq(archived) # position 1 < 2
    end
  end

  describe "#display_name" do
    let(:realm) { build(:codex_realm, name_uk: "Екосистеми", name_en: "Ecosystems") }

    it "returns Ukrainian name for :uk locale" do
      expect(realm.display_name(:uk)).to eq("Екосистеми")
    end

    it "returns English name for any non-uk locale" do
      expect(realm.display_name(:en)).to eq("Ecosystems")
    end
  end
end
