# SPDX-License-Identifier: AGPL-3.0-or-later
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
            # Шаблон, а не суфікс: «ago»/«тому» стоять ПІСЛЯ проміжку, а латиське
            # «pirms»/литовське «prieš» — ПЕРЕД ним, тож конкатенацією це не
            # виражається. Сам проміжок локалізує `time_ago_in_words`
            # (`datetime.distance_in_words` з `rails-i18n`, `04_04 §12.2`).
            plain "#{@prefix}#{t('ui.relative_time.ago', time: time_ago_in_words(@datetime))}"
          end
        end
      end
    end
  end
end
