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
  # Верифікуючий дубль НЕ є `Eth::Client` під `is_a?`, тож вимір його свідомо
  # не чіпає (`MEASURABLE_CLIENTS`) — саме тому решта сюїти не потребує стабів
  # на цінові RPC. Приклади статики судять статику.
  let(:client) { instance_double(Eth::Client, :max_fee_per_gas= => nil, :max_priority_fee_per_gas= => nil) }

  # ⚠️ Для виміряної гілки потрібен СПРАВЖНІЙ клієнт — інакше приклад судив би
  # гілку, якої в проді немає. `Eth::Client.create` мережі не чіпає (перевірено:
  # перший мережевий виклик — це `chain_id`), тож це дешево й чесно.
  let(:real_client) do
    Eth::Client.create("http://127.0.0.1:8545").tap do |c|
      allow(c).to receive(:max_fee_per_gas=)
      allow(c).to receive(:max_priority_fee_per_gas=)
    end
  end

  # 🔬 ФОРМИ ВИМІРЯНІ НА ЖИВИХ НОДАХ 2026-09-05, не вигадані — і саме відсутність
  # цього виміру тримала ногу ARCH.62 закритою («формат на money-path не можна
  # вгадувати»). Прогін проти `polygon-amoy-bor-rpc.publicnode.com`: гем відповідь
  # НЕ розгортає, віддає сирий JSON-RPC конверт, число всередині — hex-QUANTITY.
  def measuring(tip_hex, base_hex)
    allow(real_client).to receive(:eth_max_priority_fee_per_gas)
      .and_return({ "jsonrpc" => "2.0", "id" => 2, "result" => tip_hex })
    allow(real_client).to receive(:eth_get_block_by_number).with("latest", false)
      .and_return({ "jsonrpc" => "2.0", "id" => 3, "result" => { "baseFeePerGas" => base_hex } })
  end

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

    it "ні ENV, ні виміру (верифікуючий дубль вимір не проходить): нічого не присвоює" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("POLYGON_MAX_FEE_GWEI", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("POLYGON_PRIORITY_FEE_GWEI", nil).and_return(nil)

      described_class.apply!(client, "ALCHEMY_POLYGON_RPC_URL")

      expect(client).not_to have_received(:max_fee_per_gas=)
    end

    # 🔴 НАЙВАЖЛИВІШИЙ ПРИКЛАД ФАЙЛУ з 2026-09-05. Обидві живі money-мережі
    # ламались на gem-дефолті 42.69 Gwei, але ПО-РІЗНОМУ, і форми інверсні:
    # Amoy — чайова 99.57 Gwei при базі 63 wei; Celo — база 200 Gwei при чайовій
    # 2.5. Тобто одностороння евристика («бери tip» ⊥ «бери base×N») промахнулась
    # би рівно на одній із двох, а спільного ЧИСЛА не існує в принципі — саме це
    # й робить вимір єдиним чесним ходом, а не просто кращим.
    it "виміряний Polygon (чайова домінує): cap = base×2 + tip" do
      measuring("0x172ed80aa1", "0x3f") # 99.570158241 Gwei · 63 wei — живі числа Amoy

      described_class.apply!(real_client, "ALCHEMY_POLYGON_RPC_URL")

      aggregate_failures do
        expect(real_client).to have_received(:max_priority_fee_per_gas=).with(99_570_158_241)
        expect(real_client).to have_received(:max_fee_per_gas=).with((63 * 2) + 99_570_158_241)
      end
    end

    it "виміряний Celo (база домінує): та сама формула, інша форма мережі" do
      measuring("0x9502f900", "0x2e90edd000") # 2.5 Gwei · 200 Gwei — живі числа forno

      described_class.apply!(real_client, "CELO_RPC_URL")

      expect(real_client).to have_received(:max_fee_per_gas=).with((200 * (10**9) * 2) + (2_500_000_000))
    end

    it "ENV-пін БʼЄ вимір: оператор, що зафіксував cap, зробив це свідомо" do
      measuring("0x172ed80aa1", "0x3f")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("POLYGON_MAX_FEE_GWEI", nil).and_return("777")
      allow(ENV).to receive(:fetch).with("POLYGON_PRIORITY_FEE_GWEI", nil).and_return("5")

      described_class.apply!(real_client, "ALCHEMY_POLYGON_RPC_URL")

      aggregate_failures do
        expect(real_client).to have_received(:max_fee_per_gas=).with(777 * (10**9))
        expect(real_client).not_to have_received(:max_fee_per_gas=).with(99_570_158_367)
      end
    end

    # ⛔ Нуль тут — НЕ «дешева мережа», а НЕВИМІРЯНО. `to_i(16)` на `nil` мовчки
    # дав би 0 і поставив cap=0, тобто зробив би tx невключабельним НАЗАВЖДИ під
    # виглядом успішного виміру — гірше за пропущений вимір. Той самий клас, що
    # розводять три balance-гарди money-path (нуль-як-початок ⊥ нуль-як-наслідок).
    it "порожня або невалідна відповідь ноди = НЕ нуль, а падіння на статику" do
      # ⚠️ ОБИДВА читання стабляться навмисно, і це виміряна правка: перша
      # редакція стабила лише перше, тож другий виклик валив `MockExpectationError`
      # і приклад проходив ЧЕРЕЗ `rescue`, ніколи не досягаючи перевірки на `nil`.
      # Тобто приклад був зелений, доводячи ІНШУ гілку, ніж стверджує його назва
      # (спіймано гілковим покриттям, не очима).
      measuring("0x172ed80aa1", "0x3f")
      allow(real_client).to receive(:eth_max_priority_fee_per_gas).and_return({ "result" => nil })

      described_class.apply!(real_client, "ALCHEMY_POLYGON_RPC_URL")

      expect(real_client).not_to have_received(:max_fee_per_gas=)
    end

    # ⛔ Нода може віддати не-Hash (проксі-помилка, HTML-сторінка 502, `nil`).
    # `envelope[key]` на такому впав би `NoMethodError` — тобто вимір, що мав
    # деградувати тихо, шумів би на грошовому шляху при живій статиці поруч.
    it "не-Hash у відповіді ноди не ламає читання — просто немає виміру" do
      allow(real_client).to receive(:eth_max_priority_fee_per_gas).and_return("&lt;html&gt;502&lt;/html&gt;")
      allow(real_client).to receive(:eth_get_block_by_number).with("latest", false).and_return(nil)

      described_class.apply!(real_client, "ALCHEMY_POLYGON_RPC_URL")

      expect(real_client).not_to have_received(:max_fee_per_gas=)
    end

    # Вимір робиться на НАРОДЖЕННІ клієнта, тож виняток тут завалив би не одну
    # транзакцію, а створення клієнта — тобто увесь money-path через мертву ноду.
    it "мертва нода не ламає народження клієнта — веде на статику" do
      allow(real_client).to receive(:eth_max_priority_fee_per_gas).and_raise(Net::ReadTimeout)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("POLYGON_MAX_FEE_GWEI", nil).and_return("500")
      allow(ENV).to receive(:fetch).with("POLYGON_PRIORITY_FEE_GWEI", nil).and_return("40")

      expect { described_class.apply!(real_client, "ALCHEMY_POLYGON_RPC_URL") }.not_to raise_error
      expect(real_client).to have_received(:max_fee_per_gas=).with(500 * (10**9))
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
