# frozen_string_literal: true

# Спільна валідація Ethereum/Polygon адрес (Organization, Wallet, BlockchainTransaction).
# Формат: 0x + 40 hex символів (EIP-55 mixed-case safe).
module EthAddressValidatable
  extend ActiveSupport::Concern

  ETH_ADDRESS_FORMAT = /\A0x[a-fA-F0-9]{40}\z/

  class_methods do
    # Додає валідацію формату Ethereum-адреси до вказаного поля.
    #
    #   validates_eth_address :crypto_public_address, presence: true
    #   validates_eth_address :to_address, allow_blank: true
    def validates_eth_address(attribute, presence: false, allow_blank: false, **options)
      validation_opts = {
        format: {
          with: ETH_ADDRESS_FORMAT,
          message: "має бути валідною 0x адресою"
        }
      }
      validation_opts[:presence] = true if presence
      validation_opts[:allow_blank] = true if allow_blank
      validation_opts.merge!(options)

      validates attribute, **validation_opts
    end
  end
end
