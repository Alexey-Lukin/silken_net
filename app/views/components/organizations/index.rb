# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Organizations
  class Index < ApplicationComponent
    def initialize(organizations:, pagy:)
      @organizations = organizations
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        header_section

        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".columns.name") }
                th(scope: "col", class: "p-4") { t(".columns.sectors") }
                th(scope: "col", class: "p-4") { t(".columns.investment") }
                th(scope: "col", class: "p-4") { t(".columns.identity") }
                th(scope: "col", class: "p-4 text-right") { t(".columns.audit") }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              @organizations.each { |org| render_org_row(org) }
            end
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { api_v1_organizations_path(page: page) }
        )
      end
    end

    private

    def render_org_row(org)
      tr(class: "hover:bg-emerald-950/10 transition-colors group") do
        td(class: "p-4 text-emerald-400 font-bold") { org.name }
        td(class: "p-4 text-gray-400") { org.total_clusters }
        td(class: "p-4 text-emerald-100") { t(".investment_value", amount: org.total_contracted) }
        td(class: "p-4 text-tiny text-gray-600 font-mono") do
          render Views::Shared::Web3::Address.new(address: org.crypto_public_address)
        end
        td(class: "p-4 text-right") do
          a(href: api_v1_organization_path(org), class: "text-emerald-600 hover:text-white transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500", aria_label: t(".view_aria", name: org.name)) { t(".view_profile") }
        end
      end
    end

    def header_section
      div(class: "flex justify-between items-end") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".title") }
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
        end
      end
    end
  end
end
