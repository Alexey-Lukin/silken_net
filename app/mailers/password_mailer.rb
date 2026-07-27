# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class PasswordMailer < ApplicationMailer
  def reset_instructions
    @user = params[:user]
    @token = @user.generate_token_for(:password_reset)
    # Термін життя посилання називається в тілі листа словами — беремо його з
    # того самого джерела, що й сам токен, інакше текст і TTL розійдуться мовчки.
    @expires_in_minutes = (User::PASSWORD_RESET_TTL / 60).to_i

    # [I18N.1] Тут локаль КОРИСТУВАЧА: адресат — конкретний User.
    in_locale_of(@user) do
      mail(
        to: @user.email_address,
        subject: default_i18n_subject
      )
    end
  end
end
