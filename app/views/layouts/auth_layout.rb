# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Lightweight layout for standalone auth pages (login, forgot/reset password).
# These pages render outside the DashboardLayout since the user is not authenticated yet.
# Provides the minimal HTML document structure with CSS/JS includes.
class AuthLayout < ApplicationComponent
  include Phlex::Rails::Layout

  # @param title [String] page title
  # @param flash [Hash] повідомлення поточного запиту
  # @param content [Phlex::HTML] page content component
  #
  # 🔴 [SEC.25] `flash` тут несучий не менше, ніж на дашборді: він несе все, що
  # приїхало РЕДИРЕКТОМ («лист із інструкціями надіслано», «токен протермінований»,
  # rate-limit) — доти ці повідомлення були німі, хоч ключі написані й перекладені
  # в усі чотири локалі.
  #
  # ⚠️ Тут доти стояло, що auth-компоненти мають власні kwarg'и й ті просто ніхто
  # не заповнює. Станом на 2026-08-03 це неправда двічі, і різниця несуча:
  # `Passwords::Forgot` kwarg'ів не має ВЗАГАЛІ (обидва його шляхи — редиректи),
  # а `Sessions::New`/`Passwords::Reset` мають рівно один — і він НЕ дублює цей
  # канал, а робить інше: показує помилку поточного сабміту на місці, зі
  # збереженим статусом (401/429/422), біля поля, яке треба перевводити.
  def initialize(title:, flash: {}, content: nil)
    @title = title
    @flash = flash
    @content = content
  end

  def view_template
    doctype
    html(class: "h-full", lang: I18n.locale.to_s) do
      head do
        title { "Silken Net // #{@title}" }
        meta(name: "viewport", content: "width=device-width,initial-scale=1")
        link(rel: "icon", href: "/icon.png", type: "image/png")
        link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
        link(rel: "apple-touch-icon", href: "/icon.png")
        csp_meta_tag
        csrf_meta_tags
        stylesheet_link_tag "application", "tailwind", "data-turbo-track": "reload"
        javascript_importmap_tags
      end

      body(class: "h-full font-mono antialiased bg-gaia-surface-base text-gaia-primary-strong") do
        render Views::Shared::UI::FlashMessages.new(messages: @flash)
        render @content if @content
      end
    end
  end
end
