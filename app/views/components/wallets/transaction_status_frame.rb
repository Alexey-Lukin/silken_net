# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Wallets
  # [I18N.2 · клас 2 «viewer-driven pull»] Комірка статусу транзакції, зроблена
  # locale-НЕЗАЛЕЖНОЮ для броадкасту.
  #
  # Пара до `TransactionStatusFrameStub`; ролі скопійовані з прецеденту
  # `Actuators::CommandStatusFrame(Stub)`, а не з гаманцевого балансу:
  #   · СТОРІНКА (цей клас) — фрейм БЕЗ `src`, із бейджем усередині;
  #   · БРОАДКАСТ (стаб)   — той самий id, зі `src`, із пульс-плейсхолдером;
  #   · ВІДПОВІДЬ ендпоінта — знову цей клас, знову БЕЗ `src`.
  #
  # ⚠️ Чому сторінковий фрейм без `src` — це вибір, а не копія: у гаманця баланс
  # ліниться, бо він дорогий, а тут дані вже лежать у `@transactions` контролера,
  # і сторінка віддає до 50 рядків. Копія «як у балансу» дала б 50 GET на першому
  # ж відкритті леджера заради того, що вже в памʼяті.
  #
  # ⚠️ `register_element`, а НЕ `turbo_frame_tag`: хелпер Phlex::Rails ходить у
  # view-context, а рядок-батько рендериться в броадкасті через `.call`, де його
  # не існує. Тут контекст є завжди, але однакова форма в обох класах знімає цілий
  # клас помилок «працює на сторінці, падає в продюсері».
  class TransactionStatusFrame < ApplicationComponent
    register_element :turbo_frame

    # Один дім target-id на обидва боки тракту (`04_04 §8.3`): рукописний рядок
    # по два боки вже давав у цьому репо мертві цілі. ⚠️ id фрейма НЕ дорівнює
    # id бейджа всередині — інакше в DOM був би дубль, а ціллю мусить бути саме
    # фрейм, бо він несе `src`.
    def self.dom_id(tx_id) = "tx_status_frame_#{tx_id}"

    def initialize(tx:)
      @tx = tx
    end

    def view_template
      turbo_frame(id: self.class.dom_id(@tx.id)) do
        render Views::Shared::UI::StatusBadge.new(status: @tx.status)
      end
    end
  end
end
