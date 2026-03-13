module Sessions
  class New < ApplicationComponent
    # @param flash_alert [String, nil] alert message to display
    # @param flash_notice [String, nil] notice message to display
    def initialize(flash_alert: nil, flash_notice: nil)
      @flash_alert = flash_alert
      @flash_notice = flash_notice
    end

    def view_template
      # Використовуємо окремий мінімалістичний лейаут для входу
      main(class: "min-h-screen bg-black flex items-center justify-center p-4 font-mono relative overflow-hidden") do
        # Фоновий ефект Матриці/Міцелію
        div(class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]")

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10") do
          render_portal_header

          form_with(url: helpers.api_v1_login_path, method: :post, class: "p-8 border border-emerald-900 bg-black/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do |f|
            render_flash_messages

            div(class: "space-y-6") do
              field_container("Identity (Email)") do
                f.email_field :email, class: input_classes, placeholder: "architect@silken.net", required: true
              end

              field_container("Access Code (Password)") do
                f.password_field :password, class: input_classes, placeholder: "••••••••", required: true
              end
            end

            div(class: "pt-4") do
              f.submit "AUTHENTICATE", class: "w-full py-4 bg-emerald-500/10 border border-emerald-500 text-emerald-500 uppercase text-xs tracking-[0.4em] hover:bg-emerald-500 hover:text-black transition-all cursor-pointer shadow-[0_0_20px_rgba(16,185,129,0.2)]"
            end

            render_forgot_password_link
            render_social_providers
            render_footer_seal
          end
        end
      end
    end

    private

    def render_portal_header
      div(class: "text-center mb-10 space-y-2") do
        div(class: "inline-block h-12 w-12 border border-emerald-500 rotate-45 mb-4 relative") do
          div(class: "absolute inset-1 bg-emerald-500 animate-pulse")
        end
        h1(class: "text-3xl font-extralight text-white tracking-[0.3em] uppercase") { "Citadel" }
        p(class: "text-[10px] text-emerald-700 uppercase tracking-[0.5em]") { "Establishing Neural Link" }
      end
    end

    def field_container(label, &block)
      div(class: "space-y-2") do
        label(class: "text-[9px] uppercase tracking-widest text-emerald-900 font-bold") { label }
        yield
      end
    end

    def input_classes
      "w-full bg-zinc-950 border border-emerald-900/50 text-emerald-100 p-4 font-mono text-sm focus:border-emerald-500 focus:ring-0 outline-none transition-all placeholder:text-emerald-950"
    end

    def render_flash_messages
      if @flash_alert
        div(class: "p-3 border border-red-900 bg-red-950/20 text-red-500 text-[10px] uppercase tracking-widest text-center") do
          @flash_alert
        end
      end
      if @flash_notice
        div(class: "p-3 border border-emerald-900 bg-emerald-950/20 text-emerald-500 text-[10px] uppercase tracking-widest text-center") do
          @flash_notice
        end
      end
    end

    def render_forgot_password_link
      div(class: "text-right") do
        a(href: helpers.api_v1_forgot_password_path, class: "text-[10px] text-emerald-900 uppercase tracking-widest hover:text-emerald-500 transition-colors") do
          "Forgot Access Code?"
        end
      end
    end

    def render_social_providers
      div(class: "space-y-4 pt-4 border-t border-emerald-900/30") do
        p(class: "text-[9px] uppercase tracking-widest text-emerald-900 text-center") { "Or authenticate via provider" }

        div(class: "grid grid-cols-2 gap-3") do
          provider_button("google_oauth2", "Google", "🔵")
          provider_button("facebook", "Facebook", "🟦")
          provider_button("linkedin", "LinkedIn", "🔷")
          provider_button("twitter", "Twitter", "🐦")
        end
      end
    end

    def provider_button(provider, label, icon)
      a(
        href: "/auth/#{provider}",
        class: "flex items-center justify-center space-x-2 py-3 border border-emerald-900/50 text-emerald-700 text-[10px] uppercase tracking-widest hover:border-emerald-500 hover:text-emerald-400 hover:bg-emerald-950/10 transition-all"
      ) do
        span { icon }
        span { label }
      end
    end

    def render_footer_seal
      div(class: "text-center") do
        p(class: "text-[8px] text-emerald-900 uppercase tracking-widest") { "System Integrity Verified // AES-256 Enabled" }
      end
    end
  end
end
