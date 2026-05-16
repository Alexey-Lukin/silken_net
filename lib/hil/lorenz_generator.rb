# frozen_string_literal: true

require "securerandom"

module Hil
  # = ===================================================================
  # 🌀 HilLorenzGenerator — deterministic Lorenz fixture/training source
  # = ===================================================================
  #
  # Source: docs/00_06_Strategic_Roadmap_and_HIL_Simulators §4.2.
  #
  # Generates Lorenz attractor samples (inputs + Z + trajectory tails)
  # for two consumers:
  #
  #   1. TinyML training pipeline — labelled acoustic / temp / metabolism
  #      tuples with the resulting bio_status (homeostasis / stress /
  #      anomaly). Exposed as `to_csv` for OTA model retraining.
  #
  #   2. Rails Attractor validation — deterministic K_seed-derived
  #      (x₀, y₀, z₀) + sensor inputs → Z values for spec fixtures, so
  #      tests do not have to hand-craft realistic Lorenz states.
  #
  # Wraps SilkenNet::Attractor + SilkenNet::SeedDerivation so the output
  # is byte-identical to the server-side Lorenz mirror that backs Dual
  # Computation Integrity (SEC.11).
  #
  # Targeted Z bands (rejection sampling):
  #
  #   :homeostasis — z ∈ (critical_z_min .. critical_z_max)
  #   :stress      — z <  critical_z_min
  #   :anomaly     — z >  critical_z_max
  #
  # Acoustic presets reflect the four-class TinyML taxonomy
  # (silence / wind / cavitation / chainsaw) from docs/03_03 §1.
  # = ===================================================================
  class LorenzGenerator
    # Default Z-band thresholds when no TreeFamily is supplied. Match
    # SilkenNet::Attractor's homeostasis envelope (Pinus sylvestris).
    DEFAULT_Z_MIN = 5.0
    DEFAULT_Z_MAX = 45.0

    # Acoustic class presets — values fed into σ_eff perturbation.
    ACOUSTIC_PROFILES = {
      silence:    (0..15),
      wind:       (15..60),
      cavitation: (60..150),
      chainsaw:   (200..255)
    }.freeze

    # Per-state default knobs (chosen so rejection sampling converges in
    # < 10 iterations on the global default Z band).
    STATE_PROFILES = {
      homeostasis: {
        temp_range:     (15..30),
        acoustic_class: :wind,
        delta_t_range:  (30..60),
        vcap_range:     (3500..4400)
      },
      stress: {
        # Slow EBFC charging + low vcap → β collapses, Z dips below z_min.
        temp_range:     (-10..5),
        acoustic_class: :silence,
        delta_t_range:  (110..180),
        vcap_range:     (2800..3200)
      },
      anomaly: {
        # Hot crown + chainsaw burst → σ/ρ spike, Z punches through z_max.
        temp_range:     (55..80),
        acoustic_class: :chainsaw,
        delta_t_range:  (10..40),
        vcap_range:     (4400..4800)
      }
    }.freeze

    DEFAULT_MAX_ATTEMPTS = 50

    attr_reader :tree_family, :seed_bytes

    def initialize(tree_family: nil, seed_hex: nil, rng: Random.new)
      @tree_family = tree_family
      @rng = rng
      @seed_bytes = resolve_seed_bytes(seed_hex)
    end

    # One unlabelled sample with whatever Z naturally falls out of the
    # supplied (or randomised) inputs. Caller-provided overrides win over
    # the random pick — useful for sanity checks.
    #
    # Returns a Hash matching the columns TelemetryLog needs for a server
    # Z computation, plus the K_seed-derived (x₀, y₀, z₀) and the final
    # (x, y, z) trajectory tail for chain continuation.
    def sample(state: :homeostasis, **overrides)
      profile = STATE_PROFILES.fetch(state) do
        raise ArgumentError, "unknown state #{state.inspect}; one of #{STATE_PROFILES.keys.inspect}"
      end
      build_sample(profile, state: state, overrides: overrides)
    end

    # Rejection-sampled fixture guaranteed to land in the homeostasis Z
    # band. Stress / anomaly bands are mathematically unreachable from
    # physically realistic inputs (see `synthesize` for hand-tuned
    # fixtures of those rarer states).
    def sample_in_state(state:, max_attempts: DEFAULT_MAX_ATTEMPTS, **overrides)
      unless state == :homeostasis
        raise ArgumentError,
              "sample_in_state only supports :homeostasis. Lorenz dynamics with " \
              "ρ ∈ [10..50] and β ∈ [2..4] cannot reach Z < critical_z_min or " \
              "Z > critical_z_max from physical input perturbation alone — use " \
              "`synthesize(state: #{state.inspect})` for hand-tuned stress / " \
              "anomaly fixtures."
      end

      max_attempts.times do
        result = sample(state: state, **overrides)
        return result if in_band?(result[:z_value], state)
      end
      raise RuntimeError,
            "could not land in homeostasis band (z_thresholds=#{z_thresholds.inspect}) " \
            "after #{max_attempts} attempts — overrides may be over-clamped"
    end

    # Synthesise a sample for a rare band (`:stress` / `:anomaly`) by
    # picking inputs from the state profile but **overriding** the final
    # Z value to fall inside the target band. The Lorenz trajectory tail
    # is recomputed but z_value is forced — caller must treat this as a
    # fixture, not as DCI-comparable Lorenz output. Marked with
    # `synthetic: true` so consumers (TinyML training pipeline) can
    # distinguish from naturally-occurring samples.
    def synthesize(state:, **overrides)
      profile = STATE_PROFILES.fetch(state) do
        raise ArgumentError, "unknown state #{state.inspect}; one of #{STATE_PROFILES.keys.inspect}"
      end
      result = build_sample(profile, state: state, overrides: overrides)
      result[:z_value] = forced_z_for(state)
      result[:z_final] = result[:z_value]
      result[:synthetic] = true
      result
    end

    # Returns `count` samples in the requested state.
    #
    # @param in_band [Boolean] only meaningful for :homeostasis; ignored
    #   for :stress / :anomaly (which always go through synthesise).
    def batch(state:, count:, in_band: false, **overrides)
      Array.new(count) do
        case state
        when :homeostasis
          in_band ? sample_in_state(state: state, **overrides) : sample(state: state, **overrides)
        when :stress, :anomaly
          synthesize(state: state, **overrides)
        else
          raise ArgumentError, "unknown state #{state.inspect}"
        end
      end
    end

    # Full Lorenz trajectory (Array<Float> flat layout [x,y,z,x,y,z,...]
    # of length ITERATIONS*3 = 750) using K_seed-derived initial state.
    # Suitable for Three.js / Deck.gl visualisations and golden-vector
    # spec fixtures.
    def trajectory(state: :homeostasis, **overrides)
      profile = STATE_PROFILES.fetch(state)
      inputs = pick_inputs(profile, overrides)
      x0, y0, z0 = SilkenNet::SeedDerivation.initial_state(@seed_bytes)

      SilkenNet::Attractor.generate_trajectory(
        x0, y0, z0,
        inputs[:temperature_c],
        inputs[:acoustic_events],
        inputs[:metabolism_s],
        inputs[:voltage_mv]
      )
    end

    # Render an array of samples as CSV (TinyML training pipeline expects
    # this flat tabular shape — one row per sample, header row first).
    def self.to_csv(samples)
      return "" if samples.empty?

      header = %w[state temperature_c acoustic_events metabolism_s voltage_mv
                  x0 y0 z0 x_final y_final z_final z_value]
      rows = samples.map do |s|
        header.map { |k| s.fetch(k.to_sym) }.join(",")
      end
      ([ header.join(",") ] + rows).join("\n") + "\n"
    end

    private

    def build_sample(profile, state:, overrides:)
      inputs = pick_inputs(profile, overrides)
      x0, y0, z0 = SilkenNet::SeedDerivation.initial_state(@seed_bytes)

      z_value, x_final, y_final, z_final =
        SilkenNet::Attractor.calculate_z_from_state(
          x0, y0, z0,
          inputs[:temperature_c],
          inputs[:acoustic_events],
          inputs[:metabolism_s],
          inputs[:voltage_mv]
        )

      {
        state: state,
        temperature_c: inputs[:temperature_c],
        acoustic_events: inputs[:acoustic_events],
        metabolism_s: inputs[:metabolism_s],
        voltage_mv: inputs[:voltage_mv],
        x0: x0, y0: y0, z0: z0,
        x_final: x_final, y_final: y_final, z_final: z_final,
        z_value: z_value
      }
    end

    def pick_inputs(profile, overrides)
      acoustic_range = ACOUSTIC_PROFILES.fetch(profile[:acoustic_class])
      {
        temperature_c:   overrides.fetch(:temperature_c)   { @rng.rand(profile[:temp_range]) },
        acoustic_events: overrides.fetch(:acoustic_events) { @rng.rand(acoustic_range) },
        metabolism_s:    overrides.fetch(:metabolism_s)    { @rng.rand(profile[:delta_t_range]) },
        voltage_mv:      overrides.fetch(:voltage_mv)      { @rng.rand(profile[:vcap_range]) }
      }
    end

    def in_band?(z, state)
      min, max = z_thresholds
      case state
      when :homeostasis then z >= min && z <= max
      when :stress      then z < min
      when :anomaly     then z > max
      else raise ArgumentError, "no Z band defined for state #{state.inspect}"
      end
    end

    # Pick a forced Z value just inside the target band so synthesised
    # samples are unambiguously classified by downstream consumers.
    def forced_z_for(state)
      min, max = z_thresholds
      case state
      when :stress  then [ min - 1.5, 1.0 ].max
      when :anomaly then max + 1.5
      else
        raise ArgumentError, "synthesize() only supports :stress or :anomaly, got #{state.inspect}"
      end
    end

    def z_thresholds
      return [ DEFAULT_Z_MIN, DEFAULT_Z_MAX ] if @tree_family.nil?
      [ @tree_family.critical_z_min.to_f, @tree_family.critical_z_max.to_f ]
    end

    # Resolve a 32-byte K_seed for SilkenNet::SeedDerivation. If the
    # caller passes a hex string we use it verbatim (deterministic across
    # specs); otherwise we synthesise a random 32-byte value — Lorenz
    # rejection sampling re-derives the same initial state every call
    # within a single generator instance, which is what tests need.
    def resolve_seed_bytes(seed_hex)
      hex = seed_hex || SecureRandom.hex(32)
      raise ArgumentError, "seed_hex must be 64 hex characters" unless hex.length == 64
      [ hex ].pack("H*")
    end
  end
end
