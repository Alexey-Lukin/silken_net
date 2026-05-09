# frozen_string_literal: true

# Codex namespace — Lore Module / «Кодекс Архетипів».
#
# SSOT: docs/04_05_Codex_Lore_Module.md
#
# This module hosts the entire lore/gamification layer (Realms, Nodes,
# Citations, plus future Comment/Attunement/Fraction/Match/Discovery
# tables). Phase 1 ships only Realm/Node/Citation; subsequent phases add
# the social and battle features.
module Codex
  # ---------------------------------------------------------------------
  # ARCHETYPES — frozen registry of `archetype_key` values used across
  # Codex::Node and Codex::Fraction. The key is the machine slug bound
  # to a node; the human face is rendered through `subtitle_uk/_en`.
  #
  # Adding a new archetype:
  #   1. Append a slug here.
  #   2. Reference it from a seed YAML or DAO proposal.
  # The list is intentionally small and curated — DAO governance, not a
  # free-form taxonomy.
  # ---------------------------------------------------------------------
  ARCHETYPES = %w[
    chaos_engineering
    legacy_master_node
    cold_wallet
    network_architect
    deep_tech_survivor
    air_gap
    radiation_hardened
    quantum_routing
    hardware_vault
    distributed_resilience
    self_healing
    swarm_intelligence
    mesh_network
    ancient_protocol
    immutable_ledger
    bio_oracle
    forest_guardian
    seed_vault
    soil_sensor
    canopy_observer
    root_consensus
    mycorrhizal_p2p
    pheromone_broadcast
    ultrasonic_signal
    thermal_witness
    silent_archive
    keystone_species
    edge_node
    long_lived_relay
    last_witness
    extinct_protocol
    mythic_axis
    world_root
    cosmic_ladder
    eternal_flame
    burning_sentinel
    vapor_oracle
    stone_archive
    chimera_node
    primordial_seed
  ].freeze

  def self.archetype_keys
    ARCHETYPES
  end
end
