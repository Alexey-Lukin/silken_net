# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# LeafPayloadShape — форма payload'а листа Меркла за версією (`05_02 §E.60`), яку судять ОФЛАЙН
# обидва верифікатори (`scripts/verify_lineage_bundle.rb` · `scripts/verify_archive_bundle.rb`).
# Без Rails і залежностей. Формулу будує `Mrv::TelemetryLeaf`; що вона дає рівно ці ключі, пінить
# його спека проти цього модуля, тож набір ключів має один дім.
#
# Ключі — ТОЧНІ, не мінімальні: payload «без версії» (v1) із підкладеним `raw_record` інакше
# минав би перевірку DID кадру. Невідома версія — відмова: старий верифікатор, що не знає
# нової форми, мусить падати, а не мовчки пропускати її перевірки.
module LeafPayloadShape
  KEYS = {
    1 => %w[telemetry_log_id device_uid z_value bio_status created_at].freeze,
    2 => %w[leaf_version telemetry_log_id device_uid raw_record created_at].freeze
  }.freeze
  RAW_RECORD_HEX = /\A\h{60}\z/ # 30 Б кадру ефіру CCM у нижньому hex
  DID_FORMAT = "SNET-%08X"

  module_function

  # v1 версії не декларує (його формулу пінить золотий вектор), v2 — ключем `leaf_version`.
  def version_of(payload)
    return nil unless payload.is_a?(Hash)

    payload.key?("leaf_version") ? payload["leaf_version"] : 1
  end

  # Список порушень форми; порожній — форма ціла.
  def errors(payload)
    return [ "payload не є обʼєктом JSON" ] unless payload.is_a?(Hash)

    version = version_of(payload)
    keys = KEYS[version]
    return [ "невідома версія листа #{version.inspect}" ] unless keys

    errs = []
    errs << "ключі v#{version}: #{payload.keys.sort.inspect} ≠ #{keys.sort.inspect}" unless payload.keys.sort == keys.sort
    errs.concat(raw_record_errors(payload)) if version == 2
    errs
  end

  # Сирий кадр — шифртекст, тож офлайн перевірна лише його рамка: довжина й DID у перших 4 байтах.
  def raw_record_errors(payload)
    raw = payload["raw_record"]
    return [ "raw_record не 60 нижніх hex-символів" ] unless raw.is_a?(String) && raw.match?(RAW_RECORD_HEX) && raw == raw.downcase

    did = format(DID_FORMAT, raw[0, 8].to_i(16))
    did == payload["device_uid"] ? [] : [ "DID кадру #{did} ≠ device_uid #{payload['device_uid'].inspect}" ]
  end
end
