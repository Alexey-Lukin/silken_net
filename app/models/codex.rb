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
  # ARCHETYPES — canonical registry of `archetype_key` values used by
  # Codex::Node.
  #
  # The Phase-1 corpus (79 records: 32 ecosystems + 29 unique trees +
  # 8 protocols + 10 mythos) treats every archetype as the cybernetic
  # tagline of one specific lore card — so the registry IS the canon.
  # Subsequent DAO submissions may either reuse an existing key or, by
  # governance vote, append a new one here.
  #
  # Adding a new archetype:
  #   1. Append a slug at the bottom of the appropriate group below.
  #   2. Reference it from the seed YAML (or the DAO proposal payload).
  #   3. The list is intentionally curated — DAO governance, not a
  #      free-form taxonomy.
  # ---------------------------------------------------------------------
  ARCHETYPES = %w[
    ecosystem_genesis_cluster
    nlos_routing
    air_gapped_sandbox
    system_overwrite
    ip68_stress_test
    erosion_alert
    acoustic_multipath
    managed_smart_grid
    biological_fork
    delay_tolerant_network
    mesh_sharding
    relict_oracle
    climate_stress_lab
    esg_macro_scale
    planetary_regulator
    extreme_survival
    resilient_architecture
    rf_anomaly_zone
    dynamic_boundary
    mesh_logic_anomaly
    biomimetic_passive_harvest
    self_learning_edge
    acoustic_reference
    antifragile_infrastructure
    append_only_log
    carbon_to_silicon
    chaos_engineering
    fluid_topology
    ambient_energy_harvest
    extreme_geometry
    immutable_cold_storage
    layer_zero_blockchain
    legacy_master_node
    distributed_immortality
    ultra_low_power_mode
    honeypot_node
    magnetic_rom
    single_point_of_failure
    air_gap_backup
    radiation_hardened
    p2p_resilience
    active_firewall
    zero_knowledge_survival
    infinite_loop_optimised
    hardware_limit
    mega_bandwidth
    rolling_update
    monolithic_data_center
    legacy_with_exoskeleton
    local_vcap_storage
    hardware_merge
    overlay_network
    passive_mechatronic_sensor
    immutable_kernel
    hardware_vault
    anti_erosion_anchor
    backward_compatibility_node
    granite_island_router
    successful_code_porting
    encrypted_relay_node
    hardware_forking
    containerization
    udp_broadcast
    distributed_edge_computing
    channel_noise
    quantum_routing
    collision_avoidance
    trigger_function
    acoustic_panic_state
    cyber_physical_bridge
    load_balancing
    universe_topology
    sacred_hardware
    dag_architecture
    binary_clock
    timeless_artisan
    passive_monitoring
    planetary_supercomputer
    first_cyborg
  ].freeze

  def self.archetype_keys
    ARCHETYPES
  end
end
