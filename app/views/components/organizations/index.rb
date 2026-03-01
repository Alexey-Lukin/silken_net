module Views
  module Components
    module Organizations
      class Index < ApplicationComponent
        def initialize(organizations:)
          @organizations = organizations
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-700") do
            header_section
            
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
              table(class: "w-full text-left font-mono text-[11px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Organization Name" }
                    th(class: "p-4") { "Sectors" }
                    th(class: "p-4") { "Investment (SCC)" }
                    th(class: "p-4") { "On-Chain Identity" }
                    th(class: "p-4 text-right") { "Audit" }
                  end
                end
                tbody(class: "divide-y divide-emerald-900/30") do
                  @organizations.each { |org| render_org_row(org) }
                end
              end
            end
          end
        end

        private

        def render_org_row(org)
          tr(class: "hover:bg-emerald-950/10 transition-colors group") do
            td(class: "p-4 text-emerald-400 font-bold") { org.name }
            td(class: "p-4 text-gray-400") { org.total_clusters }
            td(class: "p-4 text-emerald-100") { "#{org.total_invested} SCC" }
            td(class: "p-4 text-[10px] text-gray-600 font-mono") { org.crypto_public_address&.first(12) + "..." }
            td(class: "p-4 text-right") do
              a(href: helpers.api_v1_organization_path(org), class: "text-emerald-600 hover:text-white transition-all") { "VIEW_PROFILE →" }
            end
          end
        end

        def header_section
          div(class: "flex justify-between items-end") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "Global Clan Registry" }
              p(class: "text-xs text-gray-600 mt-1") { "Management of multi-tenant entities and their environmental capital." }
            end
          end
        end
      end
    end
  end
end
