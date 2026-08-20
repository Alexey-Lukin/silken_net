# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module AuditLogs
  class Show < ApplicationComponent
    def initialize(log:)
      @log = log
    end

    def view_template
      div(class: "space-y-8") do
        render_header
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-8") do
            render_details_table
            render_metadata_panel
          end
          div(class: "space-y-8") do
            render_actor_info
            render_target_info
          end
        end
      end
    end

    private

    def render_header
      div(class: "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }
        div(class: "flex justify-between items-start") do
          div do
            p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-2") { t(".event_record") }
            h2(class: "text-3xl font-extralight tracking-tighter text-white") { Views::Shared::UI::ActionBadge.label(@log.action, metadata: @log.metadata) }
            p(class: "text-tiny font-mono text-gray-600 mt-2") { t(".tx_id_line", id: @log.id, at: @log.created_at.strftime("%d.%m.%Y %H:%M:%S UTC")) }
          end
          render Views::Shared::UI::ActionBadge.new(action: @log.action, metadata: @log.metadata)
        end
      end
    end

    def render_details_table
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        table(role: "table", class: "w-full text-left font-mono text-compact") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".details.field") }
              th(scope: "col", class: "p-4") { t(".details.value") }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            # [I18N.1] Тут СИРИЙ токен свідомо — пара «людське ⊥ машинне»:
            # заголовок і бейдж угорі несуть локалізовану мітку, а цей рядок
            # деталей лишається технічним ідентифікатором (греп/супорт), як
            # ключі metadata-дампа нижче.
            detail_row(t(".details.action"), @log.action)
            detail_row(t(".details.performed_by"), @log.user&.full_name || t(".system_user"))
            detail_row(t(".details.target_type"), @log.auditable_type || "—")
            detail_row(t(".details.target_id"), @log.auditable_id || "—")
            detail_row(t(".details.timestamp"), @log.created_at.strftime("%d.%m.%Y %H:%M:%S UTC"))
          end
        end
      end
    end

    def detail_row(label, value)
      tr(class: "hover:bg-emerald-950/10") do
        td(class: "p-4 text-emerald-500") { label }
        td(class: "p-4 text-gray-300") { value.to_s }
      end
    end

    def render_metadata_panel
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { t(".metadata.title") }
        if @log.metadata.present? && @log.metadata.any?
          div(class: "space-y-2 font-mono text-tiny") do
            @log.metadata.each do |key, value|
              div(class: "flex justify-between items-center py-1 border-b border-emerald-900/20") do
                span(class: "text-gray-600 uppercase") { key.to_s }
                span(class: "text-emerald-400") { metadata_value_label(key, value) }
              end
            end
          end
        else
          p(class: "text-compact text-gray-700 italic") { t(".metadata.empty") }
        end
      end
    end

    # [I18N.1] `from`/`to` в metadata несуть значення, чиї доми міток УЖЕ існують —
    # ведемо кожне у СВІЙ: ролі user_role_changed → `User.role_label`, AASM-статуси
    # (naas_contract_to_*, actuator_to_*) → `StatusBadge.label` (обидва fail-open,
    # тож нестатусне значення — epoch-цілі stream_epoch_rotated — падає на сире).
    # Перетин ролей із ключами ui.status перевірено: порожній. Решта
    # metadata-ключів — технічні ідентифікатори, лишаються сирими свідомо.
    def metadata_value_label(key, value)
      return value.to_s unless %w[from to].include?(key.to_s)
      return User.role_label(value) if @log.action == "user_role_changed"

      Views::Shared::UI::StatusBadge.label(value)
    end

    def render_actor_info
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".actor.title") }
        if @log.user.present?
          div do
            p(class: "text-mini text-gray-600 uppercase mb-1") { t(".actor.name") }
            p(class: "text-compact text-emerald-400 font-mono") { @log.user.full_name }
          end
          div(class: "pt-3 border-t border-emerald-900/30") do
            p(class: "text-mini text-gray-600 uppercase mb-1") { t(".actor.email") }
            p(class: "text-compact text-gray-400") { @log.user.email_address }
          end
          div(class: "pt-3 border-t border-emerald-900/30") do
            p(class: "text-mini text-gray-600 uppercase mb-1") { t(".actor.role") }
            span(class: "px-2 py-0.5 bg-emerald-900 text-emerald-200 text-mini uppercase font-bold") { @log.user.role_label }
          end
        else
          p(class: "text-compact text-gray-700 italic") { t(".actor.system") }
        end
      end
    end

    def render_target_info
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { t(".target.title") }
        if @log.auditable_type.present?
          div(class: "space-y-3 font-mono text-tiny") do
            div(class: "flex justify-between items-center") do
              span(class: "text-gray-600 uppercase") { t(".target.type") }
              span(class: "text-emerald-400") { @log.auditable_type }
            end
            div(class: "flex justify-between items-center") do
              span(class: "text-gray-600 uppercase") { t(".target.id") }
              span(class: "text-emerald-400") { @log.auditable_id.to_s }
            end
          end
        else
          p(class: "text-compact text-gray-700 italic") { t(".target.empty") }
        end
      end
    end
  end
end
