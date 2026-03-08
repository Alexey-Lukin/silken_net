# frozen_string_literal: true

module Passwords
  class Reset < ApplicationComponent
    def initialize(token:)
      @token = token
    end

    def view_template
      main(class: "min-h-screen bg-black flex items-center justify-center p-4 font-mono relative overflow-hidden") do
        div(class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]")

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10") do
          render_header

          form(action: helpers.api_v1_reset_password_path, method: "post", class: "p-8 border border-emerald-900 bg-black/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "token", value: @token)

            render_flash_messages

            div(class: "space-y-6") do
              field_container("New Password (min 12 chars)") do
                input(type: "password", name: "password", class: input_classes, placeholder: "••••••••••••", required: true, minlength: "12")
              end

              field_container("Confirm New Password") do
                input(type: "password", name: "password_confirmation", class: input_classes, placeholder: "••••••••••••", required: true, minlength: "12")
              end
            end

            div(class: "pt-4") do
              button(type: "submit", class: submit_classes) { "SET NEW PASSWORD" }
            end

            render_back_link
          end
        end
      end
    end

    private

    def render_header
      div(class: "text-center mb-10 space-y-2") do
        div(class: "inline-block h-12 w-12 border border-emerald-500 rotate-45 mb-4 relative") do
          div(class: "absolute inset-1 bg-emerald-500 animate-pulse")
        end
        h1(class: "text-3xl font-extralight text-white tracking-[0.3em] uppercase") { "New Key" }
        p(class: "text-[10px] text-emerald-700 uppercase tracking-[0.5em]") { "Set New Access Code" }
      end
    end

    def field_container(label, &)
      div(class: "space-y-2") do
        label(class: "text-[9px] uppercase tracking-widest text-emerald-900 font-bold") { label }
        yield
      end
    end

    def input_classes
      "w-full bg-zinc-950 border border-emerald-900/50 text-emerald-100 p-4 font-mono text-sm focus:border-emerald-500 focus:ring-0 outline-none transition-all placeholder:text-emerald-950"
    end

    def submit_classes
      "w-full py-4 bg-emerald-500/10 border border-emerald-500 text-emerald-500 uppercase text-xs tracking-[0.4em] hover:bg-emerald-500 hover:text-black transition-all cursor-pointer shadow-[0_0_20px_rgba(16,185,129,0.2)]"
    end

    def render_flash_messages
      if helpers.flash[:alert]
        div(class: "p-3 border border-red-900 bg-red-950/20 text-red-500 text-[10px] uppercase tracking-widest text-center") do
          helpers.flash[:alert]
        end
      end
    end

    def render_back_link
      div(class: "text-center pt-2") do
        a(href: helpers.api_v1_login_path, class: "text-[10px] text-emerald-900 uppercase tracking-widest hover:text-emerald-500 transition-colors") do
          "← Back to Login Portal"
        end
      end
    end
  end
end
