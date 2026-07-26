# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Standalone Phlex page rendered inside AuthLayout when an authenticated user
# has no organization assigned (наприклад, системний бот Oracle Executioner,
# або щойно створений акаунт у процесі onboarding).
#
# Стиль: domain page-component (auth-сторінка), тому використовує raw emerald
# Tailwind токени узгоджено з Sessions::New / Passwords::Forgot
# (див. docs/04_04 §3.4 — виняток для domain page-components).
module Errors
  class NoOrganization < ApplicationComponent
    def view_template
      main(
        class: "min-h-screen flex items-center justify-center p-4 relative overflow-hidden",
        role: "main"
      ) do
        div(
          class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]",
          aria_hidden: "true"
        )

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10") do
          render_header

          div(class: "p-8 border border-emerald-900 bg-black/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do
            render_message
            render_logout_link
          end
        end
      end
    end

    private

    def render_header
      div(class: "text-center mb-10 space-y-2") do
        div(class: "inline-block h-12 w-12 border border-status-danger-accent rotate-45 mb-4 relative", aria_hidden: "true") do
          div(class: "absolute inset-1 bg-status-danger-accent animate-pulse")
        end
        h1(class: "text-3xl font-extralight text-white tracking-[0.3em] uppercase") { t(".heading") }
        p(class: "text-tiny text-emerald-700 uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    def render_message
      div(class: "space-y-4 text-compact text-emerald-300/80 leading-relaxed") do
        p do
          plain t(".body_1")
        end
        p(class: "text-tiny text-emerald-700 uppercase tracking-widest") do
          t(".body_2")
        end
      end
    end

    def render_logout_link
      div(class: "pt-4 border-t border-emerald-900/30 text-center") do
        button_to(
          t(".sign_out"),
          api_v1_logout_path,
          method: :delete,
          aria: { label: "Sign out" },
          class: "text-tiny text-emerald-900 uppercase tracking-widest hover:text-emerald-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-colors bg-transparent border-0 cursor-pointer"
        )
      end
    end
  end
end
