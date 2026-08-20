# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Firmwares
  class New < ApplicationComponent
    def initialize(firmware:)
      @firmware = firmware
    end

    def view_template
      div(class: "max-w-2xl mx-auto") do
        # Заголовок сторінки (Презентаційний шар)
        header_section

        # Виклик атомарного компонента форми
        render Firmwares::Form.new(firmware: @firmware)
      end
    end

    private

    def header_section
      div(class: "text-center mb-10") do
        h2(class: "text-2xl font-extralight text-gaia-text-strong tracking-widest uppercase") { t(".title") }
        p(class: "text-tiny text-gaia-text-muted uppercase mt-2 tracking-[0.5em]") { t(".subtitle") }
      end
    end
  end
end
