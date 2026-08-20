# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Notifications
  # [ARCH.60] Telegram Bot API — єдиний канал крім пошти, досяжний без
  # вендор-акаунта (⚖️ founder 2026-08-20: MVP-канал). Дім УСЬОГО телеграмного:
  # ім'я ENV, формат токена, предикат «чи налаштовано» і сама відправка живуть
  # поруч — інакше «чи працює канал?» і «чим він вмикається» стали б двома
  # домами, і друкарська помилка в одному не мала б симптому (той самий
  # принцип, що `DeliveryChannels::SENDER_ENV` для пошти).
  module TelegramTransport
    TOKEN_ENV = "TELEGRAM_BOT_TOKEN"

    # Форма справжнього BotFather-токена: "<bot_id>:<секрет>". Формат — не
    # косметика: деплой-файли несуть `REQUIRED_SECRET_NOT_SET` як видиме
    # «сюди підставити», і предикат «ENV непорожній» прийняв би плейсхолдер за
    # живий канал (прецедент — форматна нога `sender_configured?`).
    TOKEN_FORMAT = /\A\d+:[\w-]{30,}\z/

    API_BASE = "https://api.telegram.org"

    module_function

    # @return [Boolean] чи існує транспорт (токен заданий і має форму токена)
    def configured?(env = ENV)
      env[TOKEN_ENV].to_s.match?(TOKEN_FORMAT)
    end

    # Надсилає повідомлення через `sendMessage`. Не-2xx і мережеві збої
    # піднімаються як `Web3::HttpClient::RequestError` — викликач-воркер
    # свідомо НЕ ковтає їх, щоб Sidekiq-retry добив доставку.
    #
    # @param chat_id [String] `users.telegram_chat_id`
    # @param text [String] уже локалізований текст (локаль отримувача — клопіт
    #   викликача, дім — `Notifications::RecipientLocale`)
    def send_message(chat_id:, text:)
      Web3::HttpClient.post(
        "#{API_BASE}/bot#{ENV[TOKEN_ENV]}/sendMessage",
        body: { chat_id: chat_id, text: text },
        service_name: "Telegram"
      )
    end
  end
end
