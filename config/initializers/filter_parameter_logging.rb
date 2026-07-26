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
  :phone_number, :telegram_chat_id, :push_token,
  # [SEC.18] Імена — теж PII (текли повз перший список); recovery_codes =
  # креденшели другого фактора.
  :first_name, :last_name, :recovery_codes
]
