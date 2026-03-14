# frozen_string_literal: true

# @label IoT Metric Value
# @display bg_color "#000"
class IoTMetricValuePreview < Lookbook::Preview
  # @label Default (4 decimal places)
  # @notes Standard precision for sensor readings.
  def default
    render Views::Shared::IoT::MetricValue.new(value: 3.14159265, unit: "σ")
  end

  # @label High Precision
  # @notes 8 decimal places for Lorenz attractor parameters.
  def high_precision
    render Views::Shared::IoT::MetricValue.new(value: 10.00000001, unit: "ρ", precision: 8)
  end

  # @label Nil Value
  # @notes Displays dash placeholder when no reading available.
  def nil_value
    render Views::Shared::IoT::MetricValue.new(value: nil, unit: "mV")
  end

  # @label Without Unit
  # @notes Raw numeric display without a unit suffix.
  def without_unit
    render Views::Shared::IoT::MetricValue.new(value: 42.0)
  end

  # @label Interactive
  # @param value text "Numeric value"
  # @param unit text "Unit suffix (σ, ρ, β, mV, °C, etc.)"
  # @param precision range { min: 0, max: 10, step: 1 }
  def interactive(value: "28.123456", unit: "β", precision: 4)
    val = value.present? ? value.to_f : nil
    render Views::Shared::IoT::MetricValue.new(value: val, unit: unit.presence, precision: precision.to_i)
  end
end
