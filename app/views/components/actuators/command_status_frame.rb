# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Actuators
  # [I18N.2 · клас 2 «viewer-driven pull»] Обгортка статусу команди, що робить
  # ціль броадкасту locale-НЕЗАЛЕЖНОЮ.
  #
  # Пара до `CommandStatusFrameStub`, дзеркало прецеденту `Wallets::BalanceFrame`:
  #   · СТОРІНКА (тут)  — фрейм БЕЗ `src`, із бейджем усередині;
  #   · БРОАДКАСТ (стаб) — той самий id, зі `src`, порожній;
  #   · ВІДПОВІДЬ ендпоінта — знову цей клас, знову БЕЗ `src`.
  #
  # ⚠️ Останнє — не «щоб не було нескінченного циклу». Turbo розпізнає фрейм, чий
  # `src` вказує на себе: кидає `Matching <turbo-frame> element has a source URL
  # which references itself`, ловить цю помилку й підставляє ПОРОЖНІЙ frame-елемент.
  # Тобто ціна помилки — назавжди порожня клітинка плюс тиха console.error, а не
  # шторм запитів. Помилка тихіша, ніж здається, і тому небезпечніша.
  #
  # ⚠️ Свідоме відхилення від прецеденту гаманця: там сторінка теж ставить `src`
  # (lazy-load дорогого балансу). Тут — НІ. Дані вже в `@commands` контролера, а
  # рядків до 20: двадцять lazy-фреймів дали б двадцять GET на першому ж
  # відкритті сторінки заради того, що вже є в пам'яті.
  class CommandStatusFrame < ApplicationComponent
    # ⚠️ id фрейма ≠ id бейджа всередині — точно як `wallet_balance_frame_{id}`
    # обгортає `wallet_balance_{id}`. Якби вони збіглися, у DOM був би дубль id, а
    # ціллю броадкасту мусить бути саме ФРЕЙМ (він несе `src`), не його вміст.
    def self.dom_id(command_id) = "command_status_frame_#{command_id}"

    def initialize(command:)
      @command = command
    end

    def view_template
      turbo_frame_tag self.class.dom_id(@command.id) do
        render Actuators::CommandStatusBadge.new(command: @command)
      end
    end
  end
end
