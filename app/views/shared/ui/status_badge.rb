# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      class StatusBadge < ApplicationComponent
        STYLES = {
          # AASM: BlockchainTransaction states
          "pending"      => "bg-status-warning text-status-warning-text",
          "processing"   => "bg-status-warning text-status-warning-text animate-pulse",
          "sent"         => "bg-status-info text-status-info-text",
          "confirmed"    => "bg-status-success text-status-success-text",
          "failed"       => "bg-status-danger text-status-danger-text",
          "manual_review" => "bg-status-warning text-status-warning-text animate-pulse",
          # Спільний «здоровий» стан п'яти доменів (Tree · Gateway · NaasContract ·
          # Actuator · ParametricInsurance) — усі п'ять кажуть цим словом «усе гаразд».
          # Доти запис належав `EwsAlert` і означав ПРОТИЛЕЖНЕ (відкрита тривога =
          # погано), тож здорове дерево дістало б червоне. Носія тієї колізії немає:
          # `EwsAlert#status` як показане СЛОВО зник разом з `Alerts::Badge`, а решта
          # його UI ходить булевими предикатами (`status_resolved?`).
          "active"       => "bg-status-success text-status-success-text",
          # AASM: NaasContract states
          "draft"        => "bg-status-neutral text-status-neutral-text",
          "fulfilled"    => "bg-status-success text-status-success-text",
          "breached"     => "bg-status-danger text-status-danger-text",
          # 🔴 [UI.3] Доти тут стояла `opacity-50` — і вона була ЄДИНИМ, що
          # відрізняло «cancelled» від «draft», ціною 6.87:1 → **2.25:1** у
          # світлій темі й 5.81:1 → 2.37:1 у темній (поріг 4.5:1 для `text-tiny`).
          # `line-through` бере ту саму роль із сусіднього рядка цієї ж мапи
          # (`deceased`), розрізняє стани БЕЗ кольору взагалі й контрасту не
          # чіпає — тобто дискримінатор став сильнішим, а не слабшим.
          "cancelled"    => "bg-status-neutral text-status-neutral-text line-through",
          # AASM: Gateway states
          "idle"         => "bg-status-neutral text-status-neutral-text",
          "updating"     => "bg-status-warning text-status-warning-text animate-pulse",
          "maintenance"  => "bg-status-info text-status-info-text",
          "faulty"       => "bg-status-danger text-status-danger-text",
          # AASM: Tree states
          "dormant"      => "bg-status-warning text-status-warning-text",
          "removed"      => "bg-status-neutral text-status-neutral-text line-through",
          "deceased"     => "bg-status-danger text-status-danger-text line-through",
          # AASM: Actuator states
          "offline"            => "bg-status-neutral text-status-neutral-text",
          "maintenance_needed" => "bg-status-warning text-status-warning-text"
        }.freeze

        DEFAULT_STYLE = "bg-status-neutral text-status-neutral-text"

        SCOPE = "ui.status"

        # ОДНА деривація ключа на застосунок (`04_04 §12.14`). Поверхня, якій
        # потрібна мітка БЕЗ бейджа (рядок таблиці деталей, матриця стану
        # актуатора), кличе цей метод, а не будує `"ui.status.#{value}"` сама:
        # друга деривація означає, що друкарська помилка в одній із них лишається
        # зеленою назавжди — обидві сторони «present» для будь-якого parity-гейта.
        # Fail-open на сирому значенні свідомий: новий AASM-стан має рендеритись
        # рівно, ще до того як мітка доїде в локалі.
        def self.label(status)
          value = status.to_s
          I18n.t("#{SCOPE}.#{value}", default: value)
        end

        def initialize(status:, id: nil, **attrs)
          @status = status.to_s
          @id = id
          @extra_class = attrs[:class]
        end

        def view_template
          style = STYLES.fetch(@status, DEFAULT_STYLE)
          label = self.class.label(@status)

          span(
            id: @id,
            role: "status",
            aria_label: t("ui.status.aria_label", status: label),
            class: tokens(badge_classes, style, @extra_class)
          ) { label }
        end

        private

        def badge_classes
          "px-2 py-0.5 rounded text-tiny font-bold uppercase tracking-widest"
        end
      end
    end
  end
end
