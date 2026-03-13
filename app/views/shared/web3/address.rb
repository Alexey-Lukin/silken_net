# frozen_string_literal: true

module Views
  module Shared
    module Web3
      class Address < ApplicationComponent
        DEFAULT_TRUNCATE_LENGTH = 12

        def initialize(address:, truncate: DEFAULT_TRUNCATE_LENGTH, fallback: "NOT_PROVISIONED")
          @address  = address
          @truncate = truncate
          @fallback = fallback
        end

        def view_template
          if @address.present?
            display_text = @address.length > @truncate ? "#{@address.first(@truncate)}…" : @address
            span(
              class: "text-[11px] font-mono text-emerald-500 break-all leading-relaxed",
              title: @address
            ) { display_text }
          else
            span(class: "text-[11px] font-mono text-gray-700 italic") { @fallback }
          end
        end
      end
    end
  end
end
