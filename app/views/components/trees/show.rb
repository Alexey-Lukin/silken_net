# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Trees
  class Show < ApplicationComponent
    # All data must be pre-loaded in the controller — no fallback queries.
    # @param tree [Tree] must respond to :did, :status, :current_stress
    # @param latest_log [TelemetryLog, nil] pre-loaded latest telemetry
    # @param recent_logs [Array<TelemetryLog>] pre-loaded recent telemetry logs
    # @param maintenance_history [Array<MaintenanceRecord>] pre-loaded records (includes :user)
    def initialize(tree:, latest_log:, recent_logs:, maintenance_history:)
      raise ArgumentError, "tree must respond to :did" unless tree.respond_to?(:did)

      @tree = tree
      @latest_log = latest_log
      @recent_logs = recent_logs
      @family = @tree.tree_family
      @maintenance_history = maintenance_history
      @hardware_key = @tree.hardware_key
    end

    def view_template
      div(class: "space-y-10 animate-in fade-in duration-1000") do
        render_header

        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          # ЛІВИЙ КОНТУР: Біометрія та Графіки
          div(class: "xl:col-span-2 space-y-10") do
            render_biometric_panel
            render_maintenance_ledger # Журнал зцілень
          end

          # ПРАВИЙ КОНТУР: Економіка, Безпека, Локація
          div(class: "space-y-10") do
            render_economic_panel
            render_hardware_security_vault # Криптографічний статус
            render_metadata_panel
          end
        end

        # ЦИФРОВИЙ ЖИТТЄПИС (Digital Chronicle) — lazy-loaded Turbo Frame
        render_chronicle_frame
      end
    end

    private

    # Lazy-lookup helper scoped to the `trees.show.*` namespace.


    def render_chronicle_frame
      div(class: "p-8 border border-gaia-border bg-gaia-surface-sunken") do
        turbo_frame_tag("tree_chronicle", src: chronicle_tree_path(@tree), loading: :lazy) do
          render Views::Shared::UI::Skeleton.new(variant: :table)
        end
      end
    end

    def render_header
      div(class: "flex flex-col md:flex-row justify-between items-start md:items-center p-8 border border-gaia-border bg-gaia-surface shadow-2xl relative overflow-hidden") do
        # Декоративний фон
        div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { "SOLDIER" }

        div do
          h2(class: "text-4xl font-extralight tracking-tighter text-gaia-text") { @tree.did }
          div(class: "flex items-center gap-3 mt-2") do
            render Views::Shared::UI::StatusBadge.new(status: @tree.status)
            span(class: "text-tiny text-gaia-text-subtle font-mono") { t(".labels.family", name: @family&.name || t(".labels.family_unknown")) }
          end
          render_codex_citations
        end

        div(class: "mt-6 md:mt-0 flex items-center gap-12") do
          div(class: "text-right") do
            p(class: "text-mini text-gaia-text-muted uppercase tracking-widest") { t(".labels.uplink_state") }
            p(class: "text-sm font-mono text-emerald-100") { @latest_log&.created_at&.strftime("%H:%M:%S // %d.%m.%y") || "SILENT" }
          end
          div(class: tokens("h-4 w-4 rounded-sm rotate-45", status_led_class))
        end
      end
    end

    # Phase 6 — Codex citation strip. Lazily looks up citations on the
    # tree so the show page surfaces lore stitches forester+ have made.
    # Wrapped in a `gaia-*` island so the surrounding emerald palette
    # of `Trees::Show` (legacy) doesn't bleed through.
    def render_codex_citations
      return unless defined?(::Codex::Citation)
      citations = ::Codex::Citation.for_target(@tree).includes(node: :realm).limit(20)
      return if citations.empty?

      div(class: "mt-3") do
        render ::Codex::Citations::Strip.new(target: @tree, citations: citations)
      end
    end

    def render_biometric_panel
      div(class: "p-8 border border-gaia-border bg-gaia-surface-sunken") do
        h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-10") { t(".headings.biometrics") }

        div(class: "grid grid-cols-1 md:grid-cols-2 gap-12 items-center") do
          div(class: "relative h-56 w-56 mx-auto") do
            render_radial_svg
            div(class: "absolute inset-0 flex flex-col items-center justify-center") do
              # `&.to_f` тримає ФОРМАТ: `z_value` — колонка `decimal`, тобто BigDecimal
              # із точністю схеми. Зникнути вона вже не може (`ApplicationComponent`
              # заповнив Phlex-хук `format_object`), але без цього тут друкувалась би
              # сира точність замість числа під `text-6xl`. ⚠️ Фолбек `|| "---"` не
              # спрацьовує НІКОЛИ — BigDecimal істинний, гілка не береться. Дім → `04_04 §2`.
              span(class: "text-6xl font-extralight text-gaia-text-strong") { @latest_log&.z_value&.to_f || "---" }
              # [ARCH.86] Підпис називає ВЕЛИЧИНУ, а не одиницю: Z безрозмірний.
              span(class: "text-tiny text-gaia-text-subtle font-mono uppercase") { t(".biometrics.lorenz_z") }
            end
          end

          div(class: "space-y-6") do
            # [ARCH.99] Мітки називають ВИМІРЯНЕ, не бажане. `voltage_mv` — це мВ VDDA
            # (шина живлення MCU через VREFINT-калібрування, `03_01` FW.50), НЕ заряд
            # іоністора: реального Vcap-каналу на вузлі не існує. `temperature_c` —
            # температура кристала STM32 (внутрішній датчик), не ксилеми.
            # ⚠️ Підпис `core_sub` тут не новий — він казав правду («температура
            # внутрішнього ядра») роками, суперечачи власному ж заголовку.
            metric_row(t(".biometrics.supply_voltage"), "#{@latest_log&.voltage_mv || 0} mV", sub: t(".biometrics.supply_sub"))
            metric_row(t(".biometrics.core_temperature"), "#{@latest_log&.temperature_c || 0} °C", sub: t(".biometrics.core_sub"))
            stress_pct = ((@tree.current_stress || 0) * 100).round(1)
            metric_row(t(".biometrics.stress_index"), "#{stress_pct}%", danger: @tree.under_threat?)
          end
        end
      end
    end

    def render_maintenance_ledger
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".headings.maintenance") }

        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-tiny") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-micro") do
              tr do
                th(scope: "col", class: "p-4") { t(".table.technician") }
                th(scope: "col", class: "p-4") { t(".table.action") }
                th(scope: "col", class: "p-4") { t(".table.observations") }
                th(scope: "col", class: "p-4 text-right") { t(".table.timestamp") }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              if @maintenance_history.any?
                @maintenance_history.each do |record|
                  tr(class: "hover:bg-gaia-surface-sunken transition-colors") do
                    td(class: "p-4 text-emerald-100") { record.user&.full_name || "Unknown" }
                    td(class: "p-4 uppercase text-gaia-primary") { record.action_type }
                    td(class: "p-4 text-gaia-text-muted italic") { record.notes&.truncate(50) || "—" }
                    td(class: "p-4 text-right text-gaia-text-muted") { record.performed_at&.strftime("%d.%m.%y") || "—" }
                  end
                end
              else
                tr { td(colspan: 4, class: "p-10 text-center text-gaia-text-subtle uppercase tracking-widest") { t(".table.empty") } }
              end
            end
          end
        end
      end
    end

    def render_hardware_security_vault
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-6") do
        div(class: "flex justify-between items-center") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".headings.hardware_vault") }
          span(class: "h-2 w-2 rounded-full bg-blue-500 shadow-[0_0_8px_#3b82f6]")
        end

        div(class: "space-y-4 text-tiny font-mono") do
          security_item(t(".security.key_identity"), @hardware_key&.device_uid || "NOT_PROVISIONED")
          security_item(t(".security.cipher_suite"), t(".security.cipher_value"))
          security_item(t(".security.integrity"), t(".security.integrity_value"))
          security_item(t(".security.ota_status"), t(".security.ota_value"))
        end

        # [UI.7] Кнопка ротації схована до дротування — interim-форма ARCH.69
        # (тіло в git, локаль-ключі лишаються). Підстава НЕ «сервіс за закритим
        # гейтом»: маршруту `rotate` не існує, а `HardwareKeyService.rotate` має
        # нуль продакшн-викликачів, тож це був голий `<button>` без цілі. Гейт
        # `FW17_RATCHET_DOWNLINK_ENABLED` стосується того, що станеться ПІСЛЯ
        # дротування, а не поточного кліку.
      end
    end

    def render_economic_panel
      div(class: "p-6 border border-gaia-border bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".headings.economic_yield") }
        div(class: "space-y-4") do
          div do
            p(class: "text-mini text-gaia-text-muted uppercase") { t(".labels.verified_balance") }
            div(class: "flex items-baseline gap-2") do
              # 🔴 Те саме, що в біометричній панелі: `balance` — `decimal`, тож без
              # `&.to_f` баланс рендерився ПОРОЖНІМ, а поруч лишався самотній тікер.
              # ✅ [ARCH.88] Підпис виправлено: це БАЛИ росту, не монети — читаємо
              # `balance` напряму, одиниця з локалі.
              span(class: "text-3xl font-light text-gaia-text-strong") { formatted_points(@tree.wallet&.balance || 0) }
              span(class: "text-xs text-gaia-primary-hover font-mono") { t(".labels.unit") }
            end
          end
          wallet_address = @tree.wallet&.crypto_public_address
          address_display = wallet_address.present? ? "#{wallet_address.first(12)}..." : "NOT_PROVISIONED"
          security_item(t(".security.address"), address_display, full: wallet_address)
        end
      end
    end

    def render_metadata_panel
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".headings.deployment_matrix") }
        div(class: "space-y-3 text-tiny font-mono") do
          meta_row(t(".metadata.cluster"), @tree.cluster&.name)
          meta_row(t(".metadata.coordinates"), "#{@tree.latitude}, #{@tree.longitude}")

          a(
            href: "https://www.google.com/maps?q=#{@tree.latitude},#{@tree.longitude}",
            target: "_blank",
            class: "block mt-4 text-center p-2 border border-gaia-border-strong text-gaia-primary-hover hover:bg-gaia-surface-sunken hover:text-gaia-text-strong transition-all uppercase focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary",
            aria_label: t(".locate_aria")
          ) { t(".actions.locate_node") }
        end
      end
    end

    # --- HELPERS ---

    def metric_row(label, value, sub: nil, danger: false)
      div(class: "flex justify-between items-end border-b border-gaia-border pb-2") do
        div do
          p(class: "text-mini text-gaia-text-muted uppercase") { label }
          p(class: "text-micro text-gaia-text-subtle font-mono") { sub } if sub
        end
        span(class: tokens("text-lg font-mono", "text-red-500 animate-pulse": danger, "text-emerald-300": !danger)) { value }
      end
    end

    def security_item(label, value, full: nil)
      div do
        p(class: "text-micro text-gaia-text-muted uppercase mb-1") { label }
        p(class: "text-gaia-primary truncate", title: full) { value }
      end
    end

    def meta_row(label, value)
      div(class: "flex justify-between") do
        span(class: "text-gaia-text-muted") { "#{label}:" }
        span(class: "text-gaia-text") { value }
      end
    end

    def render_radial_svg
      stress_factor = @tree.current_stress || 0
      offset = 552 * (1 - stress_factor)
      svg(class: "h-56 w-56 -rotate-90 transform") do
        circle(cx: "112", cy: "112", r: "88", class: "fill-none stroke-emerald-950 stroke-1")
        circle(
          cx: "112", cy: "112", r: "88",
          class: tokens(
            "fill-none stroke-[3] transition-all duration-1000",
            "stroke-red-600 animate-pulse": @tree.under_threat?,
            "stroke-emerald-500 shadow-[0_0_15px_#10b981]": !@tree.under_threat?
          ),
          style: "stroke-dasharray: 552; stroke-dashoffset: #{offset};"
        )
      end
    end

    def status_led_class
      recently_seen = @latest_log&.created_at&.after?(15.minutes.ago)
      tokens("bg-emerald-500 shadow-[0_0_12px_#10b981]": recently_seen, "bg-red-900": !recently_seen)
    end
  end
end
