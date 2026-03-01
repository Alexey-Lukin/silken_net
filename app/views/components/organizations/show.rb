# frozen_string_literal: true

module Views
  module Components
    module Organizations
      class Show < ApplicationComponent
        def initialize(organization:, clusters:, performance:)
          @organization = organization
          @clusters = clusters
          @performance = performance
        end

        def view_template
          div(class: "space-y-10 animate-in slide-in-from-right duration-700") do
            render_header
            render_performance_hero
            
            div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
              # Основний список секторів
              div(class: "xl:col-span-2 space-y-6") do
                render_clusters_registry
              end

              # Бічна панель ідентичності
              div(class: "space-y-6") do
                render_identity_vault
                render_recent_activity_placeholder
              end
            end
          end
        end

        private

        def render_header
          div(class: "flex flex-col md:flex-row justify-between items-start md:items-center p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
            # Декоративний фон для ідентифікації
            div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-emerald-900/5 select-none") { "CLAN" }
            
            div do
              h2(class: "text-4xl font-extralight tracking-tighter text-emerald-400") { @organization.name }
              p(class: "text-[10px] font-mono text-emerald-800 uppercase mt-2 tracking-[0.3em]") do
                "Member Since: #{@organization.created_at.strftime('%d.%m.%Y')}"
              end
            end

            div(class: "mt-6 md:mt-0 flex items-center space-x-4") do
              div(class: "text-right") do
                p(class: "text-[9px] text-gray-600 uppercase tracking-widest") { "Operational Status" }
                p(class: "text-sm font-mono text-emerald-500") { "FULLY_SYNCED" }
              end
              div(class: "h-3 w-3 rounded-full bg-emerald-500 shadow-[0_0_12px_#10b981]")
            end
          end
        end

        def render_performance_hero
          div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
            stat_card("Biological Assets", @performance[:total_trees], "Soldier Trees")
            stat_card("Carbon Yield", @performance[:carbon_minted], "SCC Minted")
            stat_card("Capital Injected", @organization.total_invested, "SCC Total")
          end
        end

        def stat_card(label, value, sub)
          div(class: "p-6 border border-emerald-900 bg-zinc-950") do
            p(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { label }
            div(class: "flex items-baseline space-x-2") do
              span(class: "text-4xl font-light text-white") { value }
              span(class: "text-[10px] text-gray-600 font-mono") { sub }
            end
          end
        end

        def render_clusters_registry
          div(class: "space-y-4") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Assigned Sectors (Clusters)" }
            
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
              table(class: "w-full text-left font-mono text-[11px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Sector Name" }
                    th(class: "p-4") { "Vitality" }
                    th(class: "p-4") { "Population" }
                    th(class: "p-4 text-right") { "Matrix" }
                  end
                end
                tbody(class: "divide-y divide-emerald-900/30") do
                  @clusters.each do |cluster|
                    tr(class: "hover:bg-emerald-950/10 transition-colors group") do
                      td(class: "p-4 text-emerald-100") { cluster.name }
                      td(class: "p-4") do
                        div(class: "flex items-center space-x-2") do
                          div(class: "w-16 h-1 bg-emerald-950 rounded-full overflow-hidden") do
                            div(class: "h-full bg-emerald-500", style: "width: #{cluster.health_index}%")
                          end
                          span(class: "text-[10px] text-emerald-500") { "#{cluster.health_index}%" }
                        end
                      end
                      td(class: "p-4 text-gray-400") { "#{cluster.trees.count} Soldiers" }
                      td(class: "p-4 text-right") do
                        a(
                          href: helpers.api_v1_cluster_path(cluster),
                          class: "text-emerald-600 hover:text-white transition-all uppercase text-[9px]"
                        ) { "Open Matrix →" }
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def render_identity_vault
          div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "On-Chain Identity Vault" }
            
            div do
              p(class: "text-[9px] text-gray-600 uppercase mb-2") { "Public Crypto Address" }
              p(class: "text-[11px] font-mono text-emerald-500 break-all leading-relaxed") do
                @organization.crypto_public_address || "NOT_PROVISIONED"
              end
            end

            div(class: "pt-4 border-t border-emerald-900/30") do
              p(class: "text-[9px] text-gray-600 uppercase mb-2") { "Billing Contact" }
              p(class: "text-[11px] text-gray-400") { @organization.billing_email || "N/A" }
            end
          end
        end

        def render_recent_activity_placeholder
          div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Global Events" }
            div(class: "space-y-3") do
              [ "Contract Renewal", "Asset Expansion", "Carbon Audit" ].each do |event|
                div(class: "flex justify-between items-center") do
                  span(class: "text-[10px] text-gray-500 uppercase font-mono") { event }
                  span(class: "text-[9px] text-emerald-900") { "PENDING" }
                end
              end
            end
          end
        end
      end
    end
  end
end
