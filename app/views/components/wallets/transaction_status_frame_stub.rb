# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Wallets
  # [I18N.2 · клас 2] Locale-ВІЛЬНИЙ payload комірки статусу транзакції.
  #
  # Чому не шлемо сам `StatusBadge`: `html:` — звичайний аргумент, тож Phlex-рендер
  # їде **eagerly в процесі-ПРОДЮСЕРА**, де `LocaleSettable` (це `before_action`)
  # не відпрацював ані в Sidekiq, ані в `ApplicationController.renderer`. Бейдж
  # перекладає і мітку, і `aria-label`, отже в спільний стрім полетіла б локаль
  # ТОГО, ХТО СПРИЧИНИВ перехід, — усім підписникам гаманця одразу.
  #
  # 🔴 І гейт цього НЕ спіймав би: `broadcast_payload_invariance_spec` рахує `t()`
  # лише у ВЛАСНОМУ джерелі broadcast-компонента й свідомо не ходить у дочірні
  # (стеля названа в його шапці). Тобто без цієї пари дротування бейджа в рядок
  # лишилось би ЗЕЛЕНИМ — доказ довелось будувати окремо, і він живе в спеці цього
  # класу: побайтова тотожність рендеру в усіх налаштованих локалях.
  #
  # ⚠️ `register_element`, а НЕ `turbo_frame_tag`: батьківський рядок рендериться
  # в броадкасті через `.call`, де view-контексту не існує (`NoMethodError … for nil`).
  #
  # 🔴 Плейсхолдер усередині — не косметика: порожній фрейм на час фетчу зсуває
  # висоту рядка. Пульс тримає місце бейджа й **не несе жодного слова**, тобто
  # лишається locale-інваріантним. Кістка — спільний `Skeleton::BONE`, а не сам
  # компонент: той рендерить блок, а місце бейджа рядкове.
  class TransactionStatusFrameStub < ApplicationComponent
    register_element :turbo_frame

    def initialize(tx_id:, src:)
      @tx_id = tx_id
      @src = src
    end

    def view_template
      turbo_frame(id: TransactionStatusFrame.dom_id(@tx_id), src: @src, loading: "eager") do
        span(
          class: tokens(Views::Shared::UI::Skeleton::BONE, "inline-block w-24 h-4 align-middle"),
          aria_hidden: "true"
        )
      end
    end
  end
end
