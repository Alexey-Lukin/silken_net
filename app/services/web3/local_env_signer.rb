# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

module Web3
  # =========================================================================
  # 🗝️ LOCAL ENV SIGNER (SEC.17 default backend)
  # =========================================================================
  # `KeySigner` over a local `Eth::Key` derived from deploy-ENV — тобто рівно
  # те, що money-сервіси робили інлайном. Жодної зміни поведінки: `sender_key:`
  # у `client.transact` лишається ТИМ САМИМ `Eth::Key`-обʼєктом, решта kwargs
  # проходить наскрізь недоторканою. The surface (`address`/`transact`/
  # `static_call`) and its load-bearing comments live in `KeySigner`; this
  # class owns only WHERE the key comes from.
  # =========================================================================
  class LocalEnvSigner < KeySigner
    # @param private_key [String] hex-приватник із deploy-ENV
    def initialize(private_key)
      # ⛔ Не прибирати: `Eth::Key.new(priv: nil)` НЕ падає — він тихо генерує
      # ВИПАДКОВУ пару ключів. Тобто порожній/забутий ENV дав би валідного
      # підписанта з чужою адресою: mint пішов би з нуль-балансного гаманця, а
      # lock-key `lock:web3:oracle:<addr>` переїхав би на кожному рестарті.
      raise ArgumentError, "private_key порожній — Eth::Key згенерував би ВИПАДКОВУ пару" if private_key.blank?

      super(Eth::Key.new(priv: private_key))
    end
  end
end
