# frozen_string_literal: true

class PasswordMailer < ApplicationMailer
  def reset_instructions
    @user = params[:user]
    @token = @user.generate_token_for(:password_reset)

    mail(
      to: @user.email_address,
      subject: "🔐 [Silken Net] Скидання пароля"
    )
  end
end
