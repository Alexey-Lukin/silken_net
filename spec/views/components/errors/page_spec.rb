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

    # 🔴 Пін мусить бути ТОЧНИЙ, а не підрядковий, і це куплено просто зараз: доти тут
    # стояло `include("status-warning")`, а `status-warning-accent` МІСТИТЬ цей підрядок —
    # тобто після переходу на акцент приклад лишився зеленим, не помітивши зміни, і так
    # само лишився б зеленим на відкоті в пастельний токен, тобто рівно на дефекті, який
    # він мав би стерегти (пастельний ФОН як сигнал → **1.07:1** у світлій темі).
    # Негативна половина обовʼязкова: без неї пара «пастельний ⊥ акцентний» не судиться.
    it "фарбує 403 у warning — НАСИЧЕНИМ токеном, не пастельним фоном бейджа" do
      html = render_component(heading: "H", message: "M", tone: :warning)

      expect(html).to include("bg-status-warning-accent")
      # ⚠️ `\b` тут НЕ межа: дефіс — не-словесний символ, тож `\bbg-status-warning\b`
      # спрацьовує ВСЕРЕДИНІ `bg-status-warning-accent` і робить пін вічно-червоним.
      # Межу класу токенів задає негативний lookahead, не `\b`.
      expect(html).not_to match(/\bbg-status-warning(?![-\w])/)
    end

    it "фарбує 404 стриманіше — це не аварія" do
      html = render_component(heading: "H", message: "M", tone: :info)

      # [UI.1 порція 10] Умова відкладення настала: info-тон бере власний
      # accent-токен (сигнальна хвиля завела його 08-20), сирий emerald знято.
      expect(html).to include("status-info-accent")
      expect(html).not_to include("status-danger-accent")
    end

    # Fail-closed на невідомому тоні: сторінка помилки не сміє впасти від власного
    # аргументу — вона і так остання лінія.
    it "падає назад у danger на невідомому тоні, а не кидає" do
      html = render_component(heading: "H", message: "M", tone: :nonsense)

      expect(html).to include("status-danger-accent")
    end
  end

  # 🔴 [UI.3] Пінів на ТЕКСТ цієї сторінки не було ЖОДНОГО — і це пояснює, чому дефект
  # прожив стільки: сюїта стерегла тон гліфа (`emerald-700`) і мовчала про те, чи напис
  # узагалі видно. Компонент не має власного фону, тож поверхня приходить із `<body>`
  # (`--gaia-surface-base`): `text-white` давав **1.04:1** у світлій темі, а
  # `text-emerald-300/80` — **1.37:1**. Тобто 404/403/500 показували порожній екран тому,
  # у кого світла ОС, — на поверхні, яка є ОСТАННЬОЮ лінією й іншого способу сказати
  # людині, що сталось, не має.
  #
  # ⚠️ Альфу `/80` знято разом із кольором навмисно: прозорість на змістовному тексті —
  # прихований множник контрасту, якого не бачить ЖОДЕН прилад у цьому репо
  # (`design_token_existence_spec` судить існування, браузерний збирач композитить лише
  # стек ФОНІВ). Повернення `text-…/NN` сюди має червоніти як сирий колір.
  #
  # 🔒 Стеля: судиться ТЕКСТ. `TONES` і растрова сітка лишаються сирим emerald свідомо —
  # обидва `aria-hidden`-декорація, тем-інваріантна за задумом; чи має тон `:info` їхати
  # на `status-info`, це питання ГУЧНОСТІ й окрема ⚖️ (`00_07` UI.3).
  describe "token discipline (contrast)" do
    it "рендерить текст на токенах — сторінка помилки видима в ОБОХ темах" do
      html = render_component(heading: "SYSTEM FAULT", message: "Щось пішло не так")

      # liveness: обидва текстові вузли справді відрендерились
      expect(html).to include("text-gaia-text-strong"), "заголовок без токена — пін вакуумний"
      expect(html).to include("text-gaia-text-muted")

      expect(html).not_to match(/\btext-(?:white|(?:gray|zinc|neutral|slate|stone)-\d+|emerald-\d+)\b/)
      expect(html).not_to match(%r{\btext-[\w-]+/\d+\b})
    end
  end

  def render_component(**kwargs)
    ApplicationController.renderer.render(described_class.new(**kwargs), layout: false)
  end
end
