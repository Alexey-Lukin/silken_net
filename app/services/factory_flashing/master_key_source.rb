# frozen_string_literal: true

# [SEC.3] Factory Flashing — pluggable PROVISIONING_MASTER_KEY source.
#
# The Factory Flashing tool must obtain the master key to derive per-device
# keys, but it should never assume *how* the operator surfaces it. The two
# documented options in docs/03_06 §5 A are:
#
#   1. EnvAdapter        — read PROVISIONING_MASTER_KEY directly from ENV.
#                          Acceptable for dev / lab; production use requires
#                          the WeakKeyDetector gate (SEC.9) to refuse known
#                          test vectors.
#   2. BitwardenAdapter  — short-lived token (TTL 15 min) issued by
#                          Bitwarden Secrets Manager. Live integration is
#                          out of scope for this iteration; the adapter
#                          raises NotImplementedError so callers can wire it
#                          without committing the implementation.
#
# Adding a third adapter (HSM injection — 03_06 §5 A.1) is a matter of
# implementing #fetch_master_key with the same nil-safe contract.
module FactoryFlashing
  module MasterKeySource
    # Raised when the configured adapter cannot surface a usable master key.
    class UnavailableError < StandardError; end

    class Base
      # Returns the raw master-key bytes (ASCII-8BIT) or raises UnavailableError.
      # Adapters MUST validate against Security::WeakKeyDetector before returning.
      def fetch_master_key
        raise NotImplementedError, "#{self.class.name} must implement #fetch_master_key"
      end
    end

    class EnvAdapter < Base
      ENV_NAME = "PROVISIONING_MASTER_KEY"

      def fetch_master_key
        value = ENV[ENV_NAME]
        raise UnavailableError, "#{ENV_NAME} ENV is blank" if value.blank?

        weakness = Security::WeakKeyDetector.detect(value, hint: ENV_NAME)
        raise UnavailableError, "#{ENV_NAME} rejected: #{weakness}" if weakness

        value
      end
    end

    class BitwardenAdapter < Base
      # TODO(SEC.3): Implement Bitwarden Secrets Manager integration.
      #   - exchange short-lived PROVISIONING_SESSION_TOKEN (TTL 15 min) for
      #     PROVISIONING_MASTER_KEY via `bw` CLI or Bitwarden REST API,
      #   - cache result only in memory for the duration of one session,
      #   - call Security::WeakKeyDetector before returning,
      #   - on failure raise UnavailableError with the upstream reason.
      def fetch_master_key
        raise NotImplementedError, "BitwardenAdapter is a planned source — see SEC.3 design doc 03_06 §5 A.2"
      end
    end

    # Default factory used when callers do not pass an explicit adapter.
    def self.default
      EnvAdapter.new
    end
  end
end
