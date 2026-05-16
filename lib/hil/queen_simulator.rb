# frozen_string_literal: true

require "openssl"
require "securerandom"

module Hil
  # = ===================================================================
  # 🏰 HilQueenSimulator — Queen Gateway HIL Digital Twin
  # = ===================================================================
  #
  # Source: docs/00_06_Strategic_Roadmap_and_HIL_Simulators §4.2 +
  # docs/00_03_Resilience_and_Failover_Policy §1.3.
  #
  # Generates Queen Sentinel telemetry (DID = 0x00000000) without a live
  # STM32WLE5JC, so Queen failover & resilience tests can run against the
  # full backend (TelemetryUnpackerService → GatewayTelemetryWorker →
  # Gateway.mark_seen! / EwsAlert) without firmware in the loop.
  #
  # Two output modes:
  #
  #   :direct — call `GatewayTelemetryWorker.perform_async` directly with
  #             the stats hash. Fastest path; bypasses the CoAP listener
  #             and the AES unpack. Use this in unit/integration specs.
  #
  #   :wire   — build a 21-byte LoRa packet (DID:4 + RSSI:1 + 16-byte
  #             AES-256-CBC encrypted inner payload) and POST it to the
  #             CoAP listener at /telemetry/batch/<queen_uid>. Mirrors the
  #             real Queen flush path through TelemetryUnpackerService.
  #
  # Scenarios (composable knobs):
  #
  #   :healthy        — nominal voltage / temp / CSQ
  #   :brownout       — voltage < LOW_BATTERY_THRESHOLD (3300 mV) → EwsAlert
  #   :overheat       — temperature > OVERHEAT_THRESHOLD (65 °C) → EwsAlert
  #   :weak_signal    — CSQ < LOW_SIGNAL_THRESHOLD (5) → EwsAlert
  #   :no_signal      — CSQ == 99 (unknown; no alert by spec)
  #   :cifo_filling   — increasing cache_count, otherwise healthy
  #
  # Cross-ref:
  #   - docs/03_02_Queen_Gateway_Firmware §4.4 (Queen Sentinel packet)
  #   - app/services/telemetry_unpacker_service.rb#route_queen_health
  #   - app/workers/gateway_telemetry_worker.rb (consumer)
  # = ===================================================================
  class QueenSimulator
    AES_BLOCK_SIZE = 16
    INNER_PAYLOAD_SIZE = 16   # 1 AES block — matches firmware queen_health[16]
    OUTER_PACKET_SIZE = 21    # DID:4 + RSSI:1 + inner:16
    DEFAULT_COAP_HOST = "coap://127.0.0.1:5683"
    DEFAULT_COAP_TIMEOUT = 2

    # Scenario presets — values picked to flip the corresponding
    # GatewayTelemetryLog#critical_fault? branch.
    SCENARIOS = {
      healthy:      { voltage_mv: 4100, temperature_c: 25, cellular_signal_csq: 22 },
      brownout:     { voltage_mv: 3100, temperature_c: 22, cellular_signal_csq: 18 },
      overheat:     { voltage_mv: 4000, temperature_c: 72, cellular_signal_csq: 19 },
      weak_signal:  { voltage_mv: 4000, temperature_c: 24, cellular_signal_csq: 3  },
      no_signal:    { voltage_mv: 4000, temperature_c: 24, cellular_signal_csq: 99 },
      cifo_filling: { voltage_mv: 4000, temperature_c: 24, cellular_signal_csq: 22 }
    }.freeze

    # CIFO cache cap on Queen (50 slots; flush trigger at ≥ 45).
    # Mirrors firmware/queen/main.c `CACHE_MAX_ENTRIES`.
    CIFO_CAPACITY = 50

    # 5-bit wire growth_points field (after FW.29-PACK); matches
    # firmware test `QUEEN_HEALTH_GP_MAX`.
    QUEEN_HEALTH_GP_MAX = 31

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
      @uptime_s = 0
      @cifo_fill = 0
    end

    # Emit a single Queen Sentinel beacon.
    #
    # Returns a Hash with the resolved stats (always, regardless of mode)
    # so callers can assert on what was sent without parsing wire bytes.
    def tick(scenario: :healthy, voltage_mv: nil, temperature_c: nil,
             cellular_signal_csq: nil, cifo_fill: nil, uptime_s: nil)
      preset = SCENARIOS.fetch(scenario) do
        raise ArgumentError, "unknown scenario #{scenario.inspect}; one of #{SCENARIOS.keys.inspect}"
      end

      stats = {
        voltage_mv: voltage_mv || preset[:voltage_mv],
        temperature_c: temperature_c || preset[:temperature_c],
        cellular_signal_csq: cellular_signal_csq || preset[:cellular_signal_csq],
        ip_address: @gateway.ip_address
      }

      @uptime_s = uptime_s || (@uptime_s + @rng.rand(60..120))
      @cifo_fill = cifo_fill || next_cifo_fill(scenario)

      case @mode
      when :direct then dispatch_direct(stats)
      when :wire   then dispatch_wire(stats)
      end

      stats.merge(scenario: scenario, uptime_s: @uptime_s, cifo_fill: @cifo_fill)
    end

    # Run a deterministic loop of `count` beacons. Sleeps `interval`
    # seconds between ticks (default 0 — for tests). Returns the array of
    # stats hashes that were emitted.
    def run!(scenario: :healthy, count: 5, interval: 0, **overrides)
      Array.new(count) do |i|
        sleep(interval) if interval.positive? && i.positive?
        tick(scenario: scenario, **overrides)
      end
    end

    private

    # In :direct mode we mirror what TelemetryUnpackerService#route_queen_health
    # does on receipt of a sentinel packet — enqueue GatewayTelemetryWorker
    # with the stats hash directly. No CoAP, no AES, no unpack.
    def dispatch_direct(stats)
      GatewayTelemetryWorker.perform_async(@gateway.uid, stats.stringify_keys)
    end

    # In :wire mode we build the same encrypted envelope a real Queen
    # would, and POST it through CoapClient — same code path as
    # bin/forest_simulator, but with DID == 0 sentinel chunks.
    def dispatch_wire(stats)
      payload = encrypted_sentinel_payload(stats)
      url = "#{@coap_host}/telemetry/batch/#{@gateway.uid}"
      require "coap_client" unless defined?(CoapClient)
      CoapClient.put(url, payload, timeout: @coap_timeout)
    end

    # Build the 21-byte LoRa-shaped sentinel chunk and AES-256-CBC encrypt
    # it with the gateway's per-device key. Format matches
    # bin/forest_simulator + app/workers/concerns/coap_encryption.rb.
    def encrypted_sentinel_payload(stats)
      chunk = build_sentinel_chunk(stats)
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = @gateway.hardware_key.binary_key
      cipher.padding = 0
      iv = cipher.random_iv

      pad_len = (AES_BLOCK_SIZE - (chunk.bytesize % AES_BLOCK_SIZE)) % AES_BLOCK_SIZE
      padded = chunk + ("\x00".b * pad_len)
      iv + cipher.update(padded) + cipher.final
    end

    # Outer LoRa frame for a Queen sentinel chunk:
    #   [DID:4 BE = 0][RSSI:1 = 0][inner:16]
    # Inner payload is laid out the way TelemetryUnpackerService expects
    # for `route_queen_health` — Vcap, Temp, CSQ all in the slots the
    # backend reuses for gateway diagnostics.
    def build_sentinel_chunk(stats)
      l2_header = [ 0, 0 ].pack("N C")          # DID = 0, RSSI = 0 (local)
      inner = build_sentinel_inner(stats)
      l2_header + inner
    end

    # Layout (16 bytes, matches PAYLOAD_FORMAT "N n c C n C C a4"):
    #   [0..3]   DID (uint32 BE, 0 for sentinel)
    #   [4..5]   Vcap (uint16 BE) → voltage_mv
    #   [6]      Temp (int8)      → temperature_c
    #   [7]      Acoustic (uint8) → cellular_signal_csq
    #   [8..9]   Metabolism (uint16 BE) → uptime proxy (low 16 bits)
    #   [10]     Status byte → growth_points clamped to QUEEN_HEALTH_GP_MAX
    #   [11]     TTL (uint8) = 0 (local)
    #   [12..15] Pad (4 bytes) = 0
    def build_sentinel_inner(stats)
      gp = [ @cifo_fill, QUEEN_HEALTH_GP_MAX ].min
      [
        0,                                    # DID
        clamp_uint16(stats[:voltage_mv]),     # Vcap → voltage_mv
        clamp_int8(stats[:temperature_c]),    # Temp → temperature_c
        clamp_uint8(stats[:cellular_signal_csq]), # CSQ via Acoustic byte
        @uptime_s & 0xFFFF,                   # Metabolism slot — uptime low 16
        gp,                                   # Status byte (growth_points 5-bit)
        0,                                    # TTL (local)
        "\x00\x00\x00\x00".b                  # 4-byte pad
      ].pack("N n c C n C C a4")
    end

    def next_cifo_fill(scenario)
      if scenario == :cifo_filling
        # Climb toward the 45-slot flush trigger then plateau at capacity.
        [ @cifo_fill + @rng.rand(1..3), CIFO_CAPACITY ].min
      else
        @rng.rand(0..10)
      end
    end

    def clamp_uint16(value)
      value.to_i.clamp(0, 0xFFFF)
    end

    def clamp_int8(value)
      value.to_i.clamp(-128, 127)
    end

    def clamp_uint8(value)
      value.to_i.clamp(0, 255)
    end
  end
end
