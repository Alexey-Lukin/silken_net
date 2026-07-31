# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.25] Компонент навмисно не має власних `t()` — увесь текст приходить параметром,
# бо він рендериться ЗСЕРЕДИНИ `rescue_from`, де виняток від забутого локаль-ключа
# Rails уже не переловить. Тому спека пінить саме це: що показане = передане.
RSpec.describe Errors::Page do
  describe "rendering" do
    it "показує переданий заголовок і повідомлення дослівно" do
      html = render_component(heading: "Not Found", message: "Tree not found in the forest matrix.")

      expect(html).to include("Not Found")
      expect(html).to include("Tree not found in the forest matrix.")
    end

    it "не тягне власних локаль-ключів — нічого, крім переданого, не рендериться як текст" do
      html = render_component(heading: "X-HEADING", message: "X-MESSAGE")

      # Негативна половина: якби компонент мав власний `t()`, у розмітці зʼявився б
      # або переклад, або `translation missing` — обидва тут заборонені.
      expect(html).not_to include("translation missing")
    end

    it "має семантичний landmark для скрін-рідерів" do
      html = render_component(heading: "H", message: "M")

      expect(html).to include('role="main"')
    end
  end

  describe "тон = вага помилки" do
    it "фарбує 500 у danger" do
      html = render_component(heading: "H", message: "M", tone: :danger)

      expect(html).to include("status-danger-accent")
    end

    it "фарбує 403 у warning" do
      html = render_component(heading: "H", message: "M", tone: :warning)

      expect(html).to include("status-warning")
    end

    it "фарбує 404 стриманіше — це не аварія" do
      html = render_component(heading: "H", message: "M", tone: :info)

      expect(html).to include("emerald-700")
      expect(html).not_to include("status-danger-accent")
    end

    # Fail-closed на невідомому тоні: сторінка помилки не сміє впасти від власного
    # аргументу — вона і так остання лінія.
    it "падає назад у danger на невідомому тоні, а не кидає" do
      html = render_component(heading: "H", message: "M", tone: :nonsense)

      expect(html).to include("status-danger-accent")
    end
  end

  def render_component(**kwargs)
    ApplicationController.renderer.render(described_class.new(**kwargs), layout: false)
  end
end
