# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Wallets
  # [I18N.2 · клас 2 «viewer-driven pull»] Локаль-ВІЛЬНИЙ payload броадкасту балансу.
  #
  # Чому не шлемо сам `BalanceDisplay`: `html:` — звичайний аргумент, тож Phlex-рендер
  # їде **eagerly в процесі-ПРОДЮСЕРА**, де `LocaleSettable` (це `before_action`) не
  # відпрацював ані в Sidekiq, ані в `ApplicationController.renderer`. `BalanceDisplay`
  # несе шість `t()`-міток, отже в спільний стрім полетіла б локаль ТОГО, ХТО КЛАЦНУВ,
  # усім підписникам одразу. Дозволені класи й заборона локаль-фан-ауту — `04_04 §8.1а`.
  #
  # Замість HTML шлемо порожній `<turbo-frame>` з тим самим id і зі `src`: кожен клієнт
  # тягне фрагмент **власним** запитом, де і локаль його, і Pundit-авторизація його.
  # Ціна = O(реальних глядачів), нуль залежності від розміру каталогу локалей.
  #
  # Ланцюг замикається сам: відповідь `WalletsController#balance` рендерить
  # `Wallets::BalanceFrame` — фрейм **без** `src`, тож другого фетчу не буде.
  #
  # ⚠️ `register_element`, а НЕ `turbo_frame_tag`: хелпер Phlex::Rails ходить у
  # view-context, якого при `.call` з моделі не існує (перевірено рантаймом —
  # `NoMethodError: undefined method 'turbo_frame_tag' for nil`), а броадкаст
  # рендериться саме через `.call`.
  class BalanceFrameStub < ApplicationComponent
    register_element :turbo_frame

    def initialize(wallet_id:, src:)
      @wallet_id = wallet_id
      @src = src
    end

    def view_template
      turbo_frame(id: Wallets::BalanceFrame.dom_id(@wallet_id), src: @src, loading: "eager")
    end
  end
end
