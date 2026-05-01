# frozen_string_literal: true

# Standalone Phlex component rendered inside AuthLayout when an authenticated
# user has no organization assigned (for example, the system Oracle Executioner
# bot, or a brand-new account awaiting admin onboarding).
#
# Mirrors the cyber-noir aesthetic of the auth pages (Sessions::New,
# Passwords::Forgot) so the user lands on a recognizable surface instead of an
# unstyled HTML fragment. See docs/04_04_Phlex_UI_and_Tailwind.md.
module Errors
  class NoOrganization < ApplicationComponent
    def view_template
      main(class: "min-h-screen flex items-center justify-center p-4 relative overflow-hidden", role: "main") do
        div(class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]", aria_hidden: "true")

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10") do
          div(class: "p-8 border border-emerald-900 bg-black/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-6") do
            render_header
            render_message
            render_logout_link
          end
        end
      end
    end

    private

    def render_header
      div(class: "text-center space-y-3") do
        p(class: "text-mini uppercase tracking-[0.4em] text-emerald-700") { "Citadel // Access Denied" }
        h1(class: "text-2xl font-light text-emerald-100") { "No Organization Assigned" }
      end
    end

    def render_message
      div(class: "border-t border-emerald-900/50 pt-6 space-y-3 text-compact text-gray-400 leading-relaxed") do
        p { "Your account is not currently linked to any organization in the Forest Matrix." }
        p { "Contact your administrator to be assigned to a cluster, or sign in with a provisioned identity." }
      end
    end

    def render_logout_link
      div(class: "pt-4 border-t border-emerald-900/30 text-center") do
        button_to(
          api_v1_logout_path,
          method: :delete,
          class: "text-mini uppercase tracking-widest text-emerald-600 hover:text-emerald-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-colors bg-transparent border-0"
        ) { "← Sign Out" }
      end
    end
  end
end
