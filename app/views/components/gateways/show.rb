# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Gateways
  class Show < ApplicationComponent
    # All data must be pre-loaded in the controller — no fallback queries.
    # @param gateway [Gateway] must respond to :uid, :state, :last_seen_at
    # @param latest_log [GatewayTelemetryLog, nil] pre-loaded latest telemetry
    # @param active_soldiers [Array<Tree>] pre-loaded active soldiers
    def initialize(gateway:, latest_log:, active_soldiers:)
      raise ArgumentError, "gateway must respond to :uid" unless gateway.respond_to?(:uid)

      @gateway = gateway
      @latest_log = latest_log
      @active_soldiers = active_soldiers
    end

    def view_template
      div(class: "space-y-8") do
        render_status_header

        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          # Технічний контур (Сигнал, Енергія, Температура)
          div(class: "lg:col-span-2 space-y-8") do
            render_technical_matrix
            render_soldier_fleet_overview
          end

          # Панель управління та Метадані
          div(class: "space-y-8") do
            render_network_config
            render_ota_evolution
            render_hardware_vault
          end
        end
      end
    end

    private

    def render_status_header
      div(class: "flex flex-col md:flex-row justify-between items-start md:items-center p-6 border border-gaia-border bg-gaia-surface shadow-2xl") do
        div do
          # [I18N.1] Реюз канонічного show_title (той самий, що контролер кладе в
          # <title>): доти екран казав «Queen Relay // …», а вкладка «Queen // …» —
          # слово «Relay» не мала ЖОДНА з чотирьох локалей.
          h2(class: "text-3xl font-extralight tracking-tighter text-gaia-text-strong") { t("gateways.show_title", uid: @gateway.uid) }
          div(class: "flex items-center mt-2 gap-3") do
            render Views::Shared::UI::StatusBadge.new(status: @gateway.state)
            span(class: "text-tiny text-gaia-text-subtle font-mono") { "IP: #{@gateway.ip_address || '0.0.0.0'}" }
          end
        end

        div(class: "mt-4 md:mt-0 flex items-center gap-10") do
          div(class: "text-right") do
            p(class: "text-mini text-gaia-text-muted uppercase tracking-widest") { t(".header.heartbeat") }
            p(class: "text-sm font-mono text-gaia-text-strong") { @gateway.last_seen_at&.strftime("%H:%M:%S // %d.%m.%y") || t(".labels.silent") }
          end
          div(class: tokens("h-4 w-4 rounded-sm rotate-45", connection_led_classes))
        end
      end
    end

    def render_technical_matrix
      div(class: "p-8 border border-gaia-border bg-gaia-surface-sunken") do
        h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-10") { t(".telemetry.heading") }

        div(class: "grid grid-cols-1 md:grid-cols-3 gap-12") do
          # Cellular Signal (CSQ)
          render_circular_metric(
            label: t(".telemetry.signal_strength"),
            # [ARCH.84] Обидва `|| 0` знято: 99 = «unknown» за 3GPP, а CSQ=0 — ВАЛІДНЕ
            # значення (−113 dBm, гранична чутливість), тож підстановка нуля робила
            # «модем не відповів» невідрізнимим від «сигнал на межі».
            value: measured_value(@latest_log&.signal_quality_percentage, "%", space: false),
            subtext: t(".telemetry.signal_csq", csq: @latest_log&.cellular_signal_csq || t("ui.measurement.not_measured")),
            color: signal_color
          )

          # Power / Battery
          render_circular_metric(
            label: t(".telemetry.voltage_matrix"),
            value: "#{@latest_log&.voltage_mv || '---'}",
            subtext: t(".telemetry.mvolt"),
            color: battery_color
          )

          # Internal Temperature
          render_circular_metric(
            label: t(".telemetry.thermal_state"),
            value: "#{@latest_log&.temperature_c || '--'}°C",
            subtext: t(".telemetry.internal_core"),
            color: temp_color
          )
        end
      end
    end

    def render_soldier_fleet_overview
      div(class: "p-6 border border-gaia-border bg-gaia-surface-sunken") do
        div(class: "flex justify-between items-center mb-6") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".fleet.heading") }
          # `.size`, не `.count`: наступний рядок ітерує ту саму колекцію, тож на
          # relation це був COUNT плюс SELECT. `.size` не перепитує БД ніколи.
          span(class: "text-tiny font-mono text-gaia-primary-strong") { t(".fleet.active_nodes", count: @active_soldiers.size) }
        end

        # Маленька сітка солдатів у реальному часі
        div(class: "flex flex-wrap gap-2") do
          @active_soldiers.each do |tree|
            render_soldier_node_indicator(tree)
          end
        end
      end
    end

    def render_network_config
      div(class: "p-6 border border-gaia-border bg-gaia-surface-sunken") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".config.heading") }
        div(class: "space-y-4 font-mono text-compact") do
          config_row(t(".config.cluster"), @gateway.cluster&.name || t(".config.unassigned"))
          config_row(t(".config.sleep_interval"), "#{@gateway.config_sleep_interval_s || 60}s")
          config_row(t(".config.firmware_version"), @gateway.firmware_version || "—")
          # [UI.10] Рядка «Firmware Hash» тут більше немає, і це присуд, а не
          # недогляд: джерела в системі не було ніколи. Єдиний кандидат —
          # `pending_firmware_id` — назвав би хеш ОЧІКУВАНОЇ прошивки просто під
          # версією ВСТАНОВЛЕНОЇ, тобто дві різні прошивки в сусідніх рядках під
          # спільним підписом. Хеш як доказ цілісності належить attestation-осі
          # (QATT), не конфіг-панелі.
          # 🔴 [UI.17] А рядок «Mesh Mode: Enabled» стояв ТУТ ЖЕ, за пʼять
          # рядків нижче, зашитою парою літералів — і причина, записана вище
          # власноруч, стосувалась його дослівно. Перевірено схемою: `gateways`
          # має 19 колонок і НУЛЬ mesh-полів (єдиний `mesh_ttl` лежить на
          # партиціях `telemetry_logs` і тут не читається жодного разу).
          # **Урок ширший за сайт: закривши напис, перечитай МЕТОД цілком —
          # погляд на діагнозі конкретного рядка не бачить сусіда тієї ж форми.**
        end
      end
    end

    # [SEC.20] Живий OTA-прогрес: підписка на персональний канал шлюзу;
    # broadcast'ить Downlink::PendingQueueService (FW.60 poll-тракт).
    def render_ota_evolution
      turbo_stream_from TurboStreams::Name.gateway_ota(@gateway)
      render Firmwares::OtaProgressBar.new(
        uid: @gateway.uid,
        percent: 0, current: 0, total: 0,
        status: initial_ota_status
      )
    end

    def initial_ota_status
      return "TRANSMITTING" if @gateway.updating?
      return "PENDING" if @gateway.pending_firmware_id

      "IDLE"
    end

    def render_hardware_vault
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".crypto.heading") }
        div(class: "space-y-2 text-tiny font-mono") do
          p(class: "text-gaia-text-muted") { t(".crypto.uid_label") }
          p(class: "text-gaia-primary-strong truncate") { @gateway.hardware_key&.device_uid || t(".crypto.uid_undefined") }

          # [UI.17] Крапка й напис були БЕЗУМОВНІ, тобто непровізіонований шлюз
          # рапортував себе захищеним рядком нижче власного «UNDEFINED».
          # `has_one :hardware_key` не має авто-створення — провізіювання це
          # окрема дія (`HardwareKeyService.provision`, SEC.3), — тож nil тут
          # НОРМАЛЬНИЙ стан до провізіювання, а не крайній випадок.
          # ⊕ Крапка заразом перейшла з `bg-emerald-900` на `-accent`/`-subtle`:
          # як СИГНАЛ вона підпадає під 1.4.11 (бар 3:1), а пастельний
          # emerald-900 його не тримав (UI.1, не-текстова половина).
          if @gateway.hardware_key.present?
            div(class: "mt-4 flex items-center gap-2 text-gaia-primary-strong") do
              span(class: "h-2 w-2 bg-gaia-primary-strong rounded-full")
              span { t(".crypto.aes_provisioned") }
            end
          else
            div(class: "mt-4 flex items-center gap-2 text-status-warning-text") do
              span(class: "h-2 w-2 bg-status-warning-accent rounded-full")
              span { t(".crypto.aes_not_provisioned") }
            end
          end
        end
      end
    end

    # --- HELPERS ---

    def render_circular_metric(label:, value:, subtext:, color:)
      div(class: "flex flex-col items-center") do
        div(class: tokens("h-24 w-24 rounded-full border-2 flex flex-col items-center justify-center mb-4", color)) do
          span(class: "text-xl font-light text-gaia-text-strong") { value }
        end
        p(class: "text-mini uppercase text-gaia-text-muted tracking-tighter") { label }
        p(class: "text-tiny font-mono text-gaia-text-subtle") { subtext }
      end
    end

    def render_soldier_node_indicator(tree)
      # Квадратик статусу дерева — маленька візуальна мапа флоту
      div(
        title: tree.did,
        role: "img",
        aria_label: tree.active? ? t(".soldier_active_aria", did: tree.did) : t(".soldier_inactive_aria", did: tree.did),
        class: tokens(
          "h-4 w-4 border transition-colors",
          "border-gaia-primary-strong bg-gaia-primary-strong/10": tree.active?,
          "border-status-neutral-accent bg-gaia-surface-sunken": !tree.active?,
          "border-status-danger-accent bg-status-danger-accent/10 animate-pulse": tree.under_threat?
        )
      )
    end

    def config_row(label, value)
      div(class: "flex justify-between border-b border-gaia-border pb-2") do
        span(class: "text-gaia-text-muted") { "#{label}:" }
        span(class: "text-gaia-text") { value }
      end
    end

    def connection_led_classes
      # `Gateway#online?` — один дім порога (`config_sleep_interval_s * 1.2`);
      # локальні «5 хвилин» суперечили і сторожу, і сусідній сторінці.
      recently_seen = @gateway.online?
      tokens("bg-gaia-primary-strong shadow-[0_0_8px_#10b981]": recently_seen, "bg-status-danger-accent animate-pulse": !recently_seen)
    end

    # [UI.1 сигнальна хвиля] Кільця signal/temp — КОНСТАНТИ (нічого не міряють), і
    # «завжди зелена» рамка стверджувала здоровʼя без виміру — та сама хвороба, що
    # ARCH.84-фолбек нижче. Нейтральна рамка чесно каже «не сигнал»; сигналить лише
    # battery — єдине кільце, що справді читає метрику.
    def signal_color; "border-gaia-border"; end
    # [ARCH.84] 🔴 Найтонша форма класу: ЗНАЧЕННЯ поруч чесне («---»), а КОЛІР брехав —
    # фолбек підставляв «здорову» напругу (4200 мВ Li-Po), тож невиміряний шлюз
    # діставав зелену рамку. Текст казав «не знаю», рамка казала «все гаразд», і
    # переважає завжди друге. Тепер станів три, як у `metric_row`: тривога · норма ·
    # не виміряно (нейтральний, бо тривога теж є твердженням про вимір).
    # [UI.1] Обидві живі гілки — токенні акценти: сирий `border-red-900` давав 1.92
    # у темній, тобто тривога низької напруги була невидимою рамкою.
    def battery_color
      mv = @latest_log&.voltage_mv
      return "border-gaia-border" if mv.nil?

      tokens("border-status-danger-accent": mv.to_i < 3400, "border-gaia-primary-strong": mv.to_i >= 3400)
    end
    def temp_color; "border-gaia-border"; end
  end
end
