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
          "cancelled"    => "bg-status-neutral text-status-neutral-text opacity-50",
          # AASM: Gateway states
          "idle"         => "bg-status-neutral text-status-neutral-text",
          "updating"     => "bg-status-warning text-status-warning-text animate-pulse",
          "maintenance"  => "bg-status-info text-status-info-text",
          "faulty"       => "bg-status-danger text-status-danger-text",
          # AASM: Tree states
          "dormant"      => "bg-status-warning text-status-warning-text",
          "removed"      => "bg-status-neutral text-status-neutral-text opacity-50",
          "deceased"     => "bg-status-danger text-status-danger-text line-through",
          # AASM: Actuator states
          "offline"            => "bg-status-neutral text-status-neutral-text",
          "maintenance_needed" => "bg-status-warning text-status-warning-text",
          # Codex::Node lifecycle_status (docs/04_01 §7b)
          "mythical"   => "bg-status-info text-status-info-text",
          "extinct"    => "bg-status-neutral text-status-neutral-text opacity-50",
          "endangered" => "bg-status-warning text-status-warning-text",
          "thriving"   => "bg-status-success text-status-success-text",
          "destroyed"  => "bg-status-danger text-status-danger-text line-through",
          "unknown"    => "bg-status-neutral text-status-neutral-text"
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
