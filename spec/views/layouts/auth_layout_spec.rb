# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Asset-resolving stubs are applied globally via spec/support/layout_asset_stubs.rb.

RSpec.describe AuthLayout do
  let(:content_stub) do
    Class.new(ApplicationComponent) do
      def view_template
        div(id: "test-content") { "Auth Content Rendered" }
      end
    end.new
  end

  def render_layout(title: "Access Portal", content: nil)
    ApplicationController.renderer.render(
      component_class.new(title: title, content: content),
      layout: false
    )
  end

  describe "page title" do
    it "renders the title with Silken Net prefix" do
      html = render_layout(title: "Reset Password")
      expect(html).to include("Silken Net // Reset Password")
    end

    it "defaults the title to Access Portal" do
      html = render_layout
      expect(html).to include("Silken Net // Access Portal")
    end
  end

  describe "document structure" do
    let(:html) { render_layout }

    it "renders as a full HTML document" do
      expect(html).to match(/<!doctype html>/i)
    end

    # 🔴 [UI.1] Доти тут пінився хардкод `h-full dark` — auth-екрани були
    # СВІДОМО однотемними, бо світла тема ламалась, і канон легалізував таку
    # однотемність за умови, що вона ОГОЛОШЕНА. Тумблер знято, тему обирає
    # середовище, і хардкод став єдиним місцем у дереві, яке цьому опиралось:
    # людина зі світлою ОС отримувала темний екран входу й світлу решту.
    # Пін перевернуто — він стереже, щоб клас не повернувся тихцем.
    it "declares no hardcoded theme — auth pages follow the environment too" do
      expect(html).to include("h-full")
      expect(html).not_to include("h-full dark")
    end

    it "renders the viewport meta tag" do
      expect(html).to include('name="viewport"')
    end
  end

  describe "content rendering" do
    it "renders the content component inside the body" do
      html = render_layout(content: content_stub)
      expect(html).to include("Auth Content Rendered")
      expect(html).to include("test-content")
    end

    it "renders without errors when content is nil" do
      html = render_layout(content: nil)
      expect(html).to include("<body")
      expect(html).not_to include("test-content")
    end
  end

  describe "design system compliance" do
    let(:html) { render_layout(content: content_stub) }

    it "uses gaia design tokens for the body background and text" do
      expect(html).to include("bg-gaia-surface-base")
      expect(html).to include("text-gaia-primary")
    end
  end
end
