# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "eth"

# 🔬 MUTATION-VERIFIED [ARCH.114, 2026-08-29] — evidence grade, not an assertion. The
# network-level cascade (`NETWORK_FALLBACK_ENV_KEYS`) was proved by RESTORING the defect:
# with the registry removed, the cache key falls back to the bare env-key name, a site that
# never declared a cascade poisons the per-thread entry, and the examples below go red by
# name. Re-earn this line if either half is retargeted — a claim of proof scoped to a
# subject stops being true when the subject moves.
RSpec.describe Web3::RpcConnectionPool do
  after do
    described_class.reset!
  end

  # ⚠️ [ARCH.62] Частковий мок на ГЛОБАЛЬНОМУ `ENV.fetch` без цього рядка робить
  # спеку крихкою за побудовою: будь-який інший `ENV.fetch` у тому ж стеку падає
  # як «unexpected arguments», хоч до предмета спеки стосунку не має. Спіймано
  # тим, що `Web3::FeePolicy` (накладається на народженні клієнта) читає
  # `<CHAIN>_*_FEE_GWEI` — і чотири приклади цього файлу зачервоніли на коді,
  # який вони не судять. `and_call_original` лишає решту ENV собою.
  # 🔴 [ARCH.114] Другий `before` тут не косметика: приклади мокають `ENV.fetch`
  # (primary URL), а fallback-ключі читаються через `ENV[…]` — тобто йшли в РЕАЛЬНЕ
  # оточення. Локальний `.env` розробника несе `INFURA_POLYGON_RPC_URL` (плейсхолдер
  # `YOUR_KEY`), тож після заведення реєстру мереж ці приклади почали будувати
  # `ResilientClient` замість замоканого одиничного — судили НЕ те, про що написані,
  # і результат залежав від того, чий `.env` лежить на машині. Дефолт — порожній
  # fallback; приклади, що каскад ПЕРЕВІРЯЮТЬ, вмикають його явно у власному `before`.
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).and_call_original
    described_class::NETWORK_FALLBACK_ENV_KEYS.values.flatten.uniq.each do |key|
      allow(ENV).to receive(:[]).with(key).and_return(nil)
    end
  end

  # Клієнти, повернуті моками, мусять приймати fee-сеттери: політика ARCH.62
  # накладається на КОЖНОГО новонародженого клієнта пулу.
  def stub_eth_client
    instance_double(Eth::Client, :max_fee_per_gas= => nil, :max_priority_fee_per_gas= => nil)
  end

  describe ".client_for" do
    it "returns an Eth::Client instance" do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      allow(Eth::Client).to receive(:create).and_return(stub_eth_client)

      client = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      expect(client).to be_present
    end

    it "caches the client per thread (same object returned)" do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      client_double = instance_double(Eth::Client)
      allow(Eth::Client).to receive(:create).and_return(client_double)

      client1 = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      client2 = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")

      expect(client1).to equal(client2)
      expect(Eth::Client).to have_received(:create).once
    end

    it "creates separate clients for different RPC URLs" do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      allow(ENV).to receive(:fetch).with("CELO_RPC_URL").and_return("https://celo-rpc.example.com")

      polygon_client = instance_double(Eth::Client, "polygon")
      celo_client = instance_double(Eth::Client, "celo")

      allow(Eth::Client).to receive(:create).with("https://polygon-rpc.example.com").and_return(polygon_client)
      allow(Eth::Client).to receive(:create).with("https://celo-rpc.example.com").and_return(celo_client)

      result_polygon = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      result_celo = described_class.client_for("CELO_RPC_URL")

      expect(result_polygon).not_to equal(result_celo)
    end

    it "uses fallback URL when ENV variable is not set" do
      fallback_url = "https://testnet.example.com"
      allow(ENV).to receive(:fetch).with("MISSING_RPC_URL", fallback_url).and_return(fallback_url)
      client_double = instance_double(Eth::Client)
      allow(Eth::Client).to receive(:create).with(fallback_url).and_return(client_double)

      client = described_class.client_for("MISSING_RPC_URL", fallback: fallback_url)
      expect(client).to equal(client_double)
    end

    it "raises KeyError when ENV variable is not set and no fallback provided" do
      allow(ENV).to receive(:fetch).with("TOTALLY_MISSING_URL").and_raise(KeyError.new("key not found"))

      expect {
        described_class.client_for("TOTALLY_MISSING_URL")
      }.to raise_error(KeyError)
    end

    context "with fallback_env_keys cascade" do
      it "creates a ResilientClient when multiple URLs are available" do
        allow(ENV).to receive(:fetch).with("PRIMARY_RPC_URL").and_return("https://primary.example.com")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SECONDARY_RPC_URL").and_return("https://secondary.example.com")

        client = described_class.client_for("PRIMARY_RPC_URL", fallback_env_keys: [ "SECONDARY_RPC_URL" ])

        expect(client).to be_a(Web3::ResilientClient)
      end

      # 🔴 Регресія 2026-09-01: `reject!(&:empty?)` викидає порожній primary з
      # `all_urls`, розмір падає до 1 — і гілка брала САМЕ `primary_url`, тобто
      # порожній рядок, при живому фолбеку поруч. Каскад ARCH.114 не переживав
      # рівно того випадку, заради якого існує. ⚠️ Це не кутовий випадок: Polygon
      # має в реєстрі рівно ОДИН фолбек, тож size==1 і є його штатною формою.
      # 🔒 Стеля прикладу: він пінить, що клієнт СТВОРЮЄТЬСЯ з вцілілого URL, і
      # нічого не каже про те, чи той URL відповідає — це інша вісь (ResilientClient).
      it "uses the surviving fallback when the primary is BLANK (not the empty primary)" do
        allow(ENV).to receive(:fetch).with("PRIMARY_RPC_URL").and_return("")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SECONDARY_RPC_URL").and_return("https://secondary.example.com")

        client = described_class.client_for("PRIMARY_RPC_URL", fallback_env_keys: [ "SECONDARY_RPC_URL" ])

        expect(client).to be_a(Eth::Client)
        expect(client.host).to eq("secondary.example.com")
      end

      it "still raises loudly when the primary is blank and NO fallback survives" do
        allow(ENV).to receive(:fetch).with("PRIMARY_RPC_URL").and_return("")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SECONDARY_RPC_URL").and_return(nil)

        expect {
          described_class.client_for("PRIMARY_RPC_URL", fallback_env_keys: [ "SECONDARY_RPC_URL" ])
        }.to raise_error(ArgumentError, /Unable to detect client type/)
      end

      it "falls back to simple Eth::Client when fallback env keys are not set" do
        allow(ENV).to receive(:fetch).with("PRIMARY_RPC_URL").and_return("https://primary.example.com")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("MISSING_SECONDARY_URL").and_return(nil)

        client_double = instance_double(Eth::Client)
        allow(Eth::Client).to receive(:create).with("https://primary.example.com").and_return(client_double)

        client = described_class.client_for("PRIMARY_RPC_URL", fallback_env_keys: [ "MISSING_SECONDARY_URL" ])

        expect(client).to equal(client_double)
      end

      it "skips empty string fallback URLs" do
        allow(ENV).to receive(:fetch).with("PRIMARY_RPC_URL").and_return("https://primary.example.com")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("EMPTY_RPC_URL").and_return("")

        client_double = instance_double(Eth::Client)
        allow(Eth::Client).to receive(:create).with("https://primary.example.com").and_return(client_double)

        client = described_class.client_for("PRIMARY_RPC_URL", fallback_env_keys: [ "EMPTY_RPC_URL" ])

        expect(client).to equal(client_double)
      end

      it "supports multiple fallback env keys" do
        allow(ENV).to receive(:fetch).with("PRIMARY_RPC_URL").and_return("https://primary.example.com")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SECONDARY_RPC_URL").and_return("https://secondary.example.com")
        allow(ENV).to receive(:[]).with("TERTIARY_RPC_URL").and_return("https://tertiary.example.com")

        client = described_class.client_for(
          "PRIMARY_RPC_URL",
          fallback_env_keys: [ "SECONDARY_RPC_URL", "TERTIARY_RPC_URL" ]
        )

        expect(client).to be_a(Web3::ResilientClient)
      end
    end
  end

  describe ".reset!" do
    it "clears cached clients" do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      client_double1 = instance_double(Eth::Client, "first")
      client_double2 = instance_double(Eth::Client, "second")

      call_count = 0
      allow(Eth::Client).to receive(:create) do
        call_count += 1
        call_count == 1 ? client_double1 : client_double2
      end

      first_client = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      expect(first_client).to equal(client_double1)

      described_class.reset!

      second_client = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      expect(second_client).to equal(client_double2)
      expect(first_client).not_to equal(second_client)
    end
  end

  # 🔴 [ARCH.114] Каскад є властивістю МЕРЕЖІ, і ці піни стережуть саме те, що
  # доти було недетермінованим. Проба (2026-08-29) показала: кеш ключується лише
  # на env-ключі, тож сайт, який каскад ОГОЛОШУЄ kwargʼом, діставав клієнта без
  # каскаду, якщо в тому ж потоці раніше побував сайт без нього — а для Polygon
  # таких вісім проти одного. Money-каскад працював лише за щасливим порядком джоб.
  describe "network-level fallback cascade (ARCH.114)" do
    before do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-primary.example.com")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("INFURA_POLYGON_RPC_URL").and_return("https://polygon-fallback.example.com")
    end

    it "builds a ResilientClient WITHOUT any kwarg when the network has a registered fallback" do
      expect(described_class.client_for("ALCHEMY_POLYGON_RPC_URL")).to be_a(Web3::ResilientClient)
    end

    # Пін на сам ДЕФЕКТ: доти результат залежав від того, хто в потоці перший.
    it "yields the same cascaded client regardless of call order" do
      bare_first = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      declared_second = described_class.client_for("ALCHEMY_POLYGON_RPC_URL",
                                                   fallback_env_keys: [ "INFURA_POLYGON_RPC_URL" ])

      expect(bare_first).to be_a(Web3::ResilientClient)
      expect(declared_second).to equal(bare_first)
    end

    it "keeps an explicit kwarg working as an override" do
      allow(ENV).to receive(:[]).with("CELO_RPC_URL_FALLBACK_1").and_return("https://celo-alt.example.com")

      client = described_class.client_for("ALCHEMY_POLYGON_RPC_URL",
                                          fallback_env_keys: [ "CELO_RPC_URL_FALLBACK_1" ])
      expect(client).to be_a(Web3::ResilientClient)
    end
  end

  # ⛔ Реєстр не сміє обіцяти провайдера, якого немає: порожній ENV просто випадає
  # зі списку, тож вигаданий ключ нічого не ламає — і саме тому прожив би роками
  # як фальшива обіцянка другого RPC. Пін тримає реєстр проти `.env.example`.
  describe "NETWORK_FALLBACK_ENV_KEYS registry honesty" do
    it "declares only keys that actually exist in .env.example" do
      declared = File.read(Rails.root.join(".env.example")).scan(/^([A-Z0-9_]+)=/).flatten
      registered = described_class::NETWORK_FALLBACK_ENV_KEYS.values.flatten.uniq

      expect(registered - declared).to be_empty,
                                       "реєстр каскадів обіцяє ENV-ключі, яких немає в .env.example: #{(registered - declared).join(', ')}"
    end

    it "is non-vacuous (the registry is not empty)" do
      expect(described_class::NETWORK_FALLBACK_ENV_KEYS).not_to be_empty
    end
  end
end
