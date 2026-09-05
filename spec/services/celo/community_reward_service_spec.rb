# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Celo::CommunityRewardService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:target_date) { Date.yesterday }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    # ⚖️ [2026-08-31] Форма ОДНОАРГУМЕНТНА — після зняття hardcoded-фолбека живий сайт кличе
    # `ENV.fetch("CELO_RPC_URL")` без дефолту, тож старий `.with(key, anything)` не збігався б
    # ЖОДНОГО разу й пережив би зміну зеленим (пін на порожній множині).
    # 🔒 СТЕЛЯ, ВИМІРЯНА, а не припущена: сьогодні цей стаб не несе НІЧОГО — зняття його
    # цілком лишає 33/33 зеленими, бо `RpcConnectionPool` застабано в кожному прикладі. Він
    # лишається як ОГОЛОШЕННЯ ПЕРЕДУМОВИ: щойно якийсь приклад перестане стабити пул, шлях
    # упреться в реальний `ENV.fetch` і впаде `KeyError` — і тоді краще, щоб причина стояла
    # тут, а не читалась як несподіванка. Хост теж замінено: мертвий `alfajores-forno` у
    # фікстурі моделював NXDOMAIN як норму.
    allow(ENV).to receive(:fetch).with("CELO_RPC_URL").and_return("https://celo-mainnet.example.com")
    allow(ENV).to receive(:fetch).with("ORACLE_CELO_PRIVATE_KEY").and_return("0x" + "ab" * 32)
    allow(ENV).to receive(:fetch).with("CELO_CUSD_CONTRACT_ADDRESS").and_return("0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1")

    # [ARCH.50] the reward now arms a Celo-aware reconcile — stub it everywhere.
    allow(CeloConfirmationWorker).to receive(:perform_in)

    # Kredis може бути відсутнім у тестовому середовищі (стаб серіалізує синхронно).
    unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
    end
  end

  # Builds an eligible (healthy) cluster + stubs the EVM client to a successful transfer.
  def stub_healthy_and_eligible(tx_hash: "0x" + SecureRandom.hex(32))
    create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                        target_date: target_date, stress_index: 0.05, fraud_detected: false)
    mock_client = instance_double(Eth::Client)
    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(instance_double(Eth::Key, address: "0x" + "aa" * 20))
    allow(Eth::Contract).to receive(:from_abi).and_return(instance_double(Eth::Contract))
    allow(mock_client).to receive_messages(transact: tx_hash, get_balance: 1 * 10**18)
    allow(Kredis).to receive(:lock).and_yield
    mock_client
  end

  describe "#reward_community! — happy path + intent lifecycle (ARCH.50)" do
    let!(:client) { stub_healthy_and_eligible }

    it "creates a :sent BlockchainTransaction (celo/cusd) with reward_date + arms the reconcile" do
      expect {
        described_class.new(cluster, target_date).reward_community!
      }.to change(BlockchainTransaction, :count).by(1)

      tx = BlockchainTransaction.last
      expect(tx.blockchain_network).to eq("celo")
      expect(tx.token_type).to eq("cusd")
      expect(tx.amount).to eq(5.0)
      expect(tx.status).to eq("sent")
      expect(tx.tx_hash).to be_present
      expect(tx.sourceable).to eq(cluster)
      # [ARCH.50] the logical idempotency key — the audit day, NOT created_at.
      expect(tx.reward_date).to eq(target_date)
      expect(CeloConfirmationWorker).to have_received(:perform_in).with(30.seconds, tx.id, kind_of(String))
    end

    it "returns the tx_hash on success" do
      expect(described_class.new(cluster, target_date).reward_community!).to start_with("0x")
    end

    it "writes a :pending intent BEFORE the broadcast (mark_as_sent only after)" do
      seen_status = nil
      allow(client).to receive(:transact) do
        # at transact time the intent must already exist as :pending
        seen_status = BlockchainTransaction.where(sourceable: cluster, token_type: :cusd).last&.status
        "0x" + SecureRandom.hex(32)
      end
      described_class.new(cluster, target_date).reward_community!
      expect(seen_status).to eq("pending")
    end
  end

  describe "#reward_community! — idempotency / dedup (ARCH.50 #0 + #2)" do
    let!(:client) { stub_healthy_and_eligible }

    # [ARCH.50 #0] The deterministic daily double-pay: with a PRODUCTION-realistic created_at
    # (today, the morning after the audit day), the dedup must STILL find the prior row by its
    # logical reward_date. The old created_at-window guard missed exactly this.
    it "skips a second fire for the same reward_date even when created_at is today (the #0 fix)" do
      create(:blockchain_transaction, sourceable: cluster, token_type: :cusd, blockchain_network: "celo",
                                      status: :sent, reward_date: target_date, amount: 5.0,
                                      to_address: organization.crypto_public_address,
                                      tx_hash: "0x" + SecureRandom.hex(32), created_at: Time.current)

      expect {
        result = described_class.new(cluster, target_date).reward_community!
        expect(result).to be_nil
      }.not_to change(BlockchainTransaction, :count)
      expect(client).not_to have_received(:transact)
    end

    it "blocks a re-pay against a :pending intent (possibly-landed) for the same reward_date" do
      create(:blockchain_transaction, sourceable: cluster, token_type: :cusd, blockchain_network: "celo",
                                      status: :pending, reward_date: target_date, amount: 5.0,
                                      to_address: organization.crypto_public_address, created_at: Time.current)

      expect { described_class.new(cluster, target_date).reward_community! }
        .not_to change(BlockchainTransaction, :count)
      expect(client).not_to have_received(:transact)
    end

    it "DOES re-pay when the prior attempt is :failed (admin retry path)" do
      create(:blockchain_transaction, sourceable: cluster, token_type: :cusd, blockchain_network: "celo",
                                      status: :failed, reward_date: target_date, amount: 5.0,
                                      to_address: organization.crypto_public_address,
                                      tx_hash: nil, created_at: Time.current)

      expect { described_class.new(cluster, target_date).reward_community! }
        .to change(BlockchainTransaction.where(status: :sent), :count).by(1)
    end

    it "re-pays a DIFFERENT reward_date (no cross-day contamination)" do
      create(:blockchain_transaction, sourceable: cluster, token_type: :cusd, blockchain_network: "celo",
                                      status: :sent, reward_date: target_date - 1, amount: 5.0,
                                      to_address: organization.crypto_public_address,
                                      tx_hash: "0x" + SecureRandom.hex(32), created_at: Time.current)

      expect { described_class.new(cluster, target_date).reward_community! }
        .to change(BlockchainTransaction.where(status: :sent), :count).by(1)
    end

    # [ARCH.64#2] stale reward_date (>2д) обходить dedup-вікно [rdate, +2д): backfill'у
    # created_at поза вікном → dedup сліпий → silent double-pay. Tripwire = гучний fail.
    it "raises on a stale reward_date >2д ago (backfill outside dedup window)" do
      stale_svc = described_class.new(cluster, 3.days.ago.to_date)
      expect { stale_svc.send(:reward_already_sent?) }.to raise_error(/ARCH\.64#2.*stale reward_date/)
    end

    # [ARCH.64#2 boundary] Межа age=2 (rdate РІВНО 2 дні тому): dedup-вікно [rdate, rdate+2д)
    # виключає rdate+2, тож і межа небезпечна → `<=` мусить raise (off-by-one guard).
    it "raises on a reward_date EXACTLY 2 days ago (dedup-window boundary)" do
      boundary_svc = described_class.new(cluster, 2.days.ago.to_date)
      expect { boundary_svc.send(:reward_already_sent?) }.to raise_error(/ARCH\.64#2.*stale reward_date/)
    end

    it "does NOT raise on the daily-path reward_date (yesterday, age=1)" do
      daily_svc = described_class.new(cluster, Date.yesterday)
      expect { daily_svc.send(:reward_already_sent?) }.not_to raise_error
    end
  end

  describe "#reward_community! — failure paths (ARCH.50 rescue split)" do
    let!(:client) { stub_healthy_and_eligible }

    # [ARCH.50 #1] crash-window: transact succeeds (cUSD sent) but mark_as_sent! crashes → the
    # intent stays :pending → a retry must NOT double-pay (the dedup blocks it).
    it "leaves a :pending intent (no double-pay) when persisting the :sent state crashes" do
      allow_any_instance_of(BlockchainTransaction).to receive(:mark_as_sent!).and_raise(ActiveRecord::StatementInvalid, "DB blip")

      expect { described_class.new(cluster, target_date).reward_community! }.to raise_error(/DB blip/)

      intent = BlockchainTransaction.where(sourceable: cluster, token_type: :cusd).last
      expect(intent.status).to eq("pending")

      # the retry (transact would re-send) must be blocked by the :pending dedup
      allow_any_instance_of(BlockchainTransaction).to receive(:mark_as_sent!).and_call_original
      expect { described_class.new(cluster, target_date).reward_community! }
        .not_to change(BlockchainTransaction, :count)
    end

    # [ARCH.50 #4/#7] a DETERMINISTIC node rejection (execution reverted) → the intent is failed
    # (re-payable) and the error is NOT re-raised → it does NOT count toward the shared breaker.
    it "fails the intent (re-payable) and does NOT re-raise on a deterministic rejection" do
      allow(client).to receive(:transact).and_raise(StandardError, "execution reverted: SafeERC20: transfer failed")

      result = nil
      expect { result = described_class.new(cluster, target_date).reward_community! }.not_to raise_error
      expect(result).to be_nil

      intent = BlockchainTransaction.where(sourceable: cluster, token_type: :cusd).last
      expect(intent.status).to eq("failed")
    end

    # [ARCH.50] an AMBIGUOUS error (nonce too low — a prior tx may have broadcast) → leave :pending,
    # do NOT re-pay, do NOT re-raise.
    it "leaves the intent :pending and does NOT re-raise on an ambiguous (nonce) error" do
      allow(client).to receive(:transact).and_raise(StandardError, "nonce too low")

      expect { described_class.new(cluster, target_date).reward_community! }.not_to raise_error
      expect(BlockchainTransaction.where(sourceable: cluster, token_type: :cusd).last.status).to eq("pending")
    end

    # a genuine TRANSIENT transport error → leave :pending (dedup blocks re-pay) + re-raise for retry.
    it "leaves a :pending intent and re-raises on a transient transport error" do
      allow(client).to receive(:transact).and_raise(StandardError, "Celo RPC timeout")

      expect { described_class.new(cluster, target_date).reward_community! }.to raise_error(/Celo RPC timeout/)
      expect(BlockchainTransaction.where(sourceable: cluster, token_type: :cusd).last.status).to eq("pending")
    end

    it "leaves the intent :pending on a malformed nil tx_hash (no double-pay)" do
      allow(client).to receive(:transact).and_return(nil)

      expect { described_class.new(cluster, target_date).reward_community! }
        .to change(BlockchainTransaction.where(status: :pending), :count).by(1)
      expect(CeloConfirmationWorker).not_to have_received(:perform_in)
    end

    # intent==nil → the failure happened BEFORE create_reward_intent! (e.g. the intent INSERT
    # itself blew up) → nothing was broadcast → re-raise (handle_transact_failure: raise if intent.nil?).
    it "re-raises (no broadcast) when the intent INSERT fails before any transact" do
      allow_any_instance_of(described_class).to receive(:create_reward_intent!)
        .and_raise(ActiveRecord::StatementInvalid, "intent insert blew up")

      expect { described_class.new(cluster, target_date).reward_community! }.to raise_error(/intent insert blew up/)
      expect(client).not_to have_received(:transact)
    end

    # eth wraps the on-chain revert reason in the error's `cause` → the classifier must read BOTH
    # `message` and `cause.message` (the rejection pattern can live in the cause, not the top message).
    it "classifies on the wrapped error.cause (deterministic reject hidden in the cause)" do
      wrapped = StandardError.new("RpcError")
      allow(wrapped).to receive(:cause).and_return(StandardError.new("execution reverted by the node"))
      allow(client).to receive(:transact).and_raise(wrapped)

      result = nil
      expect { result = described_class.new(cluster, target_date).reward_community! }.not_to raise_error
      expect(result).to be_nil
      expect(BlockchainTransaction.where(sourceable: cluster, token_type: :cusd).last.status).to eq("failed")
    end
  end

  # [ARCH.84] Підпис грошового рядка мусить нести ВИМІР, а не присуд: `stress_index`
  # рахується лише по деревах, що заговорили, тож «за ідеальне здоров'я кластера»
  # стверджувало про цілий кластер те, що виміряно на його частині. ⚖️ Присуд founder:
  # покриття виплату НЕ гейтує — зрізається сама заява. Пара обовʼязкова: один бік
  # доводив би лише наявність рядка, а не те, що він ДИСКРИМІНУЄ записане покриття
  # від незаписаного.
  describe "#reward_community! — підпис несе вимір, не присуд (ARCH.84)" do
    before { stub_healthy_and_eligible }

    it "несе stress_index і покриття, і НЕ стверджує «ідеальне здоров'я»" do
      AiInsight.last.update!(reasoning: { measured_trees: 1, total_trees: 5 })

      described_class.new(cluster, target_date).reward_community!

      notes = BlockchainTransaction.last.notes
      expect(notes).to include("stress_index 0.050", "виміряно 1/5 дерев")
      expect(notes).not_to include("ідеальне здоров")
    end

    it "каже «покриття не записано» замість друку числа, коли виміру немає" do
      described_class.new(cluster, target_date).reward_community!

      notes = BlockchainTransaction.last.notes
      expect(notes).to include("покриття не записано")
      expect(notes).not_to include("виміряно")
    end
  end

  describe "#reward_community! — eligibility gates (unchanged)" do
    it "skips without an AiInsight for target_date" do
      expect { described_class.new(cluster, target_date).reward_community! }.not_to change(BlockchainTransaction, :count)
    end

    it "skips when stress_index is too high" do
      create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                          target_date: target_date, stress_index: 0.5, fraud_detected: false)
      expect { described_class.new(cluster, target_date).reward_community! }.not_to change(BlockchainTransaction, :count)
    end

    # 🔴 [SLASH-1] Правило консенсусу: при ДВОХ легальних oracle-джерелах за добу гейт
    # питає НАЙГІРШЕ, а не те, що записалось першим. Доти голий `.first` віддавав
    # найстаріший рядок (AR додає `ORDER BY id ASC`), тож 5 cUSD залежали від порядку
    # запису — дефект систематичний, а не «плаваючий», і саме тому тихий.
    # Фікстура навмисно кладе ЗДОРОВЕ джерело ПЕРШИМ: без правила приклад зелений.
    context "when two oracle sources disagree that day" do
      it "withholds the reward when the LATER source sees stress" do
        create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                            target_date: target_date, stress_index: 0.05,
                            fraud_detected: false, model_source: "oracle_a")
        create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                            target_date: target_date, stress_index: 0.9,
                            fraud_detected: false, model_source: "oracle_b")

        expect { described_class.new(cluster, target_date).reward_community! }
          .not_to change(BlockchainTransaction, :count)
      end

      it "withholds the reward when only the LATER source flags fraud" do
        create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                            target_date: target_date, stress_index: 0.05,
                            fraud_detected: false, model_source: "oracle_a")
        create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                            target_date: target_date, stress_index: 0.05,
                            fraud_detected: true, model_source: "oracle_b")

        expect { described_class.new(cluster, target_date).reward_community! }
          .not_to change(BlockchainTransaction, :count)
      end
    end

    it "is eligible at the boundary stress_index 0.2" do
      stub_healthy_and_eligible
      AiInsight.last.update!(stress_index: 0.2)
      expect { described_class.new(cluster, target_date).reward_community! }.to change(BlockchainTransaction, :count).by(1)
    end

    # [SLASH-1, founder-ратифікація] vm_error-день (софт-збій прошивки → stress_index
    # 0.0 після P0-reframe) СВІДОМО reward-eligible — «не карати жертву» нашого бага;
    # емісія захищена окремо (vm_error-кадри → 0 GP). Пін РІШЕННЯ, не випадковості.
    it "stays eligible on a vm_error day (stress_index 0.0 — firmware fault is OUR bug)" do
      stub_healthy_and_eligible
      AiInsight.last.update!(stress_index: 0.0,
                             summary: "ЗБІЙ ПРОШИВКИ: пристрій не зміг порахувати біостатус (mruby VM error) — потрібен re-flash/OTA.")
      expect { described_class.new(cluster, target_date).reward_community! }.to change(BlockchainTransaction, :count).by(1)
    end

    it "skips when fraud is detected" do
      create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                          target_date: target_date, stress_index: 0.05, fraud_detected: true)
      expect { described_class.new(cluster, target_date).reward_community! }.not_to change(BlockchainTransaction, :count)
    end

    it "skips a nil stress_index" do
      create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                          target_date: target_date, stress_index: nil, fraud_detected: false)
      expect { described_class.new(cluster, target_date).reward_community! }.not_to change(BlockchainTransaction, :count)
    end

    it "skips without an org crypto address" do
      create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                          target_date: target_date, stress_index: 0.05, fraud_detected: false)
      organization.update_column(:crypto_public_address, nil)
      expect { described_class.new(cluster, target_date).reward_community! }.not_to change(BlockchainTransaction, :count)
    end

    it "skips a cluster with no organization at all (the organization&. nil-guard)" do
      stub_healthy_and_eligible
      allow(cluster).to receive(:organization).and_return(nil)
      expect { described_class.new(cluster, target_date).reward_community! }.not_to change(BlockchainTransaction, :count)
    end

    it "raises the low-balance guard before transacting" do
      create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                          target_date: target_date, stress_index: 0.05, fraud_detected: false)
      mock_client = instance_double(Eth::Client)
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(instance_double(Eth::Key, address: "0x" + "aa" * 20))
      allow(Eth::Contract).to receive(:from_abi).and_return(instance_double(Eth::Contract))
      allow(mock_client).to receive(:get_balance).and_return((0.01 * 10**18).to_i)
      allow(Kredis).to receive(:lock).and_yield

      # ⛔ [2026-09-05] ДРУГА гілка того самого розрізнення: тут баланс НЕНУЛЬОВИЙ,
      # але нижчий за мінімум — це справді вичерпання, і текст мусить казати саме це.
      # Пара «нуль ⊥ нижче мінімуму» і є предметом; поодинці кожна половина зелена
      # при зламаному розрізненні.
      expect { described_class.new(cluster, target_date).reward_community! }
        .to raise_error(/НИЖЧИЙ ЗА МІНІМУМ/)
    end
  end

  describe "RPC fallback cascade [E.49]" do
    it "exposes the fallback ENV keys in cascade order" do
      expect(described_class::RPC_FALLBACK_ENV_KEYS).to eq(%w[CELO_RPC_URL_FALLBACK_1 CELO_RPC_URL_FALLBACK_2])
    end

    it "builds a ResilientClient when fallback URLs are populated", :aggregate_failures do
      Web3::RpcConnectionPool.reset!
      stub_const("ENV", ENV.to_hash.merge(
        "CELO_RPC_URL" => "https://forno.celo.org",
        "CELO_RPC_URL_FALLBACK_1" => "https://rpc.ankr.com/celo",
        "CELO_RPC_URL_FALLBACK_2" => "https://1rpc.io/celo"
      ))
      # ⚖️ [2026-08-31] Без `fallback:` — `DEFAULT_RPC_URL` знято, і виклик тут дзеркалить
      # живий сайт: конфігурований каскад лишається, hardcoded-дефолту немає.
      client = Web3::RpcConnectionPool.client_for("CELO_RPC_URL",
                                                  fallback_env_keys: described_class::RPC_FALLBACK_ENV_KEYS)
      expect(client).to be_a(Web3::ResilientClient)
    ensure
      Web3::RpcConnectionPool.reset!
    end
  end

  describe "#reward_date_value" do
    it "coerces a Time target_date to a Date" do
      service = described_class.new(cluster, Time.current)
      expect(service.send(:reward_date_value)).to eq(Date.current)
    end
  end
end
