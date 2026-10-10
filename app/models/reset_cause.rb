# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.59] Чому вузол перезавантажився — 3-бітний код на дроті обох вузлів: health-flags пульсу
# Королеви (`GatewayTelemetryLog`) і `diag[7..5]` CCM-кадру Солдата (`TelemetryLog`). Wire-дім
# кодів — `firmware/common/reset_cause.h`; парність пінить `spec/models/reset_cause_spec.rb`.
module ResetCause
  # Індекс = код на дроті. 🔴 `:unknown` на нулі — сентинел «не повідомлено», НІКОЛИ «холодний
  # старт»: кожен рядок, старший за FW.59, несе в цьому полі нуль, тож будь-яке інше прочитання
  # приписало б усій історії причину, якої ніхто не міряв.
  CAUSES = %i[unknown power_on pin software iwdg wwdg hardfault low_power].freeze

  # Vendor-attributable кошик: завис або впав НАШ код. Дзеркало — `Silken_Reset_Cause_Is_Fault`
  # у тому ж заголовку. ⚠️ `power_on` сюди НЕ входить: brownout — це залізо/сонце, не прошивка,
  # і атрибуція вирішує, кому потім виставить рахунок slashing.
  FAULT_CAUSES = %i[iwdg wwdg hardfault low_power].freeze

  # Поза 0..7 — «не повідомлено»: `Array#fetch(-1)` віддав би `low_power`, тобто вигадану причину.
  def self.from_code(code) = code.is_a?(Integer) && code.between?(0, CAUSES.size - 1) ? CAUSES[code] : :unknown

  def self.fault?(cause) = FAULT_CAUSES.include?(cause&.to_sym)
end
