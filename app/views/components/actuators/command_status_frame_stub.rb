# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Actuators
  # [I18N.2 · клас 2] Locale-ВІЛЬНИЙ payload броадкасту статусу команди.
  #
  # Чому не шлемо сам `CommandStatusBadge`: `html:` — звичайний аргумент, тож
  # Phlex-рендер їде **eagerly в процесі-ПРОДЮСЕРА**, де `LocaleSettable` не
  # відпрацював (це `before_action`, а тут Sidekiq або coap-демон). Бейдж несе
  # `t()`, отже в спільний стрім полетіла б локаль того, ХТО КЛАЦНУВ, — усім
  # підписникам одразу. Заборона локаль-фан-ауту → `04_04 §8.1а`.
  #
  # ⚠️ `register_element`, а НЕ `turbo_frame_tag`: хелпер Phlex::Rails ходить у
  # view-context, якого при `.call` з воркера не існує (`NoMethodError ... for nil`),
  # а броадкаст рендериться саме через `.call`.
  #
  # 🔴 Плейсхолдер усередині — не косметика. Порожній фрейм на час фетчу зсуває
  # рядок таблиці й блимає дірою; пульс тримає місце бейджа й **не несе жодного
  # слова**, тобто лишається locale-інваріантним. Готовий `Views::Shared::UI::Skeleton`
  # тут НЕ годиться саме тому, що він локалізований (`t(".loading")`).
  class CommandStatusFrameStub < ApplicationComponent
    register_element :turbo_frame

    def initialize(command_id:, src:)
      @command_id = command_id
      @src = src
    end

    def view_template
      turbo_frame(id: CommandStatusFrame.dom_id(@command_id), src: @src, loading: "eager") do
        span(
          class: "inline-block w-20 h-4 rounded bg-gaia-surface-elevated animate-pulse align-middle",
          aria_hidden: "true"
        )
      end
    end
  end
end
