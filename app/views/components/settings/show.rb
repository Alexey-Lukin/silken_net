# frozen_string_literal: true

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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "🧠 Brain Map — Organization Settings" }
          p(class: "text-xs text-gray-600 mt-1") { "Конфігурація Організації: назва, білінг, крипто-адреса, пороги тривоги та AI-чутливість." }
        end
      end
    end

    def render_settings_form
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { "Configuration" }

        form(action: api_v1_settings_path, method: "post", enctype: "multipart/form-data", class: "space-y-6") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          render_field("Organization Name", "organization[name]", @organization.name)
          render_field("Billing Email", "organization[billing_email]", @organization.billing_email, placeholder: "billing@example.org")
          render_field("Crypto Public Address", "organization[crypto_public_address]", @organization.crypto_public_address, placeholder: "0x...")
          render_field("Alert Threshold (Critical Z)", "organization[alert_threshold_critical_z]", @organization.alert_threshold_critical_z, placeholder: "2.5")
          render_field("AI Sensitivity (0.0 — 1.0)", "organization[ai_sensitivity]", @organization.ai_sensitivity, placeholder: "0.7")
          render_logo_field

          div(class: "pt-4 border-t border-emerald-900/30") do
            button(type: "submit", class: "px-6 py-2 border border-emerald-500 text-tiny uppercase tracking-widest text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all") { "Update Settings →" }
          end
        end
      end
    end

    def render_field(label, name, value, placeholder: nil)
      div(class: "space-y-2") do
        label(class: "text-mini text-gray-600 uppercase tracking-widest block") { label }
        input(
          type: "text",
          name: name,
          value: value,
          placeholder: placeholder,
          class: "w-full bg-zinc-950 border border-emerald-900/50 text-compact font-mono text-emerald-400 px-4 py-3 focus-visible:border-emerald-500 focus-visible:outline-none transition-colors"
        )
      end
    end

    def render_logo_field
      div(class: "space-y-2") do
        label(class: "text-mini text-gray-600 uppercase tracking-widest block") { "Organization Logo" }
        if @organization.logo.attached?
          div(class: "flex items-center gap-4 mb-2") do
            span(class: "text-tiny text-emerald-500 font-mono") { "Current: #{@organization.logo.filename}" }
          end
        end
        input(
          type: "file",
          name: "organization[logo]",
          accept: "image/png,image/jpeg,image/svg+xml",
          class: "w-full bg-zinc-950 border border-emerald-900/50 text-compact font-mono text-emerald-400 px-4 py-3 file:mr-4 file:border-0 file:bg-emerald-900/30 file:text-emerald-400 file:text-tiny file:px-4 file:py-2"
        )
      end
    end

    def render_identity_vault
      div(class: "p-6 border border-emerald-900 bg-black space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "On-Chain Identity Vault" }

        div do
          p(class: "text-mini text-gray-600 uppercase mb-2") { "Public Crypto Address" }
          render Views::Shared::Web3::Address.new(address: @organization.crypto_public_address, truncate: 42)
        end

        div(class: "pt-4 border-t border-emerald-900/30") do
          p(class: "text-mini text-gray-600 uppercase mb-2") { "Billing Contact" }
          p(class: "text-compact text-gray-400") { @organization.billing_email || "N/A" }
        end
      end
    end

    def render_metadata
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { "System Metadata" }
        div(class: "space-y-3 font-mono text-tiny") do
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
