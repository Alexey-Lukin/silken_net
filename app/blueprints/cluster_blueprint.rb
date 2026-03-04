# frozen_string_literal: true

class ClusterBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :region
  field(:health_index) { |cluster| cluster.health_index }
end
