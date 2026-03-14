# frozen_string_literal: true

# @label Cluster Item Card
# @display bg_color "#000"
class ClusterItemPreview < Lookbook::Preview
  # @label Healthy Cluster
  # @notes A nominal cluster with no active threats.
  def healthy
    cluster = mock_cluster(name: "Черкаський бір", trees: 120, health: 0.94, threats: false)
    render Clusters::Item.new(cluster: cluster)
  end

  # @label Under Threat
  # @notes A cluster with active EWS alerts (red pulsing LED).
  def under_threat
    cluster = mock_cluster(name: "Amazon Sector Alpha", trees: 20, health: 0.45, threats: true)
    render Clusters::Item.new(cluster: cluster)
  end

  # @label Low Health
  # @notes Cluster with degraded health index but no active threats.
  def low_health
    cluster = mock_cluster(name: "Carpathian Ridge", trees: 55, health: 0.32, threats: false)
    render Clusters::Item.new(cluster: cluster)
  end

  # @label Interactive
  # @param name text "Cluster name"
  # @param trees range { min: 0, max: 500, step: 10 }
  # @param health range { min: 0, max: 100, step: 5 }
  # @param threats toggle "Active threats?"
  def interactive(name: "Preview Cluster", trees: 100, health: 85, threats: false)
    cluster = mock_cluster(name: name, trees: trees.to_i, health: health.to_f / 100, threats: threats)
    render Clusters::Item.new(cluster: cluster)
  end

  private

  def mock_cluster(name:, trees:, health:, threats:)
    OpenStruct.new(
      id: 1,
      name: name,
      total_active_trees: trees,
      active_trees_count: trees,
      health_index: health,
      active_threats?: threats
    )
  end
end
