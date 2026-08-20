# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Actuators
  class CommandStatusBadge < ApplicationComponent
    # [UI.1] Бейдж-роль = пастельний фон + парний текст (`04_04 §3.2`); сирі
    # `yellow-900/blue-900/emerald-*` пішли з міграцією домену. Фолбек нижче
    # (`surface-elevated`) свідомо не збігається зі стилем ЖОДНОГО живого стану —
    # цю розрізнимість пінить власна спека.
    STATUS_STYLES = {
      "issued"       => "bg-status-warning text-status-warning-text",
      "sent"         => "bg-status-info text-status-info-text",
      "acknowledged" => "bg-status-active text-status-active-text",
      "failed"       => "bg-status-danger text-status-danger-text",
      "confirmed"    => "bg-status-success text-status-success-text"
    }.freeze

    # [I18N.1] Дім міток станів НАКАЗУ — окремий від спільного `ui.status`
    # свідомо: перетин 3/5 (`issued`/`acknowledged` там немає), а частковий
    # резолв через спільний bag виглядав би повним. Класовий label — щоб
    # `ActionBadge` резолвив стан transition-дії тим САМИМ домом, що й цей
    # бейдж (дзеркало `StatusBadge.label`).
    SCOPE = "actuators.command_status_badge"

    def self.label(status)
      value = status.to_s
      I18n.t("#{SCOPE}.#{value}", default: value)
    end

    def initialize(command:)
      @command = command
    end

    def view_template
      status = @command.status.to_s
      style  = STATUS_STYLES.fetch(status, "bg-gaia-surface-elevated text-gaia-text-subtle")
      label  = self.class.label(status)

      # [UI.3] `data-command-state` — сирий enum, locale-інваріантний: SR-анонс
      # на Show дискримінує термінальність машинно, не парсячи локалізований
      # текст. Їде з відповіді ендпоінта (class-2 pull), не з броадкасту.
      span(
        id: "command_status_#{@command.id}",
        class: tokens("px-2 py-0.5 rounded text-tiny font-bold uppercase", style),
        data: { command_state: status }
      ) { label }
    end
  end
end
