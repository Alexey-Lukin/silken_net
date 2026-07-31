# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Attunements::Toggle do
  # Рендер через `renderer`, а не `.call`: `button_to` потребує справжнього
  # view-контексту ([`04_06 §A.3`]).
  #
  # ⚠️ Стаб маршрут-хелпера знято СВІДОМО. Доти він визначав рівно ОДИН із двох
  # потрібних шляхів — той, яким компонент помилково слав обидві дії, — тобто
  # робив правильний маршрут невиразним у принципі: спека не могла почервоніти
  # навіть теоретично. Це сусідній підвид до §A.10а: стаб не вигадував метод,
  # якого нема, а покривав ПІДМНОЖИНУ реальної поверхні ([UI.7]).
  def render_toggle(node:, attuned:, count:)
    ApplicationController.renderer.render(
      component_class.new(node: node, current_user_attuned: attuned, count: count),
      layout: false
    )
  end

  let(:node) do
    OpenStruct.new(id: 42, slug: "cherkasy-bir", attunement_count: 7).tap do |n|
      n.define_singleton_method(:to_param) { n.slug }
    end
  end

  # Справжні хелпери — не літерали: пін мусить упасти, якщо маршрут перейменують.
  let(:routes)         { Rails.application.routes.url_helpers }
  let(:attune_path)    { routes.api_v1_codex_node_attunements_path(node.slug) }
  let(:un_attune_path) { routes.api_v1_codex_node_my_attunement_path(node.slug) }

  describe "rendering" do
    it "renders the count using the public DOM id" do
      html = render_toggle(node: node, attuned: false, count: 7)
      expect(html).to include('id="codex_node_42_attunement_count"')
      expect(html).to include(">7<")
    end

    it "aims an attune at the POST collection route" do
      html = render_toggle(node: node, attuned: false, count: 0)
      expect(html).to include(">Attune<")
      expect(html).to include(%(action="#{attune_path}"))
      expect(html).to include('method="post"')
    end

    # Пін КЛАСУ UI.7: дві дії не ділять адресу. Доти обидві гілки цілили в
    # колекційний маршрут, де зареєстровано лише POST, тож зняття резонансу
    # летіло в 404 — а спека лишалась зеленою, бо перевіряла дієслово, а не ЦІЛЬ.
    it "aims the un-attune at the dedicated attunements/me route, not the POST-only collection" do
      html = render_toggle(node: node, attuned: true, count: 1)
      expect(html).to include(">Attuned<")
      expect(html).to include(%(action="#{un_attune_path}"))
      expect(html).to include('value="delete"')
      expect(html).not_to include(%(action="#{attune_path}"))
    end

    it "does not wire any Stimulus controller (Turbo Stream handles live updates)" do
      html = render_toggle(node: node, attuned: true, count: 1)
      expect(html).not_to include('data-controller=')
    end

    it "renders the 'Attunement' section title" do
      html = render_toggle(node: node, attuned: false, count: 3)
      expect(html).to include(">Attunement<")
    end
  end

  describe "edge cases" do
    it "renders a zero count as '0' with no special-cased empty state" do
      html = render_toggle(node: node, attuned: false, count: 0)
      expect(html).to include(">0<")
    end

    it "treats a nil current_user_attuned the same as false (renders the Attune/POST button)" do
      html = render_toggle(node: node, attuned: nil, count: 2)
      expect(html).to include(">Attune<")
      expect(html).to include('method="post"')
      expect(html).not_to include("bg-status-success")
    end
  end

  describe "accessibility" do
    it "submits via a real <button type=\"submit\"> so the toggle works without JavaScript" do
      html = render_toggle(node: node, attuned: false, count: 0)
      expect(html).to include("<button")
      expect(html).to include('type="submit"')
    end

    # ⚠️ CSRF-токена тут НЕ пінимо, і це виміряна межа, а не пропуск: форгері-захист
    # у test-env вимкнено (`config/environments/test.rb`), а `ApplicationController
    # .renderer` не має справжньої сесії — тож `button_to` токена не рендерить навіть
    # при примусово ввімкненому захисті (перевірено). Половина «працює без JS» живе
    # в request-спеці вузла, разом із пінами цілі — тим самим правилом, що й §A.10а.
  end

  describe "design system compliance" do
    it "uses gaia-* / status-* tokens, not raw bg-white / text-gray-*" do
      html = render_toggle(node: node, attuned: true, count: 5)
      expect(html).not_to include("bg-white")
      expect(html).not_to match(/text-gray-\d+/)
      expect(html).to include("text-gaia-text-muted")
    end

    it "applies the success token when attuned" do
      html = render_toggle(node: node, attuned: true, count: 5)
      expect(html).to include("bg-status-success")
    end

    it "wires focus-visible:ring-2 for keyboard accessibility" do
      html = render_toggle(node: node, attuned: false, count: 0)
      expect(html).to include("focus-visible:ring-2")
    end
  end
end
