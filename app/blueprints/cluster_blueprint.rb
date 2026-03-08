# frozen_string_literal: true

class ClusterBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :region
  field(:health_index) { |cluster| cluster.health_index }
  field(:total_active_trees) { |cluster| cluster.total_active_trees }
  field(:geo_center) { |cluster| cluster.geo_center }
  field(:active_threats) { |cluster| cluster.active_threats? }
end
