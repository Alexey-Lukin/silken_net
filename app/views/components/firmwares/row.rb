# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Firmwares
  class Row < ApplicationComponent
    def initialize(firmware:)
      @firmware = firmware
    end

    def view_template
      tr(class: "hover:bg-emerald-950/10 transition-colors group") do
        td(class: "p-4 text-emerald-100 font-bold font-mono") { t(".version", version: @firmware.version) }
        td(class: "p-4 text-emerald-600 uppercase font-mono text-tiny") { @firmware.target_hardware_type }
        td(class: "p-4 text-gray-600 font-mono text-tiny") { @firmware.binary_sha256&.first(16) || t(".not_available") }
        td(class: "p-4 text-gray-500 font-mono text-tiny") { @firmware.created_at.strftime("%d.%m.%y // %H:%M") }

        td(class: "p-4 text-right") do
          # [UI.7] `button_to`, не рукописна `<form>`: токен, коректний `_method`
          # і кодування приходять самі. Дія без вводу — тож форма тут була ЛИШЕ
          # обгорткою над однією кнопкою (дзеркало `Alerts::Row#acknowledge`).
          button_to(
            t(".order_evolution"),
            deploy_firmware_path(@firmware),
            method: :post,
            class: "text-emerald-500 hover:text-white border border-emerald-900 hover:border-emerald-500 px-4 py-1 uppercase text-mini tracking-widest transition-all group-hover:shadow-[0_0_10px_rgba(16,185,129,0.2)]",
            data: { turbo_confirm: t(".confirm", version: @firmware.version) }
          )
        end
      end
    end
  end
end
