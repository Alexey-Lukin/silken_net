# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passwords::Forgot do
  let(:html) { render_component }

  # 🔴 [UI.3] Див. `provisioning/new_spec` — периметр носія був третиною поверхні.
  it "associates every label with a real form control" do
    doc = Nokogiri::HTML5.fragment(html)

    expect(doc.css("label")).not_to be_empty, "no labels rendered — the pin would be vacuous"
    expect(LabelAssociation.orphan_labels(doc).map { |l| l.text.strip }).to be_empty
  end

  describe "header" do
    it "renders Recovery heading" do
      expect(html).to include("Recovery")
    end

    it "renders Password Reset Protocol subtitle" do
      expect(html).to include("Password Reset Protocol")
    end
  end

  describe "form fields" do
    it "renders Email Address label" do
      expect(html).to include("Email Address")
    end

    it "renders email input field" do
      expect(html).to include('type="email"')
    end

    it "renders email placeholder" do
      expect(html).to include("architect@silken.net")
    end
  end

  describe "submit button" do
    it "renders SEND RESET LINK button" do
      expect(html).to include("SEND RESET LINK")
    end
  end

  describe "back to login link" do
    it "renders Back to Login Portal link" do
      expect(html).to include("Back to Login Portal")
    end
  end

  # ⚠️ Блок «flash messages» знято разом із предметом [SEC.25]. Компонент приймав
  # два kwarg'и й чесно їх рендерив, але жоден викликач їх не передавав — обидві
  # гілки були мертві з народження, і живими їх тримали саме ці три приклади.
  # Повідомлення цієї сторінки приходять редиректом і належать `FlashMessages`.

  # 🔴 [UI.3] Ця сторінка була ЧОРНОЮ в обох темах (`bg-black` на корені, ніде не
  # оголошено), і на ній: мітки полів та лінк «назад» на `emerald-900` — **2.18:1**,
  # підзаголовок **3.91**, placeholder **1.31**. Форма відновлення пароля, тобто шлях,
  # який ARCH.60 щойно зробив живим, дротувавши SMTP.
  #
  # ⚠️ Пін НЕГАТИВНИЙ на родину + позитивний liveness: перелік очікуваних класів довелось
  # би правити з кожним рефактором і він мовчав би про новий сайт.
  # 🔒 Стеля: судиться ТЕКСТ. Watermark-сітка лишається сирою — `aria-hidden`-декорація.
  # ⚠️ Тут доти стояло, що `text-gaia-primary` на CTA «входить у відому когорту
  # бренд-як-текст» — когорту ЗАКРИТО 2026-08-18: підпис кнопки їде на
  # `--gaia-primary-strong` (2.28 → 4.93 у світлій). Числа й регресію тримає
  # `spec/features/auth_contrast_spec.rb`, тут лишається лише token-дисципліна.
  describe "token discipline (contrast)" do
    it "рендерить текст на токенах і має ВЛАСНУ поверхню" do
      expect(html).to include("bg-gaia-surface-base"), "корінь без поверхні — пара fg/bg невідома"
      expect(html).to include("text-gaia-text-strong")
      expect(html).to include("text-gaia-text-subtle")

      expect(html).not_to match(/\btext-(?:white|(?:gray|zinc|neutral|slate|stone)-\d+|emerald-\d+)\b/)
      expect(html).not_to match(/\bbg-(?:black|zinc-\d+)\b/)
    end
  end

  # 🔴 Приклади вище пінять ТЕКСТ мітки й нічого не кажуть про звʼязок із полем — саме
  # тому голий `<label>` жив тут непоміченим (WCAG 1.3.1, сильніше за 3.3.1, заради
  # якого пункт писався). Форму взято з `Sessions::New`, де це вже еталон.
  describe "label association" do
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)
      labels = doc.css("label")
      control_ids = doc.css("input, select, textarea").filter_map { |n| n["id"] }

      expect(labels).not_to be_empty, "no labels rendered — the pin would be vacuous"

      orphans = labels.reject { |l| l["for"].present? && control_ids.include?(l["for"]) }
      expect(orphans.map { |l| l.text.strip }).to be_empty
    end
  end

  describe "form action" do
    it "posts to the forgot password path" do
      expect(html).to include("forgot_password")
    end
  end

  describe "structure" do
    it "renders the form element" do
      expect(html).to include("<form")
    end
  end
end
