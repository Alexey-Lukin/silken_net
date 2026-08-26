# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "eth"

RSpec.describe Web3::OracleSigner do
  # [SEC.17] Пін таблиці role → ENV. Таблиця дублюється тут НАВМИСНО: гейт, що читав би
  # мапу з самого коду, стверджував би ту саму помилку, що й код. Дублікат ловить і
  # copy-paste (дві ролі на одному ENV → E.2 mint⊥burn тихо колапсує в один ключ), і
  # переїзд ролі на чужу змінну.
  def self.role_env_table
    {
      minter:   "ORACLE_MINTER_PRIVATE_KEY",
      slasher:  "ORACLE_SLASHER_PRIVATE_KEY",
      celo:     "ORACLE_CELO_PRIVATE_KEY",
      puro:     "ORACLE_PURO_PRIVATE_KEY",
      klima:    "ORACLE_KLIMA_PRIVATE_KEY",
      etherisc: "ORACLE_ETHERISC_PRIVATE_KEY",
      anchor:   "ETHEREUM_ANCHOR_PRIVATE_KEY"
    }.freeze
  end

  let(:key_double) { instance_double(Eth::Key) }
  let(:private_key) { "0x#{'a' * 64}" }

  before do
    allow(Eth::Key).to receive(:new).and_return(key_double)
    allow(ENV).to receive(:fetch).and_call_original
  end

  describe ".for" do
    role_env_table.each do |role, env_name|
      it "derives :#{role} from #{env_name}" do
        allow(ENV).to receive(:fetch).with(env_name).and_return(private_key)

        signer = described_class.for(role)

        aggregate_failures do
          expect(ENV).to have_received(:fetch).with(env_name)
          expect(signer).to be_a(Web3::LocalEnvSigner)
        end
      end
    end

    it "spends the seven roles on seven DISTINCT ENV vars (a copy-paste would collapse E.2 mint⊥burn)" do
      table = self.class.role_env_table
      fetched = []
      allow(ENV).to receive(:fetch) { |name| fetched << name; private_key }

      table.each_key { |role| described_class.for(role) }

      expect(fetched).to match_array(table.values)
    end

    it "raises ArgumentError on an unknown role (the case's else-branch)" do
      expect { described_class.for(:treasury) }
        .to raise_error(ArgumentError, /Невідома signer-роль.*treasury/)
    end

    # INF.12 fail-loud: ENV.fetch without a default. The key must be read BEFORE the key
    # object is built — burning_service_spec pins exactly that ordering downstream
    # («does NOT fall back to the retired ORACLE_PRIVATE_KEY»).
    it "lets a missing ENV var raise KeyError before any key is derived" do
      allow(ENV).to receive(:fetch).with("ORACLE_MINTER_PRIVATE_KEY")
        .and_raise(KeyError, 'key not found: "ORACLE_MINTER_PRIVATE_KEY"')

      expect { described_class.for(:minter) }.to raise_error(KeyError, /ORACLE_MINTER_PRIVATE_KEY/)
      expect(Eth::Key).not_to have_received(:new)
    end
  end
end
