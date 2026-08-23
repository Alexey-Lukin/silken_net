# SPDX-License-Identifier: AGPL-3.0-or-later
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

  # [ARCH.57] Зміна протокольного параметра = економічно-привілейований акт (governance).
  # Create (seeds/bootstrap) свідомо не аудитується — привілейована межа = мутація значення.
  include Auditable
  after_update_commit :record_parameter_change_audit, if: :saved_change_to_value?

  scope :by_category, ->(cat) { where(category: cat) }

  # Primary API: fetch a parameter with cached lookup and default fallback.
  #
  #   SystemParameter.current(:lorenz_sigma, default: 10.0)
  #
  # Returns the typed value or the default if the key is not found.
  # Cache TTL: 24 hours (invalidated on update via after_commit).
  #
  # NB: `Rails.cache.fetch(cache_key) { … }` (single round-trip) замість
  # exist?+read+write — усуває TOCTOU race коли запис expires між exist?
  # і read (тоді read повертає nil, що б приймалося як "є в кеші → повернути").
  # `MISS_SENTINEL` кешує missing keys теж, щоб не бомбити find_by на
  # кожному `SystemParameter.current(:nonexistent_key)` виклику.
  MISS_SENTINEL = :__sysparam_miss__

  def self.current(key, default: nil)
    key = key.to_s
    cache_key = cache_key_for(key)

    cached = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      record = find_by(key: key)
      record ? record.typed_value : MISS_SENTINEL
    end

    cached == MISS_SENTINEL ? default : cached
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

  # [ARCH.57] organization_id: nil → ГЛОБАЛЬНИЙ ланцюг (параметри org-less).
  def record_parameter_change_audit
    from, to = saved_change_to_value
    record_audit_trail!(
      action: "system_parameter_changed",
      organization_id: nil,
      user_id: updated_by_id,
      metadata: { key: key, from: from, to: to, source: source }
    )
  end

  def value_within_bounds
    # `return` усередині `begin…end` у контексті ПРИСВОЄННЯ читається так, ніби
    # він віддає значення змінній, — насправді він виходить із методу. Розводимо
    # два наміри явно: rescue дає `nil`, вихід стоїть окремим рядком.
    numeric = begin
      BigDecimal(value)
    rescue ArgumentError, TypeError
      nil
    end
    return if numeric.nil?

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
