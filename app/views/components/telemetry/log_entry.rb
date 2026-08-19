# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Telemetry::LogEntry — single row appended to the live HUD via Turbo Stream.
# Carries `data-label` attributes so the parent `gaia-responsive-table`
# flips into a card on mobile (CSS in application.css).
#
# 🔴 [I18N.2] Тіло рядка НЕ локалізується, і це присуд, а не недогляд
# (⚖️ founder 2026-08-14). Компонент рендериться ТІЛЬКИ з Sidekiq
# (`UnpackTelemetryWorker`), а локаль там не виставляє ніхто — тобто кожен `t()`
# тут був **мертвим перекладом за побудовою**: значення uk/lv/lt не бачив жоден
# користувач ЖОДНОГО разу (`04_04 §8.1а`, другий клас відмови).
#
# Заморожені токени — не втрата, а чесність: рядок і так моноширинний
# SCREAMING_SNAKE HUD, тобто читається як вивід машини. ⚠️ Але це НЕ канонний
# випадок «транслітерації» (`ЧАНК`): `ПАКЕТ_ОТРИМАНО` був справжнім перекладом,
# просто недосяжним — тож підстава тут «мертвий переклад», а не «фальшивий».
#
# ⊕ `IP:`-префікс і `?.?.?.?` пішли з YAML із ІНШОЇ причини: вони були
# байт-у-байт однакові в усіх чотирьох локалях, тобто ДАНІ, а не переклад —
# YAML-дім змушував тримати чотири копії й чотири зобовʼязання парності назавжди.
module Telemetry
  class LogEntry < ApplicationComponent
    # Locale-інваріантні токени HUD. Константами, а не літералами в розмітці:
    # так вони мають одне імʼя для гейта payload-інваріантності й для читача.
    BATCH_RECEIVED = "BATCH_RECEIVED"
    UNKNOWN_RELAY  = "UNKNOWN_RELAY"
    UNKNOWN_IP     = "?.?.?.?"

    def initialize(gateway:, hex_payload:, timestamp:)
      @gateway = gateway
      @hex_payload = hex_payload
      @timestamp = timestamp
    end

    def view_template
      tr(class: "hover:bg-gaia-surface-sunken md:border-b md:border-gaia-border group") do
        td(
          class: "p-3 text-gaia-text-muted font-mono text-mini"
        ) { @timestamp.strftime("%H:%M:%S.%L") }

        td(class: "p-3") do
          span(class: "text-gaia-primary-strong font-bold") { @gateway&.uid || UNKNOWN_RELAY }
          span(class: "ml-2 text-micro text-gaia-text-subtle") do
            "IP: #{@gateway&.ip_address || UNKNOWN_IP}"
          end
        end

        td(
          class: "p-3 font-mono text-gaia-text-strong/80 break-all leading-tight text-mini tracking-tighter"
        ) { @hex_payload }

        td(class: "p-3 text-right text-micro uppercase tracking-widest") do
          span(class: "px-2 py-0.5 border border-gaia-border text-gaia-text-muted group-hover:text-gaia-text group-hover:border-gaia-primary transition-colors") do
            BATCH_RECEIVED
          end
        end
      end
    end

    private
  end
end
