# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Actuators
  class CommandStatusBadge < ApplicationComponent
    STATUS_STYLES = {
      "issued"       => "bg-yellow-900 text-yellow-200",
      "sent"         => "bg-blue-900 text-blue-200",
      "acknowledged" => "bg-emerald-900 text-emerald-200",
      "failed"       => "bg-red-900 text-red-200",
      "confirmed"    => "bg-emerald-800 text-emerald-100"
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
      style  = STATUS_STYLES.fetch(status, "bg-zinc-800 text-zinc-300")
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
