# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      class ActionBadge < ApplicationComponent
        STYLES = {
          destructive: "bg-status-danger text-status-danger-text",
          mutative:    "bg-status-warning text-status-warning-text",
          creative:    "bg-status-active text-status-active-text",
          neutral:     "bg-status-neutral text-status-neutral-text"
        }.freeze

        # [I18N.1] Дім міток дії аудиту — РЕНДЕРЕР (прецедент
        # `DashboardLayout.breadcrumb_segment_label`: рендерер і є дім мапи).
        # `AuditLog#action` — вільний varchar, не enum, тож парність гейтом
        # `enum_label_parity_spec` недосяжна за побудовою (множини не дає
        # `Model.enum.keys`); повноту тримають fail-open на `humanize` (нова
        # дія видима одразу сирою) + свідок у не-базовій локалі.
        # Повний шлях, не `t(".…")`: автоскоуп дав би `views.shared.ui.*`,
        # а shared/ui живе під `ui.*` (конвенція StatusBadge).
        ACTION_SCOPE = "ui.action_badge.actions"
        TRANSITION_SCOPE = "ui.action_badge.transitions"

        # Три інтерпольовані родини `<субʼєкт>_to_<стан>`. Стан кожної
        # резолвиться домом СВОЄЇ родини: naas/blockchain-стани живуть у
        # спільному `ui.status` повністю (5/5 і 6/6), а стани НАКАЗІВ — ні
        # (3/5), тож для них дім `CommandStatusBadge.label`; частковий резолв
        # через спільний bag виглядав би повним (пастка I18N.1).
        TRANSITION_FAMILIES = {
          "naas_contract_to_" => :naas_contract,
          "actuator_to_"      => :actuator_command,
          "blockchain_tx_to_" => :blockchain_tx
        }.freeze

        # Мітка дії. `metadata` потрібна лише event-формі `blockchain_tx_{event}`
        # (писач кладе "to" завжди — `blockchain_transaction.rb`); без неї
        # (старі рядки, чужі фікстури) стан чесно падає на сирий суфікс.
        def self.label(action, metadata: nil)
          action = action.to_s
          family = transition_family(action)
          return I18n.t("#{ACTION_SCOPE}.#{action}", default: action.humanize) unless family

          state = transition_state(action, metadata)
          I18n.t("#{TRANSITION_SCOPE}.#{family}", state: state_label(family, state))
        end

        def self.transition_family(action)
          TRANSITION_FAMILIES.each { |prefix, fam| return fam if action.start_with?(prefix) }
          action.start_with?("blockchain_tx_") ? :blockchain_tx : nil
        end

        def self.transition_state(action, metadata = nil)
          TRANSITION_FAMILIES.each_key { |p| return action.delete_prefix(p) if action.start_with?(p) }
          return nil unless action.start_with?("blockchain_tx_")

          metadata&.dig("to").presence || action.delete_prefix("blockchain_tx_")
        end

        def self.state_label(family, state)
          return Actuators::CommandStatusBadge.label(state) if family == :actuator_command

          Views::Shared::UI::StatusBadge.label(state)
        end
        private_class_method :state_label

        # Рід КОЖНОЇ відомої дії — плоскою мапою, невідома → neutral (fail-open;
        # доти підрядкові CRUD-регекси клали 19 із 21 реальних значень у neutral,
        # бо писані під `user_deleted`-стиль, якого цей домен не має).
        LITERAL_STYLES = {
          "acting_organization_switched" => :mutative,
          "actuator_bulk_cancelled"      => :destructive,
          "factory_flash"                => :creative,
          "hardware_key_rotated"         => :mutative,
          "maintenance_photo_purged"     => :destructive,
          "slash_verdict_burn"           => :destructive,
          "slash_verdict_evasion"        => :destructive,
          "slash_verdict_frozen"         => :destructive,
          "stream_epoch_rotated"         => :mutative,
          "system_parameter_changed"     => :mutative,
          "user_role_changed"            => :mutative
        }.freeze

        DESTRUCTIVE_STATES = %w[failed breached cancelled].freeze
        CREATIVE_STATES    = %w[confirmed fulfilled active].freeze

        def initialize(action:, metadata: nil, **attrs)
          @action = action.to_s
          @metadata = metadata
          @extra_class = attrs[:class]
        end

        def view_template
          # aria-label тут БУВ і знятий свідомо: видимий текст тепер сам є
          # локалізованою міткою, а aria-label над локалізованим видимим текстом
          # перекриває accessible name (ратифіковане правило I18N.1).
          span(
            role: "status",
            class: tokens(badge_classes, style_for_action, @extra_class)
          ) { self.class.label(@action, metadata: @metadata) }
        end

        private

        def badge_classes
          "px-2 py-0.5 text-mini font-bold uppercase tracking-widest"
        end

        def style_for_action
          state = self.class.transition_state(@action, @metadata)
          kind =
            if state
              if DESTRUCTIVE_STATES.include?(state) then :destructive
              elsif CREATIVE_STATES.include?(state) then :creative
              else :mutative
              end
            else
              LITERAL_STYLES.fetch(@action, :neutral)
            end
          STYLES[kind]
        end
      end
    end
  end
end
