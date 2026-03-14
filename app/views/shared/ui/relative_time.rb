# frozen_string_literal: true

module Views
  module Shared
    module UI
      class RelativeTime < ApplicationComponent
        def initialize(datetime:, css_class: "text-emerald-900 text-[10px] font-mono")
          @datetime  = datetime
          @css_class = css_class
        end

        def view_template
          return plain("—") if @datetime.nil?

          time(
            datetime: @datetime.iso8601,
            title: @datetime.strftime("%d.%m.%Y %H:%M:%S UTC"),
            class: @css_class
          ) do
            plain "#{ActionController::Base.helpers.time_ago_in_words(@datetime)} ago"
          end
        end
      end
    end
  end
end
