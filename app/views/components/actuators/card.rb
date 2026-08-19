# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Actuators
  class Card < ApplicationComponent
    # ⚠️ Дані приходять готовими — жодного запиту в конструкторі ([`04_04 §6.4`],
    # CLAUDE §6). Доти тут стояв фолбек `@actuator.commands.last`, і він давав
    # РІЗНУ «останню команду» на двох сторінках: на `index` асоціація приходить
    # преloaded, тож `.last` брав останній елемент у порядку, яким її повернула
    # БД, а на `show` преload'а немає, тож летів окремий SQL з `ORDER BY id DESC`.
    def initialize(actuator:, last_command: nil)
      @actuator = actuator
      @last_command = last_command
    end

    def view_template
      div(id: "actuator_#{@actuator.id}", class: card_container_classes) do
        # Фоновий індикатор типу (декоративний)
        # Декоративний, `aria_hidden` — але ВИДИМИЙ оком, тож три літери беруться з
        # локалізованої назви: англійське «WAT» на українському екрані було тим самим
        # дефектом, лише тихішим за бейдж під ним.
        div(class: "absolute -right-4 -top-4 text-[40px] font-bold text-gaia-text-muted/5 select-none", aria_hidden: "true") { @actuator.device_type_label[0..2].upcase }

        render_header
        render_status_matrix
        render_controls
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-start mb-6") do
        div do
          # [I18N.1] Рід пристрою — через дім міток (`Actuator::DEVICE_TYPE_LABEL_SCOPE`),
          # не сирий enum: доти тут стояв англійський технічний токен «water_valve»
          # у локалізованому інтерфейсі всіх чотирьох мов.
          span(class: "text-micro px-2 py-0.5 border border-gaia-border text-gaia-text-muted uppercase font-mono tracking-widest") { @actuator.device_type_label }
          h4(class: "text-lg font-light text-gaia-text mt-2 tracking-tighter") { @actuator.name }
          p(class: "text-micro text-gaia-text-muted font-mono mt-1") { t(".gateway", uid: @actuator.gateway&.uid) }
        end
        div(class: tokens("h-2 w-2 rounded-full", status_led_class))
      end
    end

    def render_status_matrix
      div(class: "space-y-2 mb-6 font-mono text-tiny uppercase tracking-tighter") do
        div(class: "flex justify-between border-b border-gaia-border pb-1") do
          span(class: "text-gaia-text-muted") { t(".physical_state") }
          span(class: "text-gaia-primary-strong") { Views::Shared::UI::StatusBadge.label(@actuator.state) }
        end
        div(class: "flex justify-between border-b border-gaia-border pb-1") do
          span(class: "text-gaia-text-muted") { t(".endpoint") }
          span(class: "text-gaia-primary-strong") { @actuator.endpoint }
        end
        if @actuator.max_active_duration_s
          div(class: "flex justify-between border-b border-gaia-border pb-1") do
            span(class: "text-gaia-text-muted") { t(".max_duration") }
            span(class: "text-gaia-primary-strong") { t(".max_duration_value", seconds: @actuator.max_active_duration_s) }
          end
        end
        if @actuator.estimated_mj_per_action
          div(class: "flex justify-between border-b border-gaia-border pb-1") do
            span(class: "text-gaia-text-muted") { t(".energy_budget") }
            span(class: "text-gaia-primary-strong") { t(".energy_budget_value", mj: @actuator.estimated_mj_per_action) }
          end
        end
        div(class: "flex justify-between border-b border-gaia-border pb-1") do
          span(class: "text-gaia-text-muted") { t(".last_activated") }
          span(class: "text-gaia-primary-strong") { @actuator.last_activated_at&.strftime("%d.%m.%y %H:%M") || t(".never") }
        end
        div(class: "flex justify-between items-center") do
          span(class: "text-gaia-text-muted") { t(".last_sync_status") }
          # Реюз бейджа замість власної мітки: він єдиний дім і перекладу
          # (`actuators.command_status_badge.*`), і кольорів усіх п'яти станів —
          # тут же жила друга, вужча копія, що знала лише `failed` і рендерила
          # решту сирим англійським enum'ом навіть українцю.
          if @last_command
            render Actuators::CommandStatusBadge.new(command: @last_command)
          else
            span(class: "text-gaia-text-muted") { t(".idle") }
          end
        end
      end
    end

    def render_controls
      # Route helpers потребують request context (url_options).
      # При Turbo broadcast з воркера — request context відсутній.
      return unless respond_to?(:view_context) && view_context&.respond_to?(:url_options)

      # [UI.14, присуд founder 2026-08-13] Ручна дія тут рівно ОДНА — аварійна
      # зупинка, і вона єдина, що має спостережуваний ефект сьогодні: `STOP` є
      # override-вантажем (`ActuatorCommand::OVERRIDE_COMMANDS`), тож
      # `cancel_pending_for_actuator!` гасить чергу актуатора й пише audit-trail
      # ЧИСТО на бекенді — Королеви для цього не треба.
      #
      # Кнопок «відкрити/закрити» більше немає, і знято їх не за косметику: вони
      # слали `open`/`close`, тоді як модель приймає лише `[A-Z_]+` → кожен клік
      # по пожежному клапану давав 500. 🔴 «Полагодити регістр» зробило б ГІРШЕ:
      # Королева ACTION не інтерпретує взагалі (`queen/main.c` — на місці
      # виконання коментар, не код), а Rails просуває стан при ПОБУДОВІ відповіді,
      # тож команда пройшла б `dispatch!`→`acknowledge!`→`confirmed` і лягла б у
      # ланцюг `Auditable` як виконана. Гучна відмова стала б підробленим доказом
      # на physical-safety поверхні — клас FW.63 «слід бреше».
      div do
        # 🔴 `duration_seconds` тут НЕСУЧИЙ, і це ДРУГА нога того самого дефекту,
        # якої пункт не називав: модель має `validates :duration_seconds,
        # presence: true`, а стара кнопка не слала його зовсім — тобто навіть із
        # правильним регістром клік однаково давав би 500 (`create!` →
        # `RecordInvalid` → `rescue_from StandardError`). Знайдено піном на живий
        # вхід, не читанням. Значення `1` — конвенція STOP'а, що вже жила в
        # request-спеці: зупинка миттєва, тривалості не має, але поле обовʼязкове.
        button_to(
          execute_actuator_path(@actuator, action_payload: "STOP", duration_seconds: 1),
          method: :post,
          aria: { label: t(".emergency_stop_aria", device_type: @actuator.device_type_label) },
          class: emergency_stop_classes
        ) { t(".emergency_stop") }
      end
    end

    def status_led_class
      case @actuator.state
      when "active" then "bg-emerald-500 shadow-[0_0_10px_#10b981]"
      when "maintenance_needed" then "bg-red-600 animate-pulse shadow-[0_0_10px_red]"
      when "offline" then "bg-red-900"
      else "bg-gray-800"
      end
    end

    def card_container_classes
      "group p-6 border border-gaia-border bg-gaia-surface " \
        "shadow-sm dark:shadow-none " \
        "hover:border-gaia-primary transition-all duration-500 " \
        "relative overflow-hidden"
    end

    def emergency_stop_classes
      "w-full py-2 border border-status-danger-accent text-mini uppercase " \
        "text-status-danger-accent " \
        "hover:bg-status-danger-accent hover:text-black " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-status-danger-accent " \
        "transition-all font-bold tracking-widest"
    end
  end
end
