# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passwords::Reset do
  let(:token) { "abc123securetoken" }
  let(:html)  { render_component(token: token, flash_alert: nil) }

  # 🔴 [UI.3] Див. `provisioning/new_spec` — периметр носія був третиною поверхні.
  it "associates every label with a real form control" do
    doc = Nokogiri::HTML5.fragment(html)

    expect(doc.css("label")).not_to be_empty, "no labels rendered — the pin would be vacuous"
    expect(LabelAssociation.orphan_labels(doc).map { |l| l.text.strip }).to be_empty
  end

  describe "header" do
    it "renders New Key heading" do
      expect(html).to include("New Key")
    end

    it "renders Set New Access Code subtitle" do
      expect(html).to include("Set New Access Code")
    end
  end

  describe "form fields" do
    it "renders password input field" do
      expect(html).to include('type="password"')
    end

    it "renders New Password label" do
      expect(html).to include("New Password")
    end

    it "renders password_confirmation field" do
      expect(html).to include("password_confirmation")
    end

    it "renders Confirm New Password label" do
      expect(html).to include("Confirm New Password")
    end

    it "renders hidden token field" do
      expect(html).to include('name="token"')
      expect(html).to include("abc123securetoken")
    end

    it "renders hidden _method patch override" do
      expect(html).to include('value="patch"')
    end
  end

  describe "submit button" do
    it "renders SET NEW PASSWORD button" do
      expect(html).to include("SET NEW PASSWORD")
    end
  end

  describe "back to login link" do
    it "renders Back to Login Portal link" do
      expect(html).to include("Back to Login Portal")
    end
  end

  describe "flash messages" do
    it "renders alert message when flash_alert is present" do
      html = render_component(token: token, flash_alert: "Token expired")
      expect(html).to include("Token expired")
    end

    it "does not render alert div when flash_alert is nil" do
      expect(html).not_to include("Token expired")
    end
  end

  # 🔴 [UI.3] Дзеркало `passwords/forgot` — той самий немігрований близнюк `Sessions::New`:
  # сторінка чорна в обох темах, мітки обох полів пароля на **2.18:1**, placeholder **1.31**.
  # ⚠️ Тут полів ДВА, тож пін на асоціацію нижче судить обидва — а не «хоч одне».
  describe "token discipline (contrast)" do
    it "рендерить текст на токенах і має ВЛАСНУ поверхню" do
      expect(html).to include("bg-gaia-surface-base"), "корінь без поверхні — пара fg/bg невідома"
      expect(html).to include("text-gaia-text-strong")
      expect(html).to include("text-gaia-text-subtle")

      expect(html).not_to match(/\btext-(?:white|(?:gray|zinc|neutral|slate|stone)-\d+|emerald-\d+)\b/)
      expect(html).not_to match(/\bbg-(?:black|zinc-\d+)\b/)
    end
  end

  describe "label association" do
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)
      labels = doc.css("label")
      control_ids = doc.css("input, select, textarea").filter_map { |n| n["id"] }

      expect(labels.size).to eq(2), "обидва поля пароля мусять мати мітку — інакше пін судить половину"

      orphans = labels.reject { |l| l["for"].present? && control_ids.include?(l["for"]) }
      expect(orphans.map { |l| l.text.strip }).to be_empty
    end
  end

  describe "form structure" do
    it "renders form element" do
      expect(html).to include("<form")
    end

    it "posts to reset_password path" do
      expect(html).to include("reset_password")
    end
  end
end
