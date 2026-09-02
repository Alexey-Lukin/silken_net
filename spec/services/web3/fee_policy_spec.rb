# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [ARCH.62] Fee-політика на КОЖНОМУ новонародженому EVM-клієнті.
#
# Що тут стережеться і чому саме це. `eth 0.5.17` ставить fee у власному
# конструкторі (42.69 / 1.01 Gwei — константи, які гем сам позначає `# Do not
# use.`) і ціни з ноди не питає ніколи. За EIP-1559 занизький `maxFee` не
# економить — він робить tx НЕВКЛЮЧАБЕЛЬНИМ, а далі детермінований ланцюг:
# вічний `:sent` → sweeper лише re-poll'ить → `MintingRollbackService` →
# `manual_review`. Тобто дефект коштує заблокованих коштів, а не газу.
RSpec.describe Web3::FeePolicy do
  let(:client) { instance_double(Eth::Client, :max_fee_per_gas= => nil, :max_priority_fee_per_gas= => nil) }

  describe ".network_for" do
    it "впізнає мережу з імені ENV-ключа" do
      aggregate_failures do
        expect(described_class.network_for("ALCHEMY_POLYGON_RPC_URL")).to eq(:polygon)
        expect(described_class.network_for("POLYGON_RPC_URL_FALLBACK_1")).to eq(:polygon)
        expect(described_class.network_for("CELO_RPC_URL")).to eq(:celo)
        expect(described_class.network_for("CELO_RPC_URL_FALLBACK_1")).to eq(:celo)
        expect(described_class.network_for("ALCHEMY_ETHEREUM_RPC_URL")).to eq(:ethereum)
      end
    end

    it "віддає nil на ключ без імені мережі — тобто політики він НЕ дістане" do
      expect(described_class.network_for("SOME_OTHER_RPC_URL")).to be_nil
    end
  end

  describe ".apply!" do
    it "ставить успадковані L1-числа для Ethereum (поведінка якоря незмінна)" do
      described_class.apply!(client, "ALCHEMY_ETHEREUM_RPC_URL")

      aggregate_failures do
        expect(client).to have_received(:max_fee_per_gas=).with(100 * (10**9))
        expect(client).to have_received(:max_priority_fee_per_gas=).with(2 * (10**9))
      end
    end

    it "ставить задані ENV-числа для Polygon" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("POLYGON_MAX_FEE_GWEI", nil).and_return("500")
      allow(ENV).to receive(:fetch).with("POLYGON_PRIORITY_FEE_GWEI", nil).and_return("40")

      described_class.apply!(client, "ALCHEMY_POLYGON_RPC_URL")

      aggregate_failures do
        expect(client).to have_received(:max_fee_per_gas=).with(500 * (10**9))
        expect(client).to have_received(:max_priority_fee_per_gas=).with(40 * (10**9))
      end
    end

    # 🔴 Найдорожчий приклад файлу. Заданий cap БЕЗ priority виглядає як
    # «половина політики», а насправді гірший за її відсутність: на дроті
    # лишився б gem-дефолтний tip 1.01 Gwei, тобто tx так само невключабельний —
    # але вже під виглядом полагодженого.
    it "НЕ застосовує половину політики: cap без priority = жодного присвоєння" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("POLYGON_MAX_FEE_GWEI", nil).and_return("500")
      allow(ENV).to receive(:fetch).with("POLYGON_PRIORITY_FEE_GWEI", nil).and_return(nil)

      described_class.apply!(client, "ALCHEMY_POLYGON_RPC_URL")

      expect(client).not_to have_received(:max_fee_per_gas=)
    end

    it "мережа без політики: нічого не присвоює й не вигадує числа" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("POLYGON_MAX_FEE_GWEI", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("POLYGON_PRIORITY_FEE_GWEI", nil).and_return(nil)

      described_class.apply!(client, "ALCHEMY_POLYGON_RPC_URL")

      expect(client).not_to have_received(:max_fee_per_gas=)
    end

    it "невпізнаний ключ не чіпає клієнта" do
      described_class.apply!(client, "SOME_OTHER_RPC_URL")

      expect(client).not_to have_received(:max_fee_per_gas=)
    end
  end

  # ⚠️ Ліхтар на ПЕРИМЕТР, не на логіку: ключ money-шляху, з якого мережа не
  # впізнається, лишився б на gem-дефолтах МОВЧКИ — рівно той режим, який цей
  # пункт і закриває. Тож перелік ключів береться з дерева, а не з голови.
  describe "периметр" do
    it "кожен RPC-ключ, яким дерево створює клієнт, впізнається політикою" do
      # ⚠️ Збирач НЕ прив'язаний до `client_for(` у тому ж рядку, і це виміряна
      # правка: у `Celo::CommunityRewardService` виклик багаторядковий, тож
      # per-line греп бачив 2 ключі з наявних п'яти — ліхтар був ЗЕЛЕНИЙ на
      # вужчій множині, ніж стверджує. Беремо надмножину: кожен `*_RPC_URL*`
      # літерал дерева. Ширше за потрібне — але помилка тут коштує тиші.
      keys = Dir.chdir(Rails.root) do
        Dir["{app,lib}/**/*.rb"].flat_map { |f| File.read(f).scan(/"([A-Z0-9_]*RPC_URL[A-Z0-9_]*)"/) }
                                .flatten.uniq.sort
      end

      expect(keys.size).to be >= 4, "ліхтар зібрав лише #{keys.size} ключів (#{keys.join(', ')}) — " \
                                    "збирач звузився й пін став вакуумним"

      # ⛔ Не-EVM ключі виключено ОГОЛОШЕНО, а не звуженням збирача. Solana не має
      # ні EIP-1559, ні `Eth::Client`: `SOLANA_RPC_URL` живе в конфізі
      # `Treasury::MonitorService`, але споживає його окрема гілка
      # `fetch_solana_balance` (сирий JSON-RPC), а не `RpcConnectionPool`.
      # Виняток тут, а не в `FeePolicy`, бо це властивість ПЕРИМЕТРА, не політики.
      non_evm = keys.grep(/\ASOLANA_/)
      unmapped = (keys - non_evm).reject { |k| described_class.network_for(k) }
      expect(unmapped).to be_empty,
                          "RPC-ключі без мережі в FeePolicy: #{unmapped.join(', ')}. " \
                          "Клієнт із такого ключа народиться з gem-дефолтами 42.69/1.01 Gwei " \
                          "і його tx не включиться [ARCH.62]"
    end
  end
end
