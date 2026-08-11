# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Спільна валідація Ethereum/Polygon адрес (Organization, Wallet, BlockchainTransaction).
# Два шари: форма (`0x` + 40 hex) + EIP-55 контрольна сума [ARCH.56].
#
# Правило суми — сам EIP-55, рахує гем `eth`: адреса в ОДНОМУ регістрі (все-нижній або
# все-верхній) суми не несе, тож приймається як є; mixed-case суму НЕСЕ, тож вона мусить
# збігтися. Саме цим ловиться друкарська помилка у fund-destination адресі, яку shape-regex
# пропускав: 40 hex лишаються 40 hex, а кошти пішли б у нікуди.
module EthAddressValidatable
  extend ActiveSupport::Concern

  ETH_ADDRESS_FORMAT = /\A0x[a-fA-F0-9]{40}\z/

  EIP55_MESSAGE = "має невалідну EIP-55 контрольну суму (звір регістр літер)"

  # EIP-55 ПОВЕРХ форми, не замість неї: `Eth::Address` толерує адресу без `0x`-префікса
  # (сам його дописує), а наш regex — ні, тож shape лишається за regex'ом. Дім правила —
  # тут, щоб boot-guard (`Security::Web3NetworkGuard`) звіряв env-адреси тим самим кодом.
  def self.eip55_valid?(address)
    Eth::Address.new(address.to_s).valid?
  rescue Eth::Address::CheckSumError
    false
  end

  class_methods do
    # Додає валідацію формату Ethereum-адреси до вказаного поля.
    #
    #   validates_eth_address :crypto_public_address, presence: true
    #   validates_eth_address :to_address, allow_blank: true
    def validates_eth_address(attribute, presence: false, allow_blank: false, **options)
      validation_opts = {
        format: {
          with: ETH_ADDRESS_FORMAT,
          # [I18N.4] Глобальний скоуп (`errors.messages.*`), а не модельний: концерн
          # вживають ТРИ моделі, тож ключ мусить бути один на всіх.
          message: :invalid_eth_address
        }
      }
      validation_opts[:presence] = true if presence
      validation_opts[:allow_blank] = true if allow_blank
      validation_opts.merge!(options)

      validates attribute, **validation_opts

      # Окремим `validate`, а не другим `format:` — інакше зламана форма тягла б ДВІ
      # помилки про той самий рядок (одна причина = одне повідомлення).
      validate do
        value = read_attribute_for_validation(attribute)
        next if value.blank? || !value.match?(ETH_ADDRESS_FORMAT)

        errors.add(attribute, EIP55_MESSAGE) unless EthAddressValidatable.eip55_valid?(value)
      end
    end
  end
end
