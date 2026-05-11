# frozen_string_literal: true

module Contracts
  class Show < ApplicationComponent
    def initialize(contract:, history:)
      @contract = contract
      @history = history
    end

    def view_template
      div(class: "space-y-8 animate-in zoom-in duration-500") do
        render_hero_section

        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          div(class: "lg:col-span-2 space-y-8") do
            render_emission_ledger
          end
          div(class: "space-y-8") do
            render_backing_asset_panel
            render_legal_vault
          end
        end
      end
    end

    private

    def render_hero_section
      div(class: "p-10 border border-emerald-900 bg-zinc-950 flex flex-col md:flex-row justify-between items-center relative overflow-hidden") do
         div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none") { t("contracts.show.decoration") }

         div do
           p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-2") { t("contracts.show.identity") }
           h2(class: "text-5xl font-extralight text-white tracking-tighter") { t("contracts.show.title", id: @contract.id, sector: @contract.cluster&.name&.upcase) }
           p(class: "mt-2 text-xs font-mono text-gaia-text-muted") { t("contracts.show.organization", name: @contract.organization&.name) }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t("contracts.show.status", value: @contract.status.upcase) }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t("contracts.show.period", start: @contract.start_date&.strftime("%d.%m.%Y"), end: @contract.end_date&.strftime("%d.%m.%Y")) }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t("contracts.show.total_funding", amount: @contract.total_funding) }
         end

         div(class: "mt-8 md:mt-0 text-center md:text-right") do
           p(class: "text-tiny text-gray-600 uppercase mb-1") { t("contracts.show.current_yield") }
           span(class: "text-6xl font-light text-emerald-400") { @contract.emitted_tokens.to_f.round(2) }
           span(class: "text-xl text-emerald-600 font-mono ml-2") { t("contracts.show.yield_unit") }
         end
      end
    end

    def render_backing_asset_panel
      cluster = @contract.cluster
      return unless cluster

      health = cluster.health_index || 0

      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { t("contracts.show.backing.title") }
        div(class: "space-y-4") do
          metric_row(t("contracts.show.backing.vitality"), "#{(health * 100).round}%", alert: health < 0.7)
          metric_row(t("contracts.show.backing.active_soldiers"), cluster.total_active_trees)
          metric_row(t("contracts.show.backing.threat_status"), cluster.active_threats? ? t("contracts.show.backing.danger") : t("contracts.show.backing.nominal"), alert: cluster.active_threats?)
        end
      end
    end

    def metric_row(label, value, alert: false)
      div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
        span(class: "text-tiny text-gray-600 uppercase") { label }
        span(class: tokens("font-mono text-sm", "text-red-500 animate-pulse": alert, "text-emerald-100": !alert)) { value }
      end
    end

    def render_emission_ledger
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t("contracts.show.ledger.title") }
        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
           table(role: "table", class: "w-full text-left font-mono text-tiny") do
             thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
               tr do
                 th(scope: "col", class: "p-4") { t("contracts.show.ledger.tx_hash") }
                 th(scope: "col", class: "p-4") { t("contracts.show.ledger.amount") }
                 th(scope: "col", class: "p-4 text-right") { t("contracts.show.ledger.timestamp") }
               end
             end
             tbody(class: "divide-y divide-emerald-900/30") do
                if @history.any?
                  @history.each do |tx|
                    tr(class: "hover:bg-emerald-950/10 transition-colors") do
                      td(class: "p-4 text-emerald-600") { tx.tx_hash.present? ? "#{tx.tx_hash.first(12)}…" : t("contracts.show.ledger.pending_block") }
                      td(class: "p-4 text-white") { t("contracts.show.ledger.amount_value", amount: tx.amount) }
                      td(class: "p-4 text-gray-500 text-right") { tx.created_at.strftime("%H:%M // %d.%m.%y") }
                    end
                  end
                else
                  tr do
                    td(colspan: 3, class: "p-10 text-center text-gray-700 italic") { t("contracts.show.ledger.empty") }
                  end
                end
             end
           end
        end
      end
    end

    def render_legal_vault
      div(class: "p-6 border border-emerald-900 bg-emerald-950/10") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { t("contracts.show.legal.title") }
        p(class: "text-tiny text-gray-500 font-mono break-all leading-relaxed mb-4") do
          t("contracts.show.legal.verified")
        end
        if @contract.cancellation_terms.present?
          div(class: "space-y-2 pt-3 border-t border-emerald-900/30") do
            h4(class: "text-mini uppercase tracking-widest text-emerald-800 mb-2") { t("contracts.show.legal.cancellation_title") }
            term_row(t("contracts.show.legal.early_exit_fee"), t("contracts.show.legal.early_exit_value", value: @contract.early_exit_fee_percent || 0))
            term_row(t("contracts.show.legal.burn_points"), @contract.burn_accrued_points ? t("contracts.show.legal.burn_yes") : t("contracts.show.legal.burn_no"))
            term_row(t("contracts.show.legal.min_days"), @contract.min_days_before_exit || "—")
          end
        end
      end
    end

    def term_row(label, value)
      div(class: "flex justify-between text-tiny font-mono") do
        span(class: "text-gray-600") { label }
        span(class: "text-emerald-400") { value.to_s }
      end
    end
  end
end
