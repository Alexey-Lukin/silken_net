module Views
  module Components
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
               p(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-2") { "Contract Identity" }
               h2(class: "text-5xl font-extralight text-white tracking-tighter") { "##{@contract.id} // SEC_#{@contract.cluster&.name&.upcase}" }
               p(class: "mt-4 text-xs font-mono text-emerald-900") { "Signed: #{@contract.signed_at&.strftime('%d.%m.%Y // %H:%M')}" }
             end

             div(class: "mt-8 md:mt-0 text-center md:text-right") do
               p(class: "text-[10px] text-gray-600 uppercase mb-1") { "Current Yield" }
               span(class: "text-6xl font-light text-emerald-400") { @contract.emitted_tokens.to_f.round(2) }
               span(class: "text-xl text-emerald-600 font-mono ml-2") { "SCC" }
             end
          end
        end

        def render_backing_asset_panel
          div(class: "p-6 border border-emerald-900 bg-black") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Backing Asset Health" }
            div(class: "space-y-4") do
              metric_row("Cluster Vitality", "#{@contract.cluster.health_index}%", alert: @contract.cluster.health_index < 70)
              metric_row("Active Soldiers", @contract.cluster.total_active_trees)
              metric_row("Threat Status", @contract.cluster.active_threats? ? "DANGER" : "NOMINAL", alert: @contract.cluster.active_threats?)
            end
          end
        end

        def metric_row(label, value, alert: false)
          div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
            span(class: "text-[10px] text-gray-600 uppercase") { label }
            span(class: tokens("font-mono text-sm", alert ? "text-red-500 animate-pulse" : "text-emerald-100")) { value }
          end
        end

        def render_emission_ledger
          div(class: "space-y-4") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Blockchain Emission History" }
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
               table(class: "w-full text-left font-mono text-[10px]") do
                 # ... аналогічно до Wallets Ledger ...
                 tbody(class: "divide-y divide-emerald-900/30") do
                    @history.each do |tx|
                      tr do
                        td(class: "p-4 text-emerald-600") { tx.tx_hash.first(12) + "..." }
                        td(class: "p-4 text-white") { "+ #{tx.amount} SCC" }
                        td(class: "p-4 text-gray-500 text-right") { tx.created_at.strftime("%H:%M // %d.%m.%y") }
                      end
                    end
                 end
               end
            end
          end
        end

        def render_legal_vault
          div(class: "p-6 border border-emerald-900 bg-emerald-950/10") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Smart Contract Data" }
            p(class: "text-[10px] text-gray-500 font-mono break-all leading-relaxed") do
              "Verified by Silken Net Oracle. Performance indexed to LorentzA attractor stability."
            end
          end
        end
      end
    end
  end
end
