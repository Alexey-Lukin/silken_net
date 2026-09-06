# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Telemetry::BatchSummary — один рядок живої стрічки: ЗВЕДЕННЯ одного конверта
# (флашу Королеви), а не сирий hex і не окремий запис.
#
# 🔴 [UI.16, 2026-09-06] Замінив `Telemetry::LogEntry`, який показував лісгоспові
# `binary_data.unpack1("H*")` — сирий шістнадцятковий вміст CoAP-конверта, під
# заголовком колонки, що це прямо й називав. Дефект СЕМАНТИЧНИЙ і чинний при ОДНОМУ
# дереві, тож жодна каденція його не лікує; попередній пункт відкладав роботу на
# `Tree.count ≥ 10 000`, тобто причепив пускач не до тієї проблеми.
#
# ⚠️ ЧОМУ ОДИНИЦЯ — КОНВЕРТ, А НЕ ЗАПИС. Розібраний рядок на кожен запис дав би
# ~45 рядків на флаш, тобто повернув би рівно той throughput-аргумент, задля якого
# пункт колись і завели. Зведення — єдина форма, що лікує зміст і не платить за це
# потоком.
#
# 🔒 КЛАС 1 (`04_04 §8.1а`), і тут це не вибір, а ВИМОГА: компонент рендериться
# ТІЛЬКИ з Sidekiq (`UnpackTelemetryWorker`), де локаль не виставляє ніхто, тож
# будь-який `t()` був би **мертвим перекладом за побудовою**. Підписи колонок живуть
# у хромі сторінки (`Telemetry::LiveStream` → `--gaia-col-N`), відрендереному в
# запиті, де локаль відома. Тому все нижче — числа, UID, час і оголошені токени.
# ⛔ Не додавати сюди `t()` і не переносити сюди підписи: `spec/i18n/
# broadcast_payload_invariance_spec.rb` сканує кожен `html:`-компонент броадкасту, і
# його список винятків порожній — тримати його порожнім і є норма.
module Telemetry
  class BatchSummary < ApplicationComponent
    UNKNOWN_RELAY = "UNKNOWN_RELAY"
    UNKNOWN_IP    = "?.?.?.?"

    # Токени стану конверта. Порядок і зміст — дзеркало
    # `TelemetryUnpackerService::Summary#state`; тут лише подання.
    # ⚠️ `PARTIAL` каже «частину записів НЕ ПРИЙНЯТО», а не «дереву погано» —
    # злиття цих двох приписало б вузлові нашу ваду.
    STATE_TOKENS = {
      ok: "OK",
      attention: "ATTENTION",
      partial: "PARTIAL",
      panic: "PANIC"
    }.freeze

    STATE_STYLES = {
      ok: "border-gaia-border text-gaia-text-muted group-hover:text-gaia-text group-hover:border-gaia-primary",
      attention: "border-status-warning-accent text-status-warning-text",
      partial: "border-status-warning-accent text-status-warning-text",
      panic: "border-status-danger-accent text-status-danger-text"
    }.freeze

    # Не-гомеостазні статуси, показані окремими лічильниками. Гомеостаз свідомо не
    # дублюється числом: він і є `records − сума решти`, а другий вивід тієї самої
    # величини рано чи пізно розійшовся б із першим.
    COUNTED_STATUSES = %i[stress anomaly vm_error].freeze
    STATUS_TOKENS = { stress: "STRESS", anomaly: "ANOMALY", vm_error: "VM_ERR" }.freeze

    def initialize(gateway:, summary:, timestamp:)
      @gateway = gateway
      @summary = summary
      @timestamp = timestamp
    end

    def view_template
      tr(class: "hover:bg-gaia-surface-sunken md:border-b md:border-gaia-border group") do
        td(class: "p-3 text-gaia-text-muted font-mono text-mini") { @timestamp.strftime("%H:%M:%S.%L") }

        td(class: "p-3") do
          span(class: "text-gaia-primary-strong font-bold") { @gateway&.uid || UNKNOWN_RELAY }
          span(class: "ml-2 text-micro text-gaia-text-subtle") { "IP: #{@gateway&.ip_address || UNKNOWN_IP}" }
        end

        td(class: "p-3 font-mono text-gaia-text-strong/80 text-mini") { records_cell }

        td(class: "p-3 text-right text-micro uppercase tracking-widest") { state_badge }
      end
    end

    private

    def records_cell
      span(class: "text-gaia-text-strong font-bold tabular-nums") { @summary.records.to_s }

      # Втрачені записи показуємо ЗАВЖДИ, коли вони є: тиха різниця між «прийнято»
      # і «прийшло» — рівно те, що робить стрічку декоративною.
      if @summary.dropped.positive?
        span(class: "ml-2 text-status-warning-text tabular-nums") { "−#{@summary.dropped}" }
      end

      COUNTED_STATUSES.each do |status|
        count = @summary.statuses[status].to_i
        next unless count.positive?

        span(class: "ml-3 text-micro text-status-warning-text tracking-widest") do
          "#{STATUS_TOKENS.fetch(status)}·#{count}"
        end
      end
    end

    def state_badge
      state = @summary.state
      span(class: tokens("px-2 py-0.5 border transition-colors", STATE_STYLES.fetch(state))) do
        STATE_TOKENS.fetch(state)
      end
    end
  end
end
