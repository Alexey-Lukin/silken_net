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
  # Phase-8b added 19 new Cherkasy-cluster records (10 ecosystems + 9
  # unique trees), expanding the total to 98 records.
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
    # ── Phase-8b: Cherkasy cluster — ecosystem archetypes ─────────────────
    thermal_throttling_testbed
    graceful_degradation_recovery
    dynamic_floating_topology
    load_balanced_high_availability
    emf_interference_zone
    central_timing_hub
    hardware_software_codesign
    lora_attenuation_testbed
    network_partitioning
    edge_computing_frontier
    # ── Phase-8b: Cherkasy cluster — unique tree archetypes ───────────────
    load_bearing_critical_qos
    hardware_mutex_ipc
    dao_genesis_block
    peripheral_edge_interrupt_sensor
    kinetic_torsion_tolerance
    genesis_data_vault
    biological_raid_redundancy
    border_gateway_protocol
    proof_of_authority_node
    # ── Phase-8c: Cherkasy L4+L5 — ecosystem archetypes ──────────────────
    linear_topology_backbone
    secure_enclave_vpn
    thermal_runaway_hidden_state
    immutable_anchor_zone
    cross_chain_bridge
    high_risk_network_bridge
    layer1_archaeology
    periodic_interference_overload
    sinkhole_computing
    bare_metal_recovery
    # ── Phase-8c: Cherkasy L4+L5 — unique tree archetypes ────────────────
    timestamp_oracle
    solo_verifier_node
    legacy_api_endpoints
    deep_sleep_adapter
    dark_fiber
    zero_day_exploit
    orphaned_smart_contract
    edge_router_frontier
    vendor_lock_in
    baseline_idle_state
  ].freeze

  def self.archetype_keys
    ARCHETYPES
  end
end
