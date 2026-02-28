# frozen_string_literal: true

module Views
  module Components
    module Clusters
      class Grid < ApplicationComponent
        def initialize(clusters:)
          @clusters = clusters
        end

        def view_template
          if @clusters.any?
            div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
              @clusters.each do |cluster|
                render Views::Components::Clusters::Item.new(cluster: cluster)
              end
            end
          else
            render_empty_state
          end
        end

        private

        def render_empty_state
          div(class: "py-20 text-center border border-dashed border-emerald-900") do
            p(class: "text-sm text-emerald-800 uppercase tracking-widest") { "Matrix is empty. No clusters detected." }
          end
        end
      end
    end
  end
end
