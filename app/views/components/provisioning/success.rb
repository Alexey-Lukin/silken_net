module Provisioning
  class Success < ApplicationComponent
    def initialize(device:, aes_key:)
      @device = device
      @aes_key = aes_key
    end

    def view_template
      div(class: "max-w-2xl mx-auto p-10 border-2 border-emerald-500 bg-black animate-in zoom-in duration-700") do
        div(class: "text-center space-y-6") do
          div(class: "inline-flex items-center justify-center w-16 h-16 rounded-full border-2 border-emerald-500 text-emerald-500 text-3xl") { "✓" }

          h2(class: "text-2xl font-light text-white uppercase tracking-widest") { "Ritual Complete" }
          p(class: "text-sm text-gray-500 font-mono") { "Node has been woven into the Silken Net." }

          div(class: "mt-10 p-6 bg-zinc-950 border border-emerald-900 text-left space-y-6") do
            render_data_point("Assigned DID", @device.did)
            render_data_point("Hardware UID", @device.uid || "N/A")

            if @aes_key.present?
              render_lab_mode_key
            else
              render_hkdf_mode_notice
            end
          end

          div(class: "pt-10") do
            a(href: api_v1_cluster_path(@device.cluster), class: "text-emerald-500 underline underline-offset-8 text-xs uppercase tracking-widest") { "View Node in Matrix →" }
          end
        end
      end
    end

    private

    def render_data_point(label, value)
      div do
        p(class: "text-mini text-gray-600 uppercase tracking-tighter") { label }
        p(class: "text-emerald-100 font-mono") { value }
      end
    end

    # TRL4 lab mode: AES key is shown for manual flashing
    def render_lab_mode_key
      div(class: "pt-4 border-t border-emerald-900/30") do
        p(class: "text-mini text-red-500 uppercase tracking-widest mb-2") { "CRITICAL: AES-256 SESSION KEY" }
        div(class: "p-4 bg-black border border-red-900 text-red-400 font-mono text-sm break-all") { @aes_key }
        p(class: "mt-2 text-micro text-gray-700 uppercase italic") { "Write this to STM32 non-volatile memory now. It will never be shown again." }
      end
    end

    # Production HKDF mode: key is derived independently on firmware
    def render_hkdf_mode_notice
      div(class: "pt-4 border-t border-emerald-900/30") do
        p(class: "text-mini text-emerald-600 uppercase tracking-widest mb-2") { "HKDF MODE: ZERO-TRUST KEY DERIVATION" }
        div(class: "p-4 bg-black border border-emerald-900 text-emerald-400 font-mono text-sm") do
          plain "AES-256 key is derived independently via "
          strong { "HKDF-SHA256" }
          plain " on both backend and firmware. No key transmission required."
        end
        p(class: "mt-2 text-micro text-gray-500 uppercase italic") do
          plain "Ensure PROVISIONING_MASTER_KEY is programmed into device during Factory Provisioning."
        end
      end
    end
  end
end
