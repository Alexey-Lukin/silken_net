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
    2 => %w[leaf_version telemetry_log_id device_uid raw_record qatt_envelope_sha256 ema_delta_t_s
            growth_points created_at].freeze
  }.freeze
  RAW_RECORD_HEX = /\A\h{60}\z/ # 30 Б кадру ефіру CCM у нижньому hex
  SHA256_HEX = /\A\h{64}\z/
  DID_FORMAT = "SNET-%08X"
  EMA_MAX_S = 0xFFFF # u16 кадру

  # ⚖️ [FW.66 (Б) · S8b, `05_02 §E.60`] Формула балів листа v2 — ЗАМОРОЖЕНИЙ свідок. Живі пороги
  # (`firmware/bio_contracts/metabolic_core.rb`) — placeholder до bench-кривої E.63, і з калібруванням
  # вони зміняться; верифікатор, що читав би їх з чекауту, оголосив би кожен старий лист підробкою.
  # Тож формула — власність ВЕРСІЇ листа: тут вона назавжди та, з якою v2-листи писались, а
  # калібрування = лист v3 із власною формулою. Рівність живій формулі пінить спека
  # `Mrv::TelemetryLeaf` на всьому діапазоні u16 — доки v2 чинний, розійтись вони не можуть.
  V2_POINTS = { delta_t_fast_s: 600, delta_t_slow_s: 7200, gp_min: 5, gp_max: 31, wire_scale: 2 }.freeze

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
    errs.concat(raw_record_errors(payload) + v2_content_errors(payload)) if version == 2
    errs
  end

  # Бали кадру гомеостазу з цим входом за формулою v2 — база до коефіцієнта породи й відра E.64.
  # NULL (паніка) і 0 («не виміряно», ARCH.102) — нуль. Вхід — твердження сервера: перевірна лише
  # узгодженість балів із ним, не сам вхід.
  def v2_credited_points(ema_delta_t_s)
    return 0 if ema_delta_t_s.nil? || ema_delta_t_s.zero?

    f = V2_POINTS
    m = (f[:delta_t_slow_s] - ema_delta_t_s).to_f / (f[:delta_t_slow_s] - f[:delta_t_fast_s])
    gp = (f[:gp_min] + (m.clamp(0.0, 1.0) * (f[:gp_max] - f[:gp_min]))).round
    gp.clamp(f[:gp_min], f[:gp_max]) * f[:wire_scale]
  end

  # Нуль при додатній формулі — бали кадру утримано: тест відповідності не пройдено або статус не
  # гомеостаз (паніку, vm_error чи стрес несе шифртекст). Причину лист не несе — лише факт.
  def v2_points_held?(payload)
    payload["growth_points"].zero? && v2_credited_points(payload["ema_delta_t_s"]).positive?
  end

  # Вміст v2 понад кадр. Бали рівно дві законні: нуль (утримано / не гомеостаз) або формула v2
  # від входу — третє значення є підробкою листа, бо сервер іншого не пише.
  def v2_content_errors(payload)
    sha = payload["qatt_envelope_sha256"]
    ema = payload["ema_delta_t_s"]
    points = payload["growth_points"]
    errs = []
    errs << "qatt_envelope_sha256 не null і не 64 нижніх hex" unless sha.nil? || (sha.is_a?(String) && sha.match?(SHA256_HEX) && sha == sha.downcase)
    errs << "ema_delta_t_s не null і не ціле 0..#{EMA_MAX_S}" unless ema.nil? || (ema.is_a?(Integer) && ema.between?(0, EMA_MAX_S))
    return errs << "growth_points не невідʼємне ціле" unless points.is_a?(Integer) && points >= 0
    return errs unless errs.empty?

    expected = v2_credited_points(ema)
    errs << "growth_points #{points} ∉ {0, #{expected}} — формула v2 від ema_delta_t_s=#{ema.inspect}" unless [ 0, expected ].include?(points)
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
