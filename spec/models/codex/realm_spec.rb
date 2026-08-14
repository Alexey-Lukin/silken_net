# SPDX-License-Identifier: AGPL-3.0-or-later
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

  describe "#name (bilingual switch — canonical per docs/04_01 §7b)" do
    let(:realm) { build(:codex_realm, name_uk: "Екосистеми", name_en: "Ecosystems") }

    it "returns Ukrainian name for :uk locale" do
      expect(realm.name(:uk)).to eq("Екосистеми")
    end

    it "returns English name for any non-uk locale" do
      expect(realm.name(:en)).to eq("Ecosystems")
    end

    it "defaults to current I18n locale when called without args" do
      I18n.with_locale(:uk) { expect(realm.name).to eq("Екосистеми") }
      I18n.with_locale(:en) { expect(realm.name).to eq("Ecosystems") }
    end

    # `codex_realms` table has no `name` column — only `name_uk` / `name_en`.
    # Без цього guard test просто перевіряв би attribute getter, що ховало б
    # регресії на bilingual switcher.
    it "does not collide with an attribute named `name`" do
      expect(described_class.column_names).not_to include("name")
    end
  end

  # [UI.10] Акцент реалму. Властивість, заради якої його дротували, — саме
  # РОЗРІЗНЮВАНІСТЬ: Atlas-грід є єдиною поверхнею, де всі чотири видно
  # одночасно, тож мапа, що звела б два реалми в один клас, лишила б дефект на
  # місці при зелених пінах «клас присутній».
  describe "#accent_border_class / #accent_text_class" do
    # Перелік деривується з СІДІВ, а не з руки: реалм, доданий DAO, має
    # зʼявитись тут сам, інакше «чотири різні» стає твердженням про мій список.
    let(:seeded_tokens) do
      YAML.safe_load_file(Rails.root.join("db/seeds/codex/realms.yml")).map { |r| r["accent_token"] }
    end

    it "дає КОЖНОМУ засіяному реалму власний, ні з ким не спільний відтінок" do
      expect(seeded_tokens.size).to be >= 4 # ліхтар: пін на порожньому переліку був би зелений

      border = seeded_tokens.map { |t| build(:codex_realm, accent_token: t).accent_border_class }
      text   = seeded_tokens.map { |t| build(:codex_realm, accent_token: t).accent_text_class }

      expect(border.uniq.size).to eq(seeded_tokens.size)
      expect(text.uniq.size).to eq(seeded_tokens.size)
    end

    # 🔴 Носій виміру, а не смаку: базовий `status-*` — це ФОН бейджа, і саме
    # він стояв на тексті (1.01–1.11:1 у світлій темі). Пін ловить рецидив
    # рівно цієї підміни — повернення базового токена червонить.
    it "бере ТЕКСТ із парного `-text`-токена, ніколи з фонового" do
      seeded_tokens.each do |token|
        klass = build(:codex_realm, accent_token: token).accent_text_class
        expect(klass).to end_with("-text"), "#{token} → #{klass}: фон бейджа на тексті"
      end
    end

    it "падає у нейтральний дефолт на невідомому токені, не в порожній клас" do
      realm = build(:codex_realm, accent_token: "aurora-borealis")

      expect(realm.accent_border_class).to eq(described_class::DEFAULT_ACCENT_BORDER_CLASS)
      expect(realm.accent_text_class).to eq(described_class::DEFAULT_ACCENT_TEXT_CLASS)
    end
  end

  describe "#display_glyph" do
    it "translates the seeded forest keyword to a pine emoji" do
      expect(build(:codex_realm, glyph: "forest").display_glyph).to eq("🌲")
    end

    it "returns the deciduous tree for the unique_tree realm keyword" do
      expect(build(:codex_realm, glyph: "tree").display_glyph).to eq("🌳")
    end

    it "returns the atom symbol for the protocol realm keyword" do
      expect(build(:codex_realm, glyph: "protocol").display_glyph).to eq("⚛")
    end

    it "returns the six-pointed star for the mythos realm keyword" do
      expect(build(:codex_realm, glyph: "mythos").display_glyph).to eq("✶")
    end

    it "returns DEFAULT_DISPLAY_GLYPH for an unknown keyword (forward-compat for new realms)" do
      expect(build(:codex_realm, glyph: "space").display_glyph).to eq(described_class::DEFAULT_DISPLAY_GLYPH)
    end
  end
end
