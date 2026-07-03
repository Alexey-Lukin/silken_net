# frozen_string_literal: true

require "openssl"
require "securerandom"

module Hil
  # = ===================================================================
  # 🏰 HilQueenSimulator — Queen Gateway HIL Digital Twin
  # = ===================================================================
  #
  # Source: docs/00_03_TRL_Matrix_HIL_and_Beyond §4.2 +
  # docs/06_08_Resilience_and_Failover_Policy §1.3.
  #
  # [ARCH.54] Емуляція ПУЛЬСУ Королеви — health-блоку у підписаному
  # QATT-v2 конверті (wire-дім: firmware/common/queen_attest.h). Стара
  # DID=0-псевдотелеметрія ВБИТА разом із route_queen_health: health
  # більше не маскується під дерево і не існує без Ed25519-підпису.
  #
  # Two output modes:
  #
  #   :direct — call `GatewayTelemetryWorker.perform_async` directly with
  #             the v2 stats hash. Fastest path; bypasses the CoAP listener
  #             and the envelope. Use this in unit/integration specs.
  #
  #   :wire   — build the exact empty-flush heartbeat a provisioned Queen
  #             emits (header v2 + IV + 0×ct + Ed25519 sig) and POST it to
  #             the CoAP listener at /telemetry/batch/<queen_uid>. Mirrors
  #             firmware Flush_Cache_To_Rails with an empty CIFO. `signed`
  #             is implied: an UNSIGNED wire heartbeat does not exist in
  #             the protocol (health is only ever attested).
  #
  # Scenarios (composable knobs):
  #
  #   :healthy         — nominal CSQ / clean counters
  #   :weak_signal     — CSQ < LOW_SIGNAL_THRESHOLD (5) → EwsAlert
  #   :no_signal       — CSQ not read (0xFF wire → nil; no alert by spec)
  #   :uplink_degraded — coap_fail_count ≥ COAP_FAIL_ALERT_THRESHOLD → EwsAlert
  #   :cifo_filling    — increasing cifo_fill, otherwise healthy
  #
  # Deliberately an INDEPENDENT (fourth) implementation of the envelope:
  # Monocypher (firmware) ↔ OpenSSL (C KAT) ↔ worker attest-spec ↔ this
  # simulator must agree byte-for-byte.
  #
  # Cross-ref:
  #   - docs/03_02_Queen_Gateway_Firmware §7 (Queen pulse, v2)
  #   - app/workers/unpack_telemetry_worker.rb#enqueue_envelope_health
  #   - app/workers/gateway_telemetry_worker.rb (consumer)
  # = ===================================================================
  class QueenSimulator
    AES_IV_SIZE = 16
    DEFAULT_COAP_HOST = "coap://127.0.0.1:5683"
    DEFAULT_COAP_TIMEOUT = 2

    # Scenario presets — values picked to flip the corresponding
    # GatewayTelemetryLog#critical_fault? branch (v2 pulse fields).
    SCENARIOS = {
      healthy:         { cellular_signal_csq: 22,  lora_rx_drops: 0,  coap_fail_count: 0 },
      weak_signal:     { cellular_signal_csq: 3,   lora_rx_drops: 0,  coap_fail_count: 0 },
      no_signal:       { cellular_signal_csq: nil, lora_rx_drops: 0,  coap_fail_count: 0 },
      uplink_degraded: { cellular_signal_csq: 18,  lora_rx_drops: 4,  coap_fail_count: 12 },
      cifo_filling:    { cellular_signal_csq: 22,  lora_rx_drops: 0,  coap_fail_count: 0 }
    }.freeze

    # CIFO cache cap on Queen (50 slots; flush trigger at ≥ 45).
    # Mirrors firmware/queen/main.c `CACHE_MAX_ENTRIES`.
    CIFO_CAPACITY = 50

    # [L1 QATT v2] Envelope constants — mirror of firmware/common/queen_attest.h
    # (wire home: docs/03_05 §2.2).
    QATT_VERSION_2  = 0x02
    QATT_DOMAIN_TAG = "SLKN-QATT2"
    QATT_CSQ_NOT_READ = 0xFF

    attr_reader :gateway, :mode

    def initialize(gateway, mode: :direct, coap_host: DEFAULT_COAP_HOST,
                   coap_timeout: DEFAULT_COAP_TIMEOUT, rng: Random.new)
      raise ArgumentError, "gateway is required" if gateway.nil?
      raise ArgumentError, "unsupported mode #{mode.inspect} (expected :direct or :wire)" \
        unless %i[direct wire].include?(mode)

      @gateway = gateway
      @mode = mode
      @coap_host = coap_host
      @coap_timeout = coap_timeout
      @rng = rng
      @uptime_min = 0
      @cifo_fill = 0
      @flush_seq = 0
      register_attestation_key! if mode == :wire
    end

    # Emit a single Queen pulse.
    #
    # Returns a Hash with the resolved stats (always, regardless of mode)
    # so callers can assert on what was sent without parsing wire bytes.
    def tick(scenario: :healthy, cellular_signal_csq: :preset, lora_rx_drops: nil,
             coap_fail_count: nil, cifo_fill: nil, uptime_min: nil, flags: 0)
      preset = SCENARIOS.fetch(scenario) do
        raise ArgumentError, "unknown scenario #{scenario.inspect}; one of #{SCENARIOS.keys.inspect}"
      end

      @uptime_min = uptime_min || (@uptime_min + @rng.rand(30..90))
      @cifo_fill = cifo_fill || next_cifo_fill(scenario)

      stats = {
        "uptime_min"      => @uptime_min,
        "cifo_fill"       => @cifo_fill,
        "lora_rx_drops"   => lora_rx_drops || preset[:lora_rx_drops],
        "coap_fail_count" => coap_fail_count || preset[:coap_fail_count],
        "cellular_signal_csq" =>
          (cellular_signal_csq == :preset ? preset[:cellular_signal_csq] : cellular_signal_csq),
        "flags"           => flags,
        "ip_address"      => @gateway.ip_address
      }

      case @mode
      when :direct then GatewayTelemetryWorker.perform_async(@gateway.uid, stats)
      when :wire   then dispatch_wire(stats)
      end

      stats.merge("scenario" => scenario)
    end

    # Run a deterministic loop of `count` pulses. Sleeps `interval`
    # seconds between ticks (default 0 — for tests). Returns the array of
    # stats hashes that were emitted.
    def run!(scenario: :healthy, count: 5, interval: 0, **overrides)
      Array.new(count) do |i|
        sleep(interval) if interval.positive? && i.positive?
        tick(scenario: scenario, **overrides)
      end
    end

    private

    # :wire — the exact empty-flush heartbeat of a provisioned Queen:
    # [header v2 (health inside)][IV][ct = 0 bytes][sig]. Same code path as
    # a full batch, the CIFO just happens to be empty (residue math counts
    # the IV always — bytesize ≡ 1 mod 16).
    def dispatch_wire(stats)
      payload = signed_heartbeat(stats)
      url = "#{@coap_host}/telemetry/batch/#{@gateway.uid}"
      require "coap_client" unless defined?(CoapClient)
      CoapClient.put(url, payload, timeout: @coap_timeout)
    end

    # Eagerly mint the simulator's Ed25519 identity and register its pubkey
    # on the gateway's HardwareKey — the same slot the factory pipeline
    # fills at provisioning (FactoryFlashing::Session). Eager so `run!`
    # never performs a DB write mid-loop.
    def register_attestation_key!
      @attest_seed_hex = @rng.bytes(32).unpack1("H*")
      pubkey_hex = Ed25519Crypto::SigningService.public_key_from_seed(@attest_seed_hex)
      @gateway.hardware_key.update!(ed25519_public_key_hex: pubkey_hex)
    end

    # QATT v2 envelope: [ver:1][unix_ts:4 BE][flush_seq:4 BE][health:8]
    # [IV:16][ct][sig:64], signed over "SLKN-QATT2" ‖ uid_len ‖ uid ‖ <body>.
    # The signature comes back as hex from SigningService — pack("H*") is
    # load-bearing: appending the hex string instead would still leave
    # bytesize ≡ 1 (mod 16), so the residue check alone would not catch it.
    def signed_heartbeat(stats)
      @flush_seq += 1
      csq = stats["cellular_signal_csq"] || QATT_CSQ_NOT_READ
      up  = [ stats["uptime_min"].to_i, 0xFFFFFF ].min
      health = [ (up >> 16) & 0xFF, (up >> 8) & 0xFF, up & 0xFF,
                 stats["cifo_fill"].to_i.clamp(0, 255),
                 stats["lora_rx_drops"].to_i.clamp(0, 255),
                 stats["coap_fail_count"].to_i.clamp(0, 255),
                 csq.to_i.clamp(0, 255),
                 stats["flags"].to_i.clamp(0, 255) ].pack("C8")
      body = [ QATT_VERSION_2, Time.current.to_i, @flush_seq ].pack("CNN") +
             health + @rng.bytes(AES_IV_SIZE)
      uid = @gateway.uid.to_s
      message = QATT_DOMAIN_TAG + [ uid.bytesize ].pack("C") + uid.b + body
      sig_hex = Ed25519Crypto::SigningService.sign(@attest_seed_hex, message)
      body + [ sig_hex ].pack("H*")
    end

    def next_cifo_fill(scenario)
      if scenario == :cifo_filling
        # Climb toward the 45-slot flush trigger then plateau at capacity.
        [ @cifo_fill + @rng.rand(1..3), CIFO_CAPACITY ].min
      else
        @rng.rand(0..10)
      end
    end
  end
end
