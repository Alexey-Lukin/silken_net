# SPDX-License-Identifier: AGPL-3.0-or-later
module Actuators
  class Show < ApplicationComponent
    def initialize(actuator:, commands:)
      @actuator = actuator
      @commands = commands
    end

    def view_template
      # [UI.4] Стрім вузький навмисно: сторінка показує команди ОДНОГО актуатора,
      # тож `[actuator, :commands]`, а не голий `Organization` — ширший стрім був
      # би зайвою адресною книгою, і саме на цій осі UI.4 знайшов крос-тенант-витік
      # («global_events» ніс страхові виплати всіх організацій).
      turbo_stream_from @actuator, :commands

      div(class: "space-y-10") do
        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          # Головна картка стану
          div(class: "lg:col-span-1") do
            # `@commands` уже впорядковані `created_at DESC` контролером, тож
            # найновіша — перша; окремий запит із картки більше не летить.
            render Actuators::Card.new(actuator: @actuator, last_command: @commands.first)
          end

          # Реєстр команд
          div(class: "lg:col-span-2 space-y-4") do
            h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".log_title") }
            render_command_table
          end
        end
      end
    end

    private

    def render_command_table
      # [UI.3] SR-анонс термінальних станів (присуд 2026-08-20: confirmed/failed,
      # polite). Broadcast замінює САМ фрейм — aria-live на ньому гинув би разом
      # із вузлом, тож регіон живе ПОЗА фреймами й існує в DOM до першої зміни.
      # Тексти зібрані сторінкою в локалі ГЛЯДАЧА (Show рендериться в запиті);
      # заглушка броадкасту лишається locale-вільною, подія — turbo:frame-load.
      div(
        data: {
          controller: "command-announcer",
          command_announcer_terminal_value: ActuatorCommand::TERMINAL_STATUSES.to_json,
          command_announcer_messages_value: announcer_messages.to_json,
          action: "turbo:frame-load->command-announcer#announce"
        }
      ) do
        div(
          role: "status", aria_live: "polite", class: "sr-only",
          data: { command_announcer_target: "region" }
        )
        render_command_table_inner
      end
    end

    # Слово статусу — з ГОТОВОГО дому міток бейджа (нового авторингу нуль);
    # `id: "%{id}"` повертає плейсхолдер у рядок — його підставляє JS у момент
    # анонсу, бо в мить рендера сторінки id команди ще невідомий.
    def announcer_messages
      ActuatorCommand::TERMINAL_STATUSES.index_with do |status|
        t(".announcer_template", id: "%{id}",
                                 status: t("actuators.command_status_badge.#{status}"))
      end
    end

    def render_command_table_inner
      div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
        table(class: "w-full text-left font-mono text-tiny min-w-[640px]", role: "table") do
          thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-micro tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".columns.id") }
              th(scope: "col", class: "p-4") { t(".columns.operator") }
              th(scope: "col", class: "p-4") { t(".columns.payload") }
              th(scope: "col", class: "p-4") { t(".columns.status") }
              th(scope: "col", class: "p-4 text-right") { t(".columns.executed_at") }
              # [I18N.1] Кінець дії — окрема колонка: `executed_at` ставиться в
              # `acknowledge` (мітка «Початок» — виправлено 2026-07-27), а без
              # `completed_at` оператор бачив СТАРТ і не мав де побачити кінець —
              # «триває» і «завершилось» зливались, як `acknowledged`≡`confirmed`.
              th(scope: "col", class: "p-4 text-right") { t(".columns.completed_at") }
            end
          end
          tbody(class: "divide-y divide-gaia-border") do
            @commands.each do |cmd|
              tr(class: "hover:bg-gaia-surface-sunken") do
                td(class: "p-4 text-gaia-text-subtle") { "##{cmd.id}" }
                td(class: "p-4 text-gaia-text") { cmd.user&.first_name || t(".system_operator") }
                td(class: "p-4 font-bold text-gaia-text-strong") { cmd.command_payload }
                td(class: "p-4") do
                  render Actuators::CommandStatusFrame.new(command: cmd)
                end
                td(class: "p-4 text-right text-gaia-text-muted") { cmd.executed_at&.strftime("%d.%m.%y // %H:%M:%S") || t(".not_executed") }
                td(class: "p-4 text-right text-gaia-text-muted") { cmd.completed_at&.strftime("%d.%m.%y // %H:%M:%S") || t(".not_executed") }
              end
            end
          end
        end
      end
    end
  end
end
