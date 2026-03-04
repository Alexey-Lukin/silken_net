# frozen_string_literal: true

module Views
  module Components
    module Settings
      class Show < ApplicationComponent
        def initialize(organization:)
          @organization = organization
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-500") do
            header_section
            div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
              div(class: "xl:col-span-2") do
                render_settings_form
              end
              div(class: "space-y-6") do
                render_identity_vault
                render_metadata
              end
            end
          end
        end

        private

        def header_section
          div(class: "flex justify-between items-end mb-4") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "🧠 Brain Map — Organization Settings" }
              p(class: "text-xs text-gray-600 mt-1") { "Конфігурація Організації: зміна назви, білінг, крипто-адреса." }
            end
          end
        end

        def render_settings_form
          div(class: "p-6 border border-emerald-900 bg-black") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Configuration" }

            form(action: helpers.api_v1_settings_path, method: "post", class: "space-y-6") do
              input(type: "hidden", name: "_method", value: "patch")
              input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

              render_field("Organization Name", "organization[name]", @organization.name)
              render_field("Billing Email", "organization[billing_email]", @organization.billing_email, placeholder: "billing@example.org")
              render_field("Crypto Public Address", "organization[crypto_public_address]", @organization.crypto_public_address, placeholder: "0x...")

              div(class: "pt-4 border-t border-emerald-900/30") do
                button(type: "submit", class: "px-6 py-2 border border-emerald-500 text-[10px] uppercase tracking-widest text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all") { "Update Settings →" }
              end
            end
          end
        end

        def render_field(label, name, value, placeholder: nil)
          div(class: "space-y-2") do
            label(class: "text-[9px] text-gray-600 uppercase tracking-widest block") { label }
            input(
              type: "text",
              name: name,
              value: value,
              placeholder: placeholder,
              class: "w-full bg-zinc-950 border border-emerald-900/50 text-[11px] font-mono text-emerald-400 px-4 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
            )
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

        def render_metadata
          div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "System Metadata" }
            div(class: "space-y-3 font-mono text-[10px]") do
              meta_row("Organization ID", @organization.id)
              meta_row("Created", @organization.created_at.strftime("%d.%m.%Y"))
              meta_row("Last Updated", @organization.updated_at.strftime("%d.%m.%Y %H:%M"))
            end
          end
        end

        def meta_row(label, value)
          div(class: "flex justify-between items-center") do
            span(class: "text-gray-600 uppercase") { label }
            span(class: "text-emerald-400") { value.to_s }
          end
        end
      end
    end
  end
end
