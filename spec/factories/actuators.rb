# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :actuator do
    sequence(:name) { |n| "Actuator #{n}" }
    sequence(:endpoint) { |n| "ep-#{n}" }
    device_type { :water_valve }
    state { :idle }
    # [ARCH.75] Дефолт = протокольна стеля одного наказу, тобто «цей пристрій
    # витягує повноцінну команду». Доти тут стояло 300 с, і приклади
    # `EmergencyResponseService` створювали накази понад власний safety envelope
    # (клапан і сирена — 3600 проти 300, тобто вдванадцятеро; маяк — 1800 проти
    # 300, ушестеро) — `insert_all` валідації обходить, тож спеки були зелені,
    # пінячи `duration_seconds` як правильну поведінку й жодного разу не питаючи
    # `valid?`. Стелю, НИЖЧУ за потрібну, приклади тепер задають ЯВНО — саме там,
    # де її й перевіряють.
    max_active_duration_s { ActuatorCommand::MAX_DURATION_S }
    estimated_mj_per_action { 37.95 }
    gateway

    trait :water_valve do
      device_type { :water_valve }
    end

    trait :fire_siren do
      device_type { :fire_siren }
    end

    trait :seismic_beacon do
      device_type { :seismic_beacon }
    end
  end
end
