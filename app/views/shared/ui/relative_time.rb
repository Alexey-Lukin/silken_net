# frozen_string_literal: true

module Views
  module Shared
    module UI
      class RelativeTime < ApplicationComponent
        DEFAULT_CLASS = "text-gaia-text-muted text-tiny font-mono"

        def initialize(datetime:, css_class: DEFAULT_CLASS, prefix: nil)
          @datetime  = datetime
          @css_class = css_class
          @prefix    = prefix
        end

        def view_template
          return plain("—") if @datetime.nil?

          time(
            datetime: @datetime.iso8601,
            title: @datetime.strftime("%d.%m.%Y %H:%M:%S UTC"),
            class: @css_class
          ) do
            plain "#{@prefix}#{time_ago_in_words(@datetime)} ago"
          end
        end
      end
    end
  end
end
