# frozen_string_literal: true

module Clusters
  class Grid < ApplicationComponent
    def initialize(clusters:, pagy:)
      @clusters = clusters
      @pagy = pagy
    end

    def view_template
      if @clusters.any?
        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
          @clusters.each do |cluster|
            render Clusters::Item.new(cluster: cluster)
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { api_v1_clusters_path(page: page) }
        )
      else
        render_empty_state
      end
    end

    private

    def render_empty_state
      render Views::Shared::UI::EmptyState.new(
        title: "Matrix is empty. No clusters detected.",
        icon: "◎",
        description: "Deploy sensors to initialize cluster grid."
      )
    end
  end
end
