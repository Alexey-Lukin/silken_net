# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Passwords::Forgot do
  let(:html) { render_component }

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
