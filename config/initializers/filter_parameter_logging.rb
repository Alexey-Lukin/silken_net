# SPDX-License-Identifier: AGPL-3.0-or-later
# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :aes_key, :wallet_private_key, :mnemonic, :binary_payload, :private_key, :secret_key,
  :signature, :payload, :ed25519_public_key,
  # PII, що текло в логи cleartext (O4/O3): контактні дані патрульних/лісників.
  # ⛔ **ДВА З ЦИХ ТРЬОХ ІМЕН НЕ МАЮТЬ КОЛОНКИ — І ЦЕ НАВМИСНО, НЕ ЗАЛИШОК.**
  # `phone_number` знято ⚖️ 2026-08-20 разом зі SMS-каналом [ARCH.78];
  # `telegram_chat_id` — ⚖️ 2026-09-06 разом із каналом [ARCH.60]; провенанс обох
  # ALTER-ів — у шапці `db/migrate/20260905133000_init_consolidated.rb`.
  # `push_token` колонку має, але з 2026-09-06 не приймається жодним екшеном
  # (поверхню знято [ARCH.60]) — тобто рухається в той самий бік.
  #
  # 🔴 **НЕ ПРИБИРАТИ «бо колонки немає».** Скраб судить ІМʼЯ ПАРАМЕТРА, не схему:
  # ім'я може приїхати з `params` будь-якого клієнта, з JSON-тіла, з повернутої
  # колонки при ре-активації каналу (push ⚖️-відкладено, не відкинуто — ARCH.108).
  # Прибирання коштує рівно нуль сьогодні й повертає PII в логи cleartext у день,
  # коли поле повернуть — тобто ціна відкладена й тиха.
  #
  # ⚠️ **Гейта на цю вісь НЕМАЄ ЗА ПОБУДОВОЮ, і це названо тут, бо більше ніде:**
  # `filter_parameter_logging_spec` («PII-table column parity [SEC.18]») перевіряє
  # лише пряму вісь — кожна PII-колонка має бути відфільтрована. Зворотну — «кожне
  # фільтроване імʼя має колонку» — він не перевіряє й перевіряти НЕ ПОВИНЕН: саме
  # вона червонила б на цих трьох рядках, тобто на коректному вжитку.
  :phone_number, :telegram_chat_id, :push_token,
  # [SEC.18] Імена — теж PII (текли повз перший список); recovery_codes =
  # креденшели другого фактора.
  :first_name, :last_name, :recovery_codes
]
