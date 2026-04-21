# frozen_string_literal: true

# SystemParameter — Governance-aware protocol constants registry.
#
# Stores protocol parameters that can be updated via DAO governance
# (on-chain via ProtocolParameters.sol + Governance::ParameterSyncWorker)
# or admin panel. Provides cached lookups with fallback to default values.
#
# Usage:
#   SystemParameter.current(:lorenz_sigma, default: 10.0)
#   SystemParameter.current(:emission_threshold, default: 10_000)
#   SystemParameter.current(:dynamic_tax_rate, default: 0.02)
#
# See: docs/05_03_Tokenomics_SCC_and_SFC.md § Governance-Aware Backend
class SystemParameter < ApplicationRecord
  CACHE_TTL = 24.hours
  CACHE_KEY_PREFIX = "system_parameter"

  VALUE_TYPES = %w[integer float decimal string boolean json].freeze
  CATEGORIES = %w[
    lorenz tokenomics minting alerts hardware insurance general
  ].freeze
  SOURCES = %w[default admin governance].freeze

  belongs_to :updated_by, class_name: "User", optional: true

  validates :key, presence: true, uniqueness: true,
                  format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must be snake_case" }
  validates :value, presence: true
  validates :value_type, presence: true, inclusion: { in: VALUE_TYPES }
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :source, presence: true, inclusion: { in: SOURCES }

  validate :value_within_bounds, if: -> { min_value.present? || max_value.present? }

  after_commit :invalidate_cache

  scope :by_category, ->(cat) { where(category: cat) }

  # Primary API: fetch a parameter with cached lookup and default fallback.
  #
  #   SystemParameter.current(:lorenz_sigma, default: 10.0)
  #
  # Returns the typed value or the default if the key is not found.
  # Cache TTL: 24 hours (invalidated on update via after_commit).
  def self.current(key, default: nil)
    key = key.to_s

    cached = Rails.cache.read(cache_key_for(key))
    return cached unless cached.nil?

    record = find_by(key: key)

    if record
      typed = record.typed_value
      Rails.cache.write(cache_key_for(key), typed, expires_in: CACHE_TTL)
      typed
    else
      default
    end
  end

  # Bulk fetch multiple parameters at once. Returns a Hash.
  #
  #   SystemParameter.current_values(lorenz_sigma: 10.0, lorenz_rho: 28.0)
  #   # => { lorenz_sigma: 10.0, lorenz_rho: 28.0 }
  def self.current_values(**defaults)
    defaults.each_with_object({}) do |(key, default_val), result|
      result[key] = current(key, default: default_val)
    end
  end

  # Update or create a parameter with audit trail.
  def self.set(key, value, updated_by: nil, **attrs)
    record = find_or_initialize_by(key: key.to_s)
    record.assign_attributes(
      value: value.to_s,
      updated_by: updated_by,
      **attrs
    )
    record.save!
    record
  end

  # Returns the value coerced to the declared value_type.
  def typed_value
    case value_type
    when "integer" then value.to_i
    when "float" then value.to_f
    when "decimal" then BigDecimal(value)
    when "boolean" then ActiveModel::Type::Boolean.new.cast(value)
    when "json" then JSON.parse(value)
    else value
    end
  end

  private

  def value_within_bounds
    numeric = begin
      BigDecimal(value)
    rescue ArgumentError, TypeError
      return
    end

    if min_value.present? && numeric < min_value
      errors.add(:value, "must be >= #{min_value}")
    end

    if max_value.present? && numeric > max_value
      errors.add(:value, "must be <= #{max_value}")
    end
  end

  def invalidate_cache
    Rails.cache.delete(self.class.cache_key_for(key))
  end

  def self.cache_key_for(key)
    "#{CACHE_KEY_PREFIX}:#{key}"
  end
end
