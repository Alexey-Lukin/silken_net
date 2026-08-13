# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :device_calibration do
    tree
    temperature_offset_c { 0.0 }
    vcap_coefficient { 1.0 }

    # [ARCH.56] Tree.after_create вже створює калібровку (ensure_calibration),
    # а device_calibrations.tree_id тепер unique — реюзаємо авто-створену.
    initialize_with { tree&.device_calibration || DeviceCalibration.new(tree: tree) }

    trait :critical_drift do
      temperature_offset_c { 6.0 }
    end
  end
end
