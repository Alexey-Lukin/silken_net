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
         div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none") { "NaaS" }

         div do
           p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-2") { "Contract Identity" }
           h2(class: "text-5xl font-extralight text-white tracking-tighter") { "##{@contract.id} // SEC_#{@contract.cluster&.name&.upcase}" }
           p(class: "mt-2 text-xs font-mono text-gaia-text-muted") { "Organization: #{@contract.organization&.name}" }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { "Status: #{@contract.status.upcase}" }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { "Period: #{@contract.start_date&.strftime('%d.%m.%Y')} → #{@contract.end_date&.strftime('%d.%m.%Y')}" }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { "Total Funding: #{@contract.total_funding} SCC" }
         end

         div(class: "mt-8 md:mt-0 text-center md:text-right") do
           p(class: "text-tiny text-gray-600 uppercase mb-1") { "Current Yield" }
           span(class: "text-6xl font-light text-emerald-400") { @contract.emitted_tokens.to_f.round(2) }
           span(class: "text-xl text-emerald-600 font-mono ml-2") { "SCC" }
         end
      end
    end

    def render_backing_asset_panel
      cluster = @contract.cluster
      return unless cluster

      health = cluster.health_index || 0

      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { "Backing Asset Health" }
        div(class: "space-y-4") do
          metric_row("Cluster Vitality", "#{(health * 100).round}%", alert: health < 0.7)
          metric_row("Active Soldiers", cluster.total_active_trees)
          metric_row("Threat Status", cluster.active_threats? ? "DANGER" : "NOMINAL", alert: cluster.active_threats?)
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
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "Blockchain Emission History" }
        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
           table(role: "table", class: "w-full text-left font-mono text-tiny") do
             thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
               tr do
                 th(scope: "col", class: "p-4") { "TX Hash" }
                 th(scope: "col", class: "p-4") { "Amount" }
                 th(scope: "col", class: "p-4 text-right") { "Timestamp" }
               end
             end
             tbody(class: "divide-y divide-emerald-900/30") do
                if @history.any?
                  @history.each do |tx|
                    tr(class: "hover:bg-emerald-950/10 transition-colors") do
                      td(class: "p-4 text-emerald-600") { tx.tx_hash.present? ? "#{tx.tx_hash.first(12)}…" : "PENDING_BLOCK" }
                      td(class: "p-4 text-white") { "+ #{tx.amount} SCC" }
                      td(class: "p-4 text-gray-500 text-right") { tx.created_at.strftime("%H:%M // %d.%m.%y") }
                    end
                  end
                else
                  tr do
                    td(colspan: 3, class: "p-10 text-center text-gray-700 italic") { "No emissions recorded." }
                  end
                end
             end
           end
        end
      end
    end

    def render_legal_vault
      div(class: "p-6 border border-emerald-900 bg-emerald-950/10") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { "Smart Contract Data" }
        p(class: "text-tiny text-gray-500 font-mono break-all leading-relaxed mb-4") do
          "Verified by Silken Net Oracle. Performance indexed to LorentzA attractor stability."
        end
        if @contract.cancellation_terms.present?
          div(class: "space-y-2 pt-3 border-t border-emerald-900/30") do
            h4(class: "text-mini uppercase tracking-widest text-emerald-800 mb-2") { "Cancellation Terms" }
            term_row("Early Exit Fee", "#{@contract.early_exit_fee_percent || 0}%")
            term_row("Burn Accrued Points", @contract.burn_accrued_points ? "Yes" : "No")
            term_row("Min Days Before Exit", @contract.min_days_before_exit || "—")
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
