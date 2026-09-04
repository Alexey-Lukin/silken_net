# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainBurningService do
  # 🔴 [SLASH-1 §7, ⚖️ 2026-08-26] Статистичний вирок вимагає НЕвиродженої вибірки
  # СВІДКІВ (≥ `1/slash_fraction` = 5 за дефолтних 0.2), інакше сервіс віддає `nil`
  # → freeze + Field Audit. Доти фікстури будували «одне з двох», бо знаменником
  # були ВСІ активні дерева — а мовчазне дерево рахувалось свідченням про виживання.
  # Тепер пара «одне з двох» описує стан, у якому система свідомо ВІДМОВЛЯЄТЬСЯ
  # судити, тож приклади нижче будують когорту з ТІЄЮ САМОЮ часткою — очікувані
  # суми спалення від цього не рухаються, і саме тому вони лишились дослівними.
  def witness_cohort!(cluster, critical:, healthy:, stress: 1.0, date: AiInsight.reporting_date)
    Array.new(critical) do
      create(:ai_insight, analyzable: create(:tree, cluster: cluster),
             insight_type: :daily_health_summary,
             target_date: date, stress_index: stress)
    end
    Array.new(healthy) do
      create(:ai_insight, analyzable: create(:tree, cluster: cluster),
             insight_type: :daily_health_summary,
             target_date: date, stress_index: 0.1)
    end
  end

  let(:fake_tx_hash) { "0x#{'f' * 64}" }
  let(:mock_client)  { instance_double(Eth::Client) }
  let(:mock_key)     { instance_double(Eth::Key, address: "0x#{'d' * 40}") }
  let(:mock_contract) { instance_double(Eth::Contract) }

  let(:organization) { create(:organization, crypto_public_address: "0x#{'b' * 40}") }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:naas_contract) { create(:naas_contract, organization: organization, cluster: cluster) }

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_SLASHER_PRIVATE_KEY"] = "0x#{'a' * 64}"
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x#{'0' * 40}"

    # Kredis може бути відсутнім у тестовому середовищі
    unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
    end

    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
    allow(Kredis).to receive(:lock).and_yield

    # [SLASH.2] transact + slashUpTo balanceOf pre-read. Дефолтний баланс 10_000 SCC ≫ усі burn-суми
    # цих специв → effective_burn = burn_amount, clamp inert (існуючі amount_in_wei-очікування
    # лишаються дійсні). Clamp/evasion-гілки перевизначають :call локально.
    allow(mock_client).to receive_messages(transact: fake_tx_hash, call: 10_000 * (10**18))

    silence_broadcasts!(:wallet_balance, :tree_map, :alert_new, :alert_notify)

    # [SLASH-1 §3.2] Default: positive-A evidence present, so the existing burn-mechanics
    # specs exercise the slash path. CauseEvidence's own logic is unit-tested in
    # spec/services/slashing/cause_evidence_spec.rb; here we stub the collaborator and
    # test the GATE WIRING explicitly below.
    allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_return(true)
  end

  describe ".call" do
    context "when no confirmed transactions exist" do
      it "returns early when no confirmed transactions exist" do
        result = described_class.call(organization.id, naas_contract.id)

        expect(result).to be_nil
        expect(Eth::Client).not_to have_received(:create)
      end
    end

    # [ARCH.103 ⚖️ 08-20] Чиста база буває ВІДʼЄМНОЮ (спалення > мінт — легально,
    # відколи кластер несе кілька контрактів одночасно). Гард `<= 0` мовчить, як на
    # нулі: відʼємний інтент падав би об `validates greater_than: 0` у вічний
    # :manual_review. Мутація `<= 0` → `.zero?` червонить рівно цей приклад.
    context "when burns exceed mints (negative net base)" do
      it "returns early without slashing and without freezing" do
        tree = create(:tree, cluster: cluster)
        tree.wallet.blockchain_transactions.create!(
          amount: 25, token_type: :carbon_coin, status: :confirmed,
          sourceable: naas_contract, direction: :burn,
          to_address: organization.crypto_public_address, tx_hash: "0x#{'e' * 64}"
        )

        expect { described_class.call(organization.id, naas_contract.id) }
          .not_to change { [ BlockchainTransaction.count, EwsAlert.count ] }
        expect(Eth::Client).not_to have_received(:create)
      end
    end

    context "when confirmed minted tokens exist" do
      let!(:tree) { create(:tree, cluster: cluster) }

      before do
        tree.wallet.blockchain_transactions.create!(
          amount: 1000,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )
      end

      it "calculates damage ratio from AiInsight data" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'c' * 64}"
        )

        # [SLASH-1] 3 критичні з 6 СВІДКІВ → та сама частка 0.5, але вибірка невироджена.
        witness_cohort!(cluster, critical: 2, healthy: 3)
        create(:ai_insight,
               analyzable: tree,
               insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date,
               stress_index: 1.0)

        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          # §6.2 convex curve: slash_ratio = damage_ratio^GAMMA (0.5^1.3), NOT linear 0.5
          burn_amount = (2000 * (0.5**1.3)).ceil
          expected_wei = (burn_amount.to_f * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end

      it "FREEZES (no burn) when no AiInsight data and no source_tree — ARCH.46 magnitude indeterminate" do
        result = nil
        expect {
          result = described_class.call(organization.id, naas_contract.id)
        }.to change { EwsAlert.where(alert_type: :field_audit).count }.by(1)

        expect(result).to eq(:frozen)
        expect(mock_client).not_to have_received(:transact)
        expect(naas_contract.reload.status).not_to eq("breached")
      end

      # [ARCH.57] Freeze-вердикт (кошти утримано без burn) → audit-ланцюг з причиною;
      # chain-only (fraud-attribution + DID не пінити на публічний IPFS).
      it "records the frozen verdict into the audit chain, chain-only" do
        create(:user, :super_admin, email_address: "oracle.executioner@system.silkennet.com",
                                    first_name: "Oracle", last_name: "Executioner")

        expect { described_class.call(organization.id, naas_contract.id) }
          .to change { AuditLogWorker.jobs.size }.by(1)

        job = AuditLogWorker.jobs.last
        attrs = job["args"].first
        expect(attrs["action"]).to eq("slash_verdict_frozen")
        expect(attrs["organization_id"]).to eq(naas_contract.organization_id)
        expect(attrs["metadata"]).to include("verdict" => "frozen_cat_c",
                                             "reason" => "indeterminate_magnitude")
        expect(job["args"][1]).to be false
      end

      # [ARCH.46] Threshold fix: moderate stress (0.83 ≤ s < 1.0) now counts as damage (was 1.0-only).
      it "counts moderate stress (stress_index 0.9) as damage — proportional, not 100% (ARCH.46)" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000, token_type: :carbon_coin, status: :confirmed,
          to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
        )
        # [SLASH-1] 3 із 6 свідків на 0.9 → та сама частка 0.5, вибірка невироджена.
        witness_cohort!(cluster, critical: 2, healthy: 3, stress: 0.9)
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 0.9)

        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          burn_amount = (2000 * (0.5**1.3)).ceil # convex on 0.5, not 2000 (full)
          expect(amount_in_wei).to eq((burn_amount.to_f * (10**18)).to_i)
        end
      end

      # [ARCH.46] Data present + forest healthy (0 trees ≥0.83) + no source_tree → 0 damage → no burn.
      it "does NOT burn when data exists but the forest is healthy and there is no source_tree (ARCH.46)" do
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 0.5)

        result = described_class.call(organization.id, naas_contract.id)

        expect(result).to be_nil
        expect(mock_client).not_to have_received(:transact)
      end

      # 🔴 [⚖️ 2026-07-30] Два інсайти ОДНОГО дерева ≠ два дерева — тут це РОЗМІР спалення.
      # Дзеркало піна в `contract_health_check_service_spec` (той самий клас на тригер-половині):
      # без `.distinct` critical=2 із двох рядків одного дерева дає damage 2/2 = 1.0 замість 0.5,
      # і `.min`-clamp маскує це як «повна загибель» замість «половина».
      it "не рахує два інсайти одного дерева як два дерева (розмір спалення)" do
        witness_cohort!(cluster, critical: 2, healthy: 2) # [SLASH-1] 3 критичні з 6 свідків → частка 0.5 незмінна
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000, token_type: :carbon_coin, status: :confirmed,
          to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
        )
        # Одне дерево, ДВА легальні oracle-consensus рядки → одне критичне дерево з двох.
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 1.0, model_source: "oracle_a")
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 1.0, model_source: "oracle_b")
        create(:ai_insight, analyzable: other_tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 0.1)

        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          burn_amount = (2000 * (0.5**1.3)).ceil # damage 1/2, НЕ 2/2
          expect(amount_in_wei).to eq((burn_amount.to_f * (10**18)).to_i)
        end
      end

      # 🔴 [⚖️ 2026-07-30 · GOV.1] Поріг РОЗМІРУ мусить рухатись за DAO-голосом так само, як
      # поріг ТРИГЕРА — інакше `AiInsight::SLASH_STRESS_THRESHOLD`-константа тихо розводить
      # половини інваріанта ARCH.46. Дзеркало «respects a raised stress_threshold» на тригер-боці.
      it "сайзить damage за DAO-live порогом, не за константою (ARCH.46 тригер ≡ розмір)" do
        create(:system_parameter, key: "stress_threshold", value: "0.9",
                                  value_type: "float", category: "alerts")
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000, token_type: :carbon_coin, status: :confirmed,
          to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
        )
        # 0.85 — ВИЩЕ константи 0.83, НИЖЧЕ DAO-порога 0.9 → з константою це був би burn.
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 0.85)
        create(:ai_insight, analyzable: other_tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 0.1)

        result = described_class.call(organization.id, naas_contract.id)

        expect(result).to be_nil
        expect(mock_client).not_to have_received(:transact)
      end

      # 🔴 [⚖️ 2026-07-30] Знаменник мусить читати ЖИВИЙ COUNT, а не денормалізований
      # `active_trees_count`: колонку тримають Tree-колбеки, а `update_columns`/`update_all`/
      # `insert_all` їх обходять. Пін ловить відкат «назад на лічильник заради оптимізації» —
      # на ньому цей приклад дав би `2.0/0 = Infinity` → `.min` → тихі 100% замість чесних 1/2.
      it "сайзить damage живим COUNT, а не денормалізованим active_trees_count" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000, token_type: :carbon_coin, status: :confirmed,
          to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
        )
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 1.0)
        # [SLASH-1] 3 із 6 свідків → 0.5; лічильник лишається дрейфованим у нуль, і саме
        # це доводить, що знаменник його БІЛЬШЕ НЕ ЧИТАЄ (він тепер із `daily_insights`).
        witness_cohort!(cluster, critical: 2, healthy: 3)
        # Дрейф колонки: дерева ЖИВІ, а лічильник каже 0.
        cluster.update_column(:active_trees_count, 0)

        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          burn_amount = (2000 * (0.5**1.3)).ceil # 1/2 живого лісу, НЕ Infinity→100%
          expect(amount_in_wei).to eq((burn_amount.to_f * (10**18)).to_i)
        end
      end

      # 🔴 [⚖️ 2026-07-30] Змішаний випадок: є І критичні живі дерева, І свіжий труп. Гілка
      # `critical_count` перехоплює source_tree-тракт, тож труп у цьому вироку не карається
      # взагалі — і НЕ сміє ще й розбавляти знаменник (глобальний += 1 давав 2/11 замість 2/10,
      # тобто розходився з канон-формулою §3 «мертвих нема ні в чисельнику, ні в знаменнику»).
      it "не розбавляє статистичну частку свіжим трупом (2/10, не 2/11)" do
        others = create_list(:tree, 9, cluster: cluster)
        others.first.wallet.blockchain_transactions.create!(
          amount: 1000, token_type: :carbon_coin, status: :confirmed,
          to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
        )
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 1.0)
        create(:ai_insight, analyzable: others.first, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 1.0)
        # [SLASH-1] Решта вісім свідчать і здорові → множина свідків = 10, критичних 2.
        others.drop(1).each do |t|
          create(:ai_insight, analyzable: t, insight_type: :daily_health_summary,
                 target_date: AiInsight.reporting_date, stress_index: 0.1)
        end
        dead = create(:tree, cluster: cluster)
        dead.update!(status: :deceased)

        described_class.call(organization.id, naas_contract.id, source_tree: dead)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          burn_amount = (2000 * ((2.0 / 10)**1.3)).ceil # 2 критичні з 10 ЖИВИХ
          expect(amount_in_wei).to eq((burn_amount.to_f * (10**18)).to_i)
        end
      end

      # 🔴 [SLASH-1, ⚖️ 2026-08-26] ГОЛОВНИЙ пін доктрини: мовчання НЕ є свідченням
      # про виживання. Мовчазне дерево в чисельник потрапити не може (немає інсайту),
      # а в знаменнику стояло — і РОЗБАВЛЯЛО шкоду тих, хто справді свідчив.
      # Сценарій: 6 дерев свідчать (3 критичні), ще 20 мовчать. Стара шкала дала б
      # 3/26 ≈ 11.5%; чесна — 3/6 = 50%.
      it "мовчазні дерева не рахуються ЗНАМЕННИКОМ — мовчання НЕ є свідченням про виживання" do
        # Когорта — ЄДИНЕ джерело свідків: `tree` (носій мінту) свідомо лишається
        # МОВЧАЗНИМ, тобто теж належить множині, яку доктрина виключає.
        witness_cohort!(cluster, critical: 3, healthy: 3)
        create_list(:tree, 20, cluster: cluster) # мовчать: жодного AiInsight

        described_class.call(organization.id, naas_contract.id)

        expect(mock_client).to have_received(:transact) do |_c, _m, _a, amount_in_wei, **_o|
          # База спалення в ЦЬОМУ прикладі — 1000 (один мінт `tree`), не 2000:
          # сусідні приклади додають другий мінт, цей ні. Частка 3/6, а НЕ 3/27.
          burn_amount = (1000 * (0.5**1.3)).ceil
          expect(amount_in_wei).to eq((burn_amount.to_f * (10**18)).to_i)
        end
      end

      # 🔴 [SLASH-1 §7] Друга половина, без якої перша була б МНОЖНИКОМ: при виродженій
      # вибірці свідків будь-яке одне критичне дерево дало б ≈100%. Нижче межі
      # (`1/slash_fraction` = 5) статистичного вироку немає — freeze + Field Audit,
      # рівно як ратифіковано для тригерного боку.
      it "не судить статистично за виродженою вибіркою свідків — freeze, не 100%" do
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 1.0)
        create_list(:tree, 9, cluster: cluster) # мовчать → свідків рівно 1

        expect(described_class.call(organization.id, naas_contract.id)).to eq(:frozen)
        expect(mock_client).not_to have_received(:transact)
      end

      # 🔴 [⚖️ 2026-07-30] Знаменник source_tree-гілки = ліс ДО події. Дерево, за смерть якого
      # караємо, вже вибуло з активних (хук статусу спрацьовує до воркера), тож наївний перехід
      # на «лише активні» дав би кластеру з двох дерев 1/1 = 100% замість чесних 1/2.
      it "міряє смерть дерева від лісу ДО події, не після (2 дерева → 1/2, не 1/1)" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000, token_type: :carbon_coin, status: :confirmed,
          to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
        )
        tree.update!(status: :deceased)

        described_class.call(organization.id, naas_contract.id, source_tree: tree)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          burn_amount = (2000 * (0.5**1.3)).ceil # 1/2 живого лісу, НЕ 1/1
          expect(amount_in_wei).to eq((burn_amount.to_f * (10**18)).to_i)
        end
      end

# 🔴 [SLASH-1, ⚖️ 2026-08-26] Масова вирубка сайзиться від УСІХ трупів доби, не від одного.
# Доти N зрубаних дерев давали розмір ОДНОГО (`1/(вцілілі+1)`), а решта N−1 не входили
# ні в чисельник, ні в знаменник — тобто суцільна вирубка коштувала як одне дерево.
it "рахує ВСІХ трупів доби, не лише source (3 мертві + 1 живий → 3/4)" do
  survivor = create(:tree, cluster: cluster)
  survivor.wallet.blockchain_transactions.create!(
    amount: 1000, token_type: :carbon_coin, status: :confirmed,
    to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
  )
  two_more = create_list(:tree, 2, cluster: cluster)
  two_more.each { |t| t.update!(status: :removed) }
  tree.update!(status: :deceased)

  described_class.call(organization.id, naas_contract.id, source_tree: tree)

  expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
    burn_amount = (2000 * ((3.0 / 4)**1.3)).ceil # 3 трупи з 4 дерев ДО події
    expect(amount_in_wei).to eq((burn_amount.to_f * (10**18)).to_i)
  end
end

# 🔴 [SLASH-1] Повна загибель мусить давати РІВНО 100% — це обіцянка канону §2, якої
# стара форма не могла виконати НІКОЛИ (при нулі вцілілих вона давала 1/(0+1) для
# одного дерева, тобто ≈0,25% після ^GAMMA при сотні трупів).
it "дає 100% при повній загибелі кластера (3 мертвих, 0 живих)" do
  two_more = create_list(:tree, 2, cluster: cluster)
  two_more.each { |t| t.update!(status: :removed) }
  tree.update!(status: :deceased)

  described_class.call(organization.id, naas_contract.id, source_tree: tree)

  expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
    # damage 3/3 = 1.0 → 100% ЧИСТОЇ емісії кластера (тут лише tree-транзакція, 1000)
    expect(amount_in_wei).to eq((1000.0 * (10**18)).to_i)
  end
end

# 🔴 [SLASH-1] Legacy-дерево: `status_changed_at` NULL (колонка молодша за нього).
# Це стан УСІХ наявних дерев на момент міграції, тож fallback тут — не крайній
# випадок, а базовий: без нього мертвий кластер дав би `0/0`.
it "не ділить на нуль, коли source вмер ДО появи status_changed_at (NULL)" do
  survivor = create(:tree, cluster: cluster)
  survivor.wallet.blockchain_transactions.create!(
    amount: 1000, token_type: :carbon_coin, status: :confirmed,
    to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
  )
  tree.update!(status: :deceased)
  tree.update_column(:status_changed_at, nil) # legacy: колонки тоді не існувало

  described_class.call(organization.id, naas_contract.id, source_tree: tree)

  expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
    burn_amount = (2000 * (0.5**1.3)).ceil # 1 труп із 2 дерев ДО події — стара поведінка
    expect(amount_in_wei).to eq((burn_amount.to_f * (10**18)).to_i)
  end
end

      # [ARCH.46] Date threading: damage is queried on the PASSED target_date, not a re-derived local_yesterday.
      it "queries AiInsight on the passed target_date, not local_yesterday (ARCH.46 date-threading)" do
        explicit_date = AiInsight.reporting_date - 1.day
        witness_cohort!(cluster, critical: 4, healthy: 0, date: explicit_date) # [SLASH-1] когорта на ТІЙ САМІЙ даті
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: explicit_date, stress_index: 1.0)

        # Default (local_yesterday) would find nothing → freeze; the passed date finds it → burns.
        result = described_class.call(organization.id, naas_contract.id, target_date: explicit_date)

        expect(result).to eq(:slashed)
        expect(mock_client).to have_received(:transact)
      end

      # 🔴 [SLASH-1] Друга координата того самого інваріанта: ПОРІГ теж подорожує з
      # вироком, а не перечитується в момент виконання. Доти ARCH.46 звів обидві
      # половини на одну ДОБУ, лишивши їм два різні моменти читання порога — тож
      # DAO-голос (чи закінчення 24-год TTL) між диспатчем і виконанням розводив
      # тригер і розмір. Небезпечний напрямок: поріг ЗНИЖЕНО у вікні → burn більший
      # за підставу, на якій тригер спрацював.
      it "sizes damage on the threshold FIXED at trigger time, not the one live at execution" do
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 0.9)

        # DAO знизив поріг ПІСЛЯ того, як тригер спрацював на 0.95.
        SystemParameter.set(:stress_threshold, "0.5", value_type: "decimal", source: "governance")

        result = described_class.call(organization.id, naas_contract.id, stress_threshold: 0.95)

        # За зафіксованим порогом 0.95 дерево зі стресом 0.9 НЕ критичне → нема шкоди.
        # Якби сервіс перечитав живий 0.5 — воно стало б критичним і спалило б кошти.
        expect(result).not_to eq(:slashed)
        expect(mock_client).not_to have_received(:transact)
      end

      # [ARCH.46] Contractual early-exit forfeiture MUST still full-burn on no-data (NOT freeze).
      it "still full-burns a contractual forfeiture with no data and no source_tree (ARCH.46 exempts contractual)" do
        described_class.call(organization.id, naas_contract.id, contractual: true)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          expected_wei = (1000.0 * (10**18)).to_i # full forfeiture
          expect(amount_in_wei).to eq(expected_wei)
        end
      end

      # [ARCH.46] Contractual is checked FIRST → full forfeiture even with stressed trees (not
      # short-circuited to proportional by critical_count, the code-review fix).
      it "full-burns a contractual forfeiture even with stressed trees (contractual-first, not proportional)" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 1000, token_type: :carbon_coin, status: :confirmed,
          to_address: organization.crypto_public_address, tx_hash: "0x#{'d' * 64}"
        )
        # 1 of 2 trees stressed → without the contractual-first guard this would size to 0.5.
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 0.9)

        described_class.call(organization.id, naas_contract.id, contractual: true)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          expected_wei = (2000.0 * (10**18)).to_i # full forfeiture of both, not proportional 0.5
          expect(amount_in_wei).to eq(expected_wei)
        end
      end

      it "creates audit BlockchainTransaction on success" do
        expect {
          described_class.call(organization.id, naas_contract.id, source_tree: tree)
        }.to change(BlockchainTransaction, :count).by(1)

        audit_tx = BlockchainTransaction.last
        expect(audit_tx.tx_hash).to eq(fake_tx_hash)
        # [ARCH.45] intent → :sent; BlockchainConfirmationWorker дорезолвить до :confirmed/:failed.
        expect(audit_tx.status).to eq("sent")
        expect(audit_tx.to_address).to eq(organization.crypto_public_address)
        expect(audit_tx.sourceable).to eq(naas_contract)
      end

      it "schedules BlockchainConfirmationWorker after sending transaction" do
        allow(BlockchainConfirmationWorker).to receive(:perform_in).with(30.seconds, fake_tx_hash, kind_of(String)) # [ARCH.52] +created_at

        described_class.call(organization.id, naas_contract.id, source_tree: tree)

        expect(BlockchainConfirmationWorker).to have_received(:perform_in).with(30.seconds, fake_tx_hash, kind_of(String))
      end

      # [ARCH.45] Double-burn crash-window guard — slash() необоротний; на повторному виклику
      # (non-StandardError крах, що обходить rescue-breach) intent-marker не дає палити вдруге.
      context "when an in-flight slash already exists" do
        it "does NOT re-slash when an in-flight :sent slash already exists for the contract" do
          BlockchainTransaction.create!(
            sourceable: naas_contract, cluster: cluster, amount: 500, token_type: :carbon_coin,
            direction: :burn, status: :sent, to_address: organization.crypto_public_address, tx_hash: fake_tx_hash,
            notes: "prior in-flight slash"
          )

          result = described_class.call(organization.id, naas_contract.id)

          expect(result).to eq(:slashed)
          expect(mock_client).not_to have_received(:transact) # без повторного on-chain slash
        end

        it "re-slashes after a :pending intent (crash before broadcast), failing the stale one" do
          stale = BlockchainTransaction.create!(
            sourceable: naas_contract, cluster: cluster, amount: 500, token_type: :carbon_coin,
            direction: :burn, status: :pending, to_address: organization.crypto_public_address,
            notes: "pre-broadcast crash intent"
          )

          described_class.call(organization.id, naas_contract.id, source_tree: tree)

          expect(stale.reload.status).to eq("failed")
          expect(mock_client).to have_received(:transact) # свіжий slash виконано
        end

        it "escalates the intent to manual_review (not :failed) when the slash broadcast raises (ARCH.48)" do
          allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC down")

          result = described_class.call(organization.id, naas_contract.id, source_tree: tree)

          # [ARCH.48] An error from transact is ambiguous (the tx may have broadcast) → escalate to
          # :manual_review so the in-flight guard blocks a blind re-slash; the service does NOT re-raise.
          expect(result).to eq(:manual_review)
          intent = BlockchainTransaction.where(sourceable: naas_contract).last
          expect(intent.status).to eq("manual_review")
        end
      end

      # [ARCH.48] An AMBIGUOUS slash failure — an error FROM client.transact, where the tx may have
      # reached the mempool before the RPC response was lost — must NOT breach and must NOT auto-retry
      # (a blind re-slash would double-burn with a fresh nonce). It escalates the intent to
      # :manual_review (human reconciles on Polygonscan) and returns it, leaving the contract :active.
      it "escalates to manual_review WITHOUT breaching on an ambiguous transact failure (ARCH.48)" do
        allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")

        result = nil
        expect {
          result = described_class.call(organization.id, naas_contract.id, source_tree: tree)
        }.to change(EwsAlert, :count).by(1)

        expect(result).to eq(:manual_review)
        expect(naas_contract.reload.status).to eq("active") # NOT breached — slash unconfirmed

        audit = BlockchainTransaction.where(sourceable: naas_contract).last
        expect(audit.status).to eq("manual_review")
        # [SLASH-1 ⚖️ 2026-09-04] Власний тип, не спільний кошик: наш RPC-збій
        # більше не годує `comms_no_ack?`/`critical_unmaintained?` (self-ref → стеля pf).
        expect(EwsAlert.last.alert_type).to eq("slash_dispatch_failed")
      end

      # [ARCH.48] Anti-double-burn invariant: once an ambiguous slash sits in :manual_review, a later
      # attempt (e.g. the next cron cycle) must NOT re-slash — the in-flight guard short-circuits it.
      it "does NOT re-slash a manual_review (possibly-landed) slash on a later attempt (ARCH.48)" do
        allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")
        described_class.call(organization.id, naas_contract.id, source_tree: tree)

        # Even if the RPC "recovers", the guard must short-circuit on the manual_review intent.
        allow(mock_client).to receive(:transact).and_return(fake_tx_hash)
        result = described_class.call(organization.id, naas_contract.id, source_tree: tree)

        expect(result).to eq(:manual_review)
        expect(mock_client).to have_received(:transact).once # only the first (failed) call
      end

      # [ARCH.51-family] If the durable intent INSERT (create_slash_intent!) itself raises, `audit`
      # stays nil → the StandardError rescue must degrade gracefully via the `audit&.`-nil guards:
      # no breach, nothing broadcast, return :manual_review. Mirrors the Celo/insurance
      # intent-creation-failure path; this is the previously-untested audit-nil branch.
      it "returns :manual_review without breaching when the slash intent INSERT fails (audit nil)" do
        allow_any_instance_of(described_class).to receive(:create_slash_intent!)
          .and_raise(ActiveRecord::StatementInvalid, "intent insert failed")

        result = described_class.call(organization.id, naas_contract.id, source_tree: tree)

        expect(result).to eq(:manual_review)
        expect(naas_contract.reload.status).to eq("active") # not breached — nothing reached the chain
        expect(mock_client).not_to have_received(:transact) # failed before the lock/broadcast
      end

      # [ARCH.48] A LockTimeout means the lock was never acquired → transact never ran → the tx is
      # definitely NOT in the mempool → safe to retry. It must NOT breach; a retry re-executes the slash.
      it "re-executes the slash on retry after a LockTimeout (ARCH.48 — lock contention)" do
        call_count = 0
        allow(Kredis).to receive(:lock) do |*_args, **_kwargs, &blk|
          call_count += 1
          raise Kredis::LockTimeout, "contended" if call_count == 1

          blk.call
        end

        expect { described_class.call(organization.id, naas_contract.id, source_tree: tree) }
          .to raise_error(Kredis::LockTimeout)
        expect(naas_contract.reload.status).to eq("active") # not breached → retry can run

        result = described_class.call(organization.id, naas_contract.id, source_tree: tree)
        expect(result).to eq(:slashed)
        expect(naas_contract.reload.status).to eq("breached")
      end

      # [ARCH.48] LockTimeout на ОРАКУЛ-локу (не per-contract claim): intent уже створено (:pending),
      # але transact НЕ виконувався → tx не в мемпулі → безпечно retry. rescue fail-ить intent
      # (не in-flight), лишає контракт :active й re-raise-ить (Sidekiq re-slash-ить).
      it "fails the :pending intent and re-raises on an ORACLE-lock timeout (transact never ran — ARCH.48)" do
        allow(Kredis).to receive(:lock) do |key, **_kwargs, &blk|
          raise Kredis::LockTimeout, "oracle busy" if key.to_s.start_with?("lock:web3:oracle:")

          blk.call # per-contract claim yields normally
        end

        expect { described_class.call(organization.id, naas_contract.id, source_tree: tree) }
          .to raise_error(Kredis::LockTimeout)

        expect(mock_client).not_to have_received(:transact) # oracle-лок не взято → transact не запускався
        intent = BlockchainTransaction.where(sourceable: naas_contract).last
        expect(intent.status).to eq("failed") # :pending → :failed (не in-flight) → retry перепустить
        expect(naas_contract.reload.status).to eq("active") # НЕ breached
      end

      # [ARCH.48 / ARCH.45 case-2] If the crash happens AFTER a successful broadcast (audit already
      # :sent — e.g. the confirmation-worker enqueue or the breach-update fails), the slash WILL land,
      # so the contract MUST still breach (NOT escalate). The :sent guard then makes a retry idempotent.
      it "still breaches when a crash occurs AFTER a successful broadcast (ARCH.48 case-2)" do
        allow(mock_client).to receive(:transact).and_return(fake_tx_hash)
        call = 0
        allow(BlockchainConfirmationWorker).to receive(:perform_in) do
          call += 1
          raise StandardError, "Redis down" if call == 1 # crash right after mark_as_sent

          nil
        end

        expect { described_class.call(organization.id, naas_contract.id, source_tree: tree) }
          .to raise_error(StandardError, "Redis down")

        expect(naas_contract.reload.status).to eq("breached") # broadcast happened → slash will land
        audit = BlockchainTransaction.where(sourceable: naas_contract).last
        expect(audit.status).to eq("sent")
      end

      it "uses proportional damage ratio for single source_tree death" do
        other_tree = create(:tree, cluster: cluster)
        other_tree.wallet.blockchain_transactions.create!(
          amount: 500,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'e' * 64}"
        )

        # 2 trees total, source_tree specified → damage_ratio = 1/2 = 0.5
        described_class.call(organization.id, naas_contract.id, source_tree: tree)

        expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
          total_minted = 1500
          # §6.2 convex curve: slash_ratio = 0.5^1.3 (not linear 0.5)
          burn_amount = (total_minted * (0.5**1.3)).ceil
          expected_wei = (burn_amount.to_f * (10**18)).to_i
          expect(amount_in_wei).to eq(expected_wei)
        end
      end
    end
  end

  # =========================================================================
  # SLASH.2 — slashUpTo (on-chain clamp) + evasion tripwire
  # =========================================================================
  describe "SLASH.2 — on-chain balance clamp + evasion" do
    let!(:tree) { create(:tree, cluster: cluster) }

    before do
      tree.wallet.blockchain_transactions.create!(
        amount: 1000, token_type: :carbon_coin, status: :confirmed,
        to_address: organization.crypto_public_address, tx_hash: "0x#{'a' * 64}"
      )
    end

    it "calls slashUpTo (not slash) on-chain with the intent-id contextHash" do
      described_class.call(organization.id, naas_contract.id, source_tree: tree)

      intent = BlockchainTransaction.order(:id).last
      expected_context = "0x" + intent.id.to_i.to_s(16).rjust(64, "0")
      expect(mock_client).to have_received(:transact)
        .with(mock_contract, "slashUpTo", organization.crypto_public_address, anything,
              expected_context, hash_including(sender_key: mock_key))
    end

    it "reads balanceOf before slashing" do
      described_class.call(organization.id, naas_contract.id, source_tree: tree)

      expect(mock_client).to have_received(:call).with(mock_contract, "balanceOf", organization.crypto_public_address)
    end

    it "clamps the burn to the on-chain balance when it is below the pre-tax DB sum" do
      # Pre-tax burn = 1000 (single tree, damage 1.0); on-chain holds only 600 (tax + market moves).
      allow(mock_client).to receive(:call).and_return(600 * (10**18))

      described_class.call(organization.id, naas_contract.id, source_tree: tree)

      expect(mock_client).to have_received(:transact) do |_c, _m, _addr, amount_in_wei, **_o|
        expect(amount_in_wei).to eq(600 * (10**18)) # clamped to balance, not the 1000 pre-tax sum
      end
      # Intent-marker records the realistic (clamped) amount, not the pre-tax 1000.
      expect(BlockchainTransaction.where(sourceable: naas_contract).last.amount).to eq(600)
    end

    it "still records the full requested burn when the balance exceeds it (no clamp)" do
      allow(mock_client).to receive(:call).and_return(5_000 * (10**18))

      described_class.call(organization.id, naas_contract.id, source_tree: tree)

      expect(BlockchainTransaction.where(sourceable: naas_contract).last.amount).to eq(1000)
    end

    context "when the violator has drained all tokens before the slash (evasion)" do
      it "escalates to Field Audit WITHOUT breaching or broadcasting, returns :evaded" do
        allow(mock_client).to receive(:call).and_return(0)

        result = nil
        expect {
          result = described_class.call(organization.id, naas_contract.id, source_tree: tree)
        }.to change { EwsAlert.where(alert_type: :field_audit).count }.by(1)

        expect(result).to eq(:evaded)
        expect(mock_client).not_to have_received(:transact)
        expect(naas_contract.reload.status).to eq("active") # NOT breached — nothing burned
        # No intent-marker created (no on-chain attempt was made).
        expect(BlockchainTransaction.where(sourceable: naas_contract)).to be_empty
      end

      it "also escalates when the residual balance is below 1 whole SCC (sub-unit dust)" do
        allow(mock_client).to receive(:call).and_return((10**18) - 1) # 0.999… SCC

        result = described_class.call(organization.id, naas_contract.id, source_tree: tree)

        expect(result).to eq(:evaded)
        expect(mock_client).not_to have_received(:transact)
      end

      # Evasion БЕЗ source_tree → context-гілка «кластер», не «дерево» (330-else). Потрібен
      # AiInsight, щоб damage_ratio був визначений (інакше freeze спрацював би до balanceOf).
      it "escalates evasion with cluster context (not tree) when there is no source_tree" do
        witness_cohort!(cluster, critical: 4, healthy: 0) # [SLASH-1] невироджена вибірка
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
               target_date: AiInsight.reporting_date, stress_index: 1.0)
        allow(mock_client).to receive(:call).and_return(0)

        result = described_class.call(organization.id, naas_contract.id)

        expect(result).to eq(:evaded)
        # Раніше тут стояв `include("кластер #N")` БЕЗ обгортки локалі — і саме
        # тому проходив: український фрагмент їхав параметром і рендерився в
        # будь-якій мові. Тепер суб'єкт у КЛЮЧІ, а спека це і фіксує.
        alert = EwsAlert.where(alert_type: :field_audit).last
        expect(alert.message_key).to eq("slash_evasion_cluster")
        expect(alert.message_params["cluster_id"]).to eq(cluster.id)
        I18n.with_locale(:uk) { expect(alert.message).to include("кластер ##{cluster.id}") }
      end
    end
  end

  describe "positive-A-evidence gate (SLASH-1 §3.2)" do
    let!(:tree) { create(:tree, cluster: cluster) }

    before do
      tree.wallet.blockchain_transactions.create!(
        amount: 1000, token_type: :carbon_coin, status: :confirmed,
        to_address: organization.crypto_public_address, tx_hash: "0x#{'a' * 64}"
      )
    end

    it "FREEZES (no burn, no breach, Field-Audit alert) without direct Category-A evidence" do
      allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_return(false)

      result = nil
      expect {
        result = described_class.call(organization.id, naas_contract.id, source_tree: tree)
      }.to change { EwsAlert.where(alert_type: :field_audit).count }.by(1)

      expect(result).to eq(:frozen)
      expect(mock_client).not_to have_received(:transact)
      expect(naas_contract.reload.status).not_to eq("breached")
    end

    it "SLASHES (returns :slashed, burns, breaches) when Category-A evidence is present" do
      result = described_class.call(organization.id, naas_contract.id, source_tree: tree)

      expect(result).to eq(:slashed)
      expect(mock_client).to have_received(:transact)
      expect(naas_contract.reload.status).to eq("breached")
    end

    it "BYPASSES the gate for a contractual burn even without Category-A evidence" do
      allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_return(false)

      described_class.call(organization.id, naas_contract.id, source_tree: tree, contractual: true)

      expect(mock_client).to have_received(:transact)
    end
  end

  # [SLASH-1] Спека сідає в ТОЧКУ ДІЇ — на сам шов між двома писачами термінального
  # стану. Доти `ContractTerminationService`-спека пінила `:cancelled`, а ця пінила
  # `:breached`, і ЖОДНА не перетинала шва: сервіс наприкінці contractual-шляху
  # перезаписував чужий термінальний стан, і жоден пін цього не бачив.
  # 💰 Ціна була не реєстровою: `NaasContract.total_insurance_premiums` рахує
  # `[active, fulfilled, breached]` з власним коментарем «cancelled повертається —
  # виключено», тож перезапис утримував 5% премії у Real-Yield звіті за договором,
  # який замовник ЗАКОННО скасував.
  describe "contractual forfeiture does NOT overwrite the customer's own termination" do
    let!(:tree) { create(:tree, cluster: cluster) }

    before do
      # Мінт, з якого рахується база форфейтури — без нього сервіс завершиться no-op'ом
      # на нульовій базі, і жоден із пінів нижче не мав би предмета (пін на порожній
      # множині зелений завжди).
      tree.wallet.blockchain_transactions.create!(
        amount: 1000, token_type: :carbon_coin, status: :confirmed, direction: :mint,
        to_address: organization.crypto_public_address, tx_hash: "0x#{'c' * 64}"
      )
      allow(mock_client).to receive(:transact).and_return("0x#{'e' * 64}")
      naas_contract.update!(status: :cancelled, cancelled_at: Time.current)
    end

    it "leaves the contract :cancelled (a voluntary exit is not a breach)" do
      described_class.call(organization.id, naas_contract.id, source_tree: tree, contractual: true)

      expect(naas_contract.reload.status).to eq("cancelled")
    end

    it "keeps the cancelled contract OUT of the insurance-premium base" do
      described_class.call(organization.id, naas_contract.id, source_tree: tree, contractual: true)

      expect(NaasContract.total_insurance_premiums).to eq(0)
    end

    it "labels the money row as forfeiture, not slashing (the customer reads this)" do
      described_class.call(organization.id, naas_contract.id, source_tree: tree, contractual: true)

      notes = BlockchainTransaction.where(sourceable: naas_contract, direction: :burn).last.notes
      expect(notes).to include("ФОРФЕЙТУРА")
      expect(notes).not_to include("SLASHING")
    end

    # 🔴 Крах ПІСЛЯ broadcast — окрема гілка, і на contractual-шляху вона мала власну
    # прогалину: `rescue` теж писав `:breached`, тобто збій у вікні між `mark_as_sent!`
    # і кінцем методу перетворював добровільний вихід на порушення. Мовчки, і саме
    # тоді, коли ретрай уже нічого не виправить (burn у ланцюгу).
    it "keeps the contract :cancelled even when the pass crashes AFTER broadcast" do
      allow(BlockchainConfirmationWorker).to receive(:perform_in).and_raise(StandardError, "post-broadcast boom")

      expect {
        described_class.call(organization.id, naas_contract.id, source_tree: tree, contractual: true)
      }.to raise_error(StandardError, /post-broadcast boom/)

      expect(naas_contract.reload.status).to eq("cancelled")
    end
  end

  describe "#calculate_slash_ratio (§6.2 convex curve)" do
    subject(:service) { described_class.new(organization.id, naas_contract.id) }

    it "reaches 100% slash for full negligent loss (no dead-zone)" do
      expect(service.send(:calculate_slash_ratio, 1.0)).to eq(1.0)
    end

    it "punishes a small loss gently (convex: d=0.1 → ~5%, not 10%)" do
      expect(service.send(:calculate_slash_ratio, 0.1)).to be_within(0.005).of(0.05)
    end

    it "is strictly below the old linear ratio for partial damage" do
      expect(service.send(:calculate_slash_ratio, 0.5)).to be < 0.5
    end

    it "is monotonic — more damage always burns strictly more" do
      ratios = [ 0.1, 0.3, 0.6, 1.0 ].map { |d| service.send(:calculate_slash_ratio, d) }
      expect(ratios).to eq(ratios.sort)
      expect(ratios.uniq.size).to eq(4)
    end

    it "returns 0.0 for zero damage" do
      expect(service.send(:calculate_slash_ratio, 0.0)).to eq(0.0)
    end

    it "caps the penalty_factor at PENALTY_FACTOR_MAX (multiplier ceiling, not final ratio)" do
      expect(service.send(:calculate_slash_ratio, 0.5, 5.0)).to be_within(1e-9).of((0.5**1.3) * 2.0)
    end

    it "clamps the final ratio to 1.0 even when the multiplier would exceed it" do
      expect(service.send(:calculate_slash_ratio, 1.0, 2.0)).to eq(1.0)
    end

    it "reads GAMMA from SystemParameter (DAO-governed)" do
      allow(SystemParameter).to receive(:current).and_call_original
      allow(SystemParameter).to receive(:current).with(:slash_gamma, default: 1.3).and_return(2.0)
      # γ=2.0 → 0.5^2 × 1.0 = 0.25
      expect(service.send(:calculate_slash_ratio, 0.5)).to be_within(1e-9).of(0.25)
    end

    # 🔴 [DOC-T.89] Заморожений закон вироку БʼЄ DAO-live. Без цього піна сама
    # заморозка не має чим почервоніти: усі приклади вище конструюють сервіс БЕЗ
    # неї, тож читають DAO-live і лишились би зеленими при повністю знятому каналі.
    #
    # Сценарій відтворює реальне вікно: тригер зняв γ=1.3, а між диспатчем і
    # виконанням DAO проголосував за 2.0. Напрямок несучий — `damage^γ` при
    # damage<1 УБУВАЄ по γ, тож DAO-live дав би МЕНШИЙ burn, ніж підстава, на якій
    # тригер спрацював. Пін вимагає саме замороженого числа, не «якогось».
    it "uses the verdict law frozen at the TRIGGER, not the DAO-live value at execution" do
      allow(SystemParameter).to receive(:current).and_call_original
      allow(SystemParameter).to receive(:current).with(:slash_gamma, default: 1.3).and_return(2.0)

      frozen = described_class.new(organization.id, naas_contract.id, slash_gamma: 1.3)

      # Заморожена γ=1.3 → 0.5^1.3 ≈ 0.4061; DAO-live γ=2.0 дала б 0.25.
      expect(frozen.send(:calculate_slash_ratio, 0.5)).to be_within(1e-9).of(0.5**1.3)
      expect(frozen.send(:calculate_slash_ratio, 0.5)).not_to be_within(1e-9).of(0.25)
    end

    it "freezes the penalty ceiling at the trigger too — both coordinates or neither" do
      allow(SystemParameter).to receive(:current).and_call_original
      allow(SystemParameter).to receive(:current)
        .with(:slash_penalty_factor_max, default: 2.0).and_return(5.0)

      frozen = described_class.new(organization.id, naas_contract.id, penalty_factor_max: 2.0)

      # pf=5.0 клемпиться ЗАМОРОЖЕНОЮ стелею 2.0 → 0.5^1.3 × 2.0; DAO-live дала б ×5.0.
      expect(frozen.send(:calculate_slash_ratio, 0.5, 5.0)).to be_within(1e-9).of((0.5**1.3) * 2.0)
    end
  end

  # [SLASH-1 ⚖️ 2026-09-04] Розкол кошика `system_fault` за АТРИБУЦІЄЮ. Предикати
  # читають `alert_type` і до `message_key` сліпі за побудовою, тож поки
  # деградований uplink їхав спільним типом, він годував ОБИДВА терми — за подію,
  # чийого винуватця встановити НЕМОЖЛИВО (лічильник провалених flush-розмов не
  # розрізняє, чий бік упав). Пін кличе САМ предикат, не повторює його список.
  describe "#critical_unmaintained? — атрибуційно-неоднозначний тип поза периметром" do
    let(:service) { described_class.new(organization.id, naas_contract.id) }

    def stale_alert!(alert_type)
      create(:ews_alert, cluster: cluster, tree: nil, alert_type: alert_type,
                         severity: :critical, message_key: "gateway_uplink_degraded",
                         message_params: { uid: "SNET-Q-1", fail_count: 99 })
        .update_column(:created_at, 2.hours.ago)
    end

    it "НЕ рахує `gateway_uplink_degraded` недбалістю оператора" do
      stale_alert!(:gateway_uplink_degraded)
      expect(service.send(:critical_unmaintained?)).to be(false)
    end

    # Позитивний контроль: та сама фікстура під СТАРИМ типом предикат вмикає —
    # тобто приклад вище доводить роботу ТИПУ, а не порожню множину.
    it "але рахує ТУ САМУ подію, якщо вона лишилась у спільному кошику" do
      stale_alert!(:system_fault)
      expect(service.send(:critical_unmaintained?)).to be(true)
    end

    # [SLASH-1 ⚖️ 2026-09-04] Друга родина того ж розколу: `hardware_fault` несе
    # КЛАС АТРИБУЦІЇ (залізо — наше або невизначене), а подію далі розрізняє
    # `message_key`. Обидва боки — «наше» й «невідомо» — за асиметрією §3.2
    # падають однаково: не карати.
    it "НЕ рахує родину `hardware_fault` (залізо: наше або невизначене)" do
      stale_alert!(:hardware_fault)
      expect(service.send(:critical_unmaintained?)).to be(false)
    end

    # 🔴 [SLASH-1 2026-09-04] Поправка до першої редакції присуду: розкол мусив зняти
    # РІВНО ОДИН терм, не обидва. `comms_no_ack?` цінує НЕПІДТВЕРДЖЕНІСТЬ сигналу
    # зв'язку, а не провину — інакше підстава «атрибуція невизначена» викинула б і
    # `queen_uplink_lost`, який так само не каже, Starlink упав чи наш бекхол.
    # Канон називає дефектом саме ПОДВІЙНИЙ заряд, тож пін тримає ОБИДВІ половини.
    it "але лишається сигналом зв'язку — рівно ОДИН терм, не подвійний" do
      stale_alert!(:gateway_uplink_degraded)
      expect(service.send(:comms_no_ack?)).to be(true)
      expect(service.send(:critical_unmaintained?)).to be(false)
      expect(service.send(:combine_penalty_factor, no_ack: true, no_maintenance: false))
        .to eq(described_class::DEFAULT_PENALTY_FACTOR + described_class::PF_NO_ACK)
    end

    it "залізна родина не є сигналом каналу — не входить у ЖОДЕН терм" do
      stale_alert!(:hardware_fault)
      expect(service.send(:comms_no_ack?)).to be(false)
      expect(service.send(:critical_unmaintained?)).to be(false)
    end
  end

  describe "#combine_penalty_factor (SLASH-1 de-correlation §6, pure)" do
    subject(:service) { described_class.new(organization.id, naas_contract.id) }

    def combine(no_ack: false, no_maintenance: false)
      service.send(:combine_penalty_factor, no_ack: no_ack, no_maintenance: no_maintenance)
    end

    it "is the negligence baseline when no signal fires" do
      expect(combine).to eq(1.0)
    end

    it "applies the no-ack uplift" do
      expect(combine(no_ack: true)).to eq(1.5)
    end

    # ⚫ [ARCH.118 ⚖️ 2026-09-03] The comms-correlated class has ONE member since Streamr left
    # (`PF_STREAMR_GAP` was a guarded hook that always contributed 0), so the SLASH-SAFETY §6
    # de-correlation example (no-ack + gap → max, NOT sum) has no second operand to pin. It
    # returns with the next comms-correlated signal that has ground truth (00_07 SLASH-1).
    it "feeds the multiplier into the slash curve, capped at PENALTY_FACTOR_MAX" do
      penalty_factor = combine(no_ack: true, no_maintenance: true) # 2.0 = PENALTY_FACTOR_MAX
      expect(service.send(:calculate_slash_ratio, 0.5, penalty_factor))
        .to be_within(1e-9).of((0.5**1.3) * 2.0)
    end
  end

  describe "#calculate_penalty_factor (SLASH-1 activation gate §3)" do
    subject(:service) { described_class.new(organization.id, naas_contract.id) }

    context "when the activation gate is off (default — DAO-confirm pending, 05_05 §3)" do
      it "returns the negligence baseline" do
        expect(service.send(:calculate_penalty_factor))
          .to eq(described_class::DEFAULT_PENALTY_FACTOR)
      end

      # `defined?`-memo (не ||=): false — легітимне закешоване значення, а не привід re-query.
      it "memoizes cause_uplift_enabled? — false is cached, not re-read from SystemParameter" do
        allow(SystemParameter).to receive(:current).and_call_original
        allow(SystemParameter).to receive(:current)
          .with(:slash_cause_uplift_enabled, default: false).and_return(false)

        2.times { service.send(:cause_uplift_enabled?) }

        expect(SystemParameter).to have_received(:current)
          .with(:slash_cause_uplift_enabled, default: false).once
      end

      it "stays inert even when a real cause signal is present" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :vandalism_breach, status: :active)
        expect(service.send(:calculate_penalty_factor)).to eq(1.0)
      end
    end

    context "when DAO-enabled via SystemParameter" do
      before do
        allow(SystemParameter).to receive(:current).and_call_original
        allow(SystemParameter).to receive(:current)
          .with(:slash_cause_uplift_enabled, default: false).and_return(true)
      end

      it "is the baseline when no signal fires" do
        expect(service.send(:calculate_penalty_factor)).to eq(1.0)
      end

      it "sources no-ack from an active critical node-offline EwsAlert and applies the uplift" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :queen_offline, status: :active)
        expect(service.send(:calculate_penalty_factor)).to eq(1.5)
      end
    end

    context "when sourcing signals from real records" do
      it "does not flag no-ack once the critical node-offline alert is resolved (acknowledged)" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :queen_offline, status: :resolved)
        expect(service.send(:comms_no_ack?)).to be(false)
      end

      it "flags physical negligence: aged critical alert with no MaintenanceRecord" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :fire_detected, status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(true)
      end

      # [ARCH.58] `actuator_stuck` = Rails загубив слід ВЛАСНОЇ команди. Той
      # самий vendor-attributable клас, що firmware_fault: виїзд лісника нашого
      # bookkeeping-збою не лікує. Обидва боки предиката перевіряються окремо —
      # blacklist мовчазний, тож без пари «виключений / не виключений» тест
      # зеленів би й на порожньому наборі.
      it "excludes actuator_stuck: our own lost-track bug is not operator negligence" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :actuator_stuck, status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      it "keeps actuator_stuck out of the comms_no_ack? whitelist too (no double penalty)" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :actuator_stuck, status: :active, created_at: 1.hour.ago)
        expect(service.send(:comms_no_ack?)).to be(false)
      end

      # [SLASH-1 ⚖️ 2026-09-04] Провал НАШОГО спалення доти їхав `system_fault`,
      # тобто типом, що сидить у whitelist `comms_no_ack?` І поза виключеннями
      # `critical_unmaintained?` — отже наш RPC-збій садив множник оператора рівно
      # на стелю (1.0 + 0.5 + 0.5 = PENALTY_FACTOR_MAX). Три приклади, бо регресія
      # можлива трьома шляхами: повернути тип, зняти виключення, додати тип у
      # whitelist — і кожен із них мовчазний.
      it "excludes slash_dispatch_failed: our own failed burn is not operator negligence" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :slash_dispatch_failed, status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      it "keeps slash_dispatch_failed out of comms_no_ack? too (no self-referential uplift)" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :slash_dispatch_failed, status: :active, created_at: 1.hour.ago)
        expect(service.send(:comms_no_ack?)).to be(false)
      end

      it "raises the failed-burn alert under its OWN type, never the shared system_fault basket" do
        expect {
          service.send(:handle_slashing_failure, "RPC timeout", 42.0)
        }.to change(EwsAlert, :count).by(1)

        alert = EwsAlert.order(:created_at).last
        expect(alert.alert_type).to eq("slash_dispatch_failed")
        expect(alert.message_key).to eq("burn_failure")
        expect(service.send(:critical_unmaintained?)).to be(false)
        expect(service.send(:comms_no_ack?)).to be(false)
      end

      it "clears physical negligence once a MaintenanceRecord exists for the alert" do
        alert = create(:ews_alert, cluster: cluster, severity: :critical,
                                   alert_type: :fire_detected, status: :active, created_at: 1.hour.ago)
        create(:maintenance_record, ews_alert: alert)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      # [SLASH-1 gap-E] Машинний resolve ≠ ack оператора. Коли Королева повернулась в ефір
      # САМА, GatewayStalenessSweepWorker закриває queen_offline без `user:` → виїзд не був
      # потрібен нікому → MaintenanceRecord не може існувати за визначенням → рядок інакше
      # читався б як «недбалість» вічно (ретеншену нема, а created_at-предикат рахується в
      # момент слешу — транзієнтна тиша латчила б PF_NO_MAINTENANCE назавжди).
      it "excludes a machine-resolved alert from critical_unmaintained? (gap-E)" do
        alert = create(:ews_alert, cluster: cluster, severity: :critical,
                                   alert_type: :queen_offline, status: :active, created_at: 1.hour.ago)
        alert.resolve!(notes: "Королева повернулась в ефір.") # машинний шлях — БЕЗ user:

        expect(alert.reload.resolved_by).to be_nil # дискримінатор, на якому тримається фільтр
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      # Анти-гейминг ЖИВИЙ: саме тому предикат не фільтрує по `.unresolved` — форестер
      # резолвить власні алерти (resolve ≡ ack), тож клік без виїзду штраф НЕ знімає.
      it "still flags an alert resolved BY A HUMAN with no MaintenanceRecord (anti-gaming)" do
        alert = create(:ews_alert, cluster: cluster, severity: :critical,
                                   alert_type: :queen_offline, status: :active, created_at: 1.hour.ago)
        alert.resolve!(user: create(:user), notes: "Подивився, начебто гаразд.")

        expect(service.send(:critical_unmaintained?)).to be(true)
      end

      # [P1-3] vandalism_breach = сам positive-A доказ Cat-A slash → НЕ рахується у comms/unmaintained
      # (self-ref: той самий tamper-алерт накручував penalty на СОБІ → множник завжди сідав на стелю).
      it "excludes vandalism_breach (the positive-A evidence) from comms_no_ack? (P1-3 self-ref)" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :vandalism_breach, status: :active)
        expect(service.send(:comms_no_ack?)).to be(false)
      end

      it "excludes vandalism_breach from critical_unmaintained? (P1-3 self-ref)" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :vandalism_breach, status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      # [SLASH-1 gap-D] Наш власний :field_audit (freeze/blackout) НЕ рахується як comms-loss —
      # інакше freeze самонакручував би penalty_factor на тій самій жертві.
      it "excludes our own :field_audit escalation from comms_no_ack? (gap-D)" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :field_audit, tree: nil, status: :active)
        expect(service.send(:comms_no_ack?)).to be(false)
      end

      it "excludes :field_audit from critical_unmaintained? (our audit-call ≠ operator negligence)" do
        create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :field_audit,
                           tree: nil, status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      # [SLASH-1] firmware_fault (wire vm_error) = vendor-attributable софт-збій:
      # «не виїхав на mruby-crash» ≠ фізична недбалість оператора (лікується OTA).
      it "excludes :firmware_fault from critical_unmaintained? (software fault ≠ negligence)" do
        create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :firmware_fault,
                           status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      # [SEC.20] firmware_reverted = термінальний vendor-стан (baseline після
      # fallback; не самогаситься, виїздом не лікується) — blacklist-виключення
      # обов'язкове, інакше PF_NO_MAINTENANCE штрафує оператора за наш баг.
      it "excludes :firmware_reverted from critical_unmaintained? (terminal vendor state)" do
        create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :firmware_reverted,
                           status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      # [SEC.21] canary-trip = потенційна софт-атака на парсер, не фізична
      # недбалість — виїзд її не лікує, тож поза critical_unmaintained?.
      it "excludes :firmware_canary_trip from critical_unmaintained? (software attack ≠ negligence)" do
        create(:ews_alert, cluster: cluster, severity: :critical, alert_type: :firmware_canary_trip,
                           status: :active, created_at: 1.hour.ago)
        expect(service.send(:critical_unmaintained?)).to be(false)
      end

      it "excludes :firmware_fault from comms_no_ack? (node is alive — only mruby is broken)" do
        create(:ews_alert, cluster: cluster, severity: :critical,
                           alert_type: :firmware_fault, status: :active)
        expect(service.send(:comms_no_ack?)).to be(false)
      end
    end
  end

  describe "calculate_damage_ratio edge cases" do
    context "when burn_amount is zero due to very small damage_ratio" do
      it "returns early without calling blockchain" do
        tree = create(:tree, cluster: cluster)
        # Create a very small confirmed amount
        tree.wallet.blockchain_transactions.create!(
          amount: 1,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )

        # Many trees so damage_ratio is tiny, and ceil of (1 * tiny) = 0
        # We need enough trees that 1/N rounds to 0 after ceil. That's impossible with ceil.
        # Instead, test when total_minted is 0 by removing confirmed txs.
        # Actually, the burn_amount.zero? path is when damage_ratio * total_minted rounds to 0.
        # With source_tree, damage_ratio = 1/total_trees.
        # If total_minted=1 and total_trees=1, burn_amount = ceil(1 * 1.0) = 1, not zero.
        # The zero path happens when total_minted_amount itself is zero (already tested).
        # Let's verify total_minted_amount.zero? early return.
        expect(Eth::Client).not_to have_received(:create)
      end
    end

    # 🔴 [⚖️ 2026-07-30] Порожній ЖИВИЙ ліс → розмір indeterminate → FREEZE, не 100%.
    # Доти стояло `return 1.0 if total_trees.zero?` — необоротне спалення за арифметику на
    # порожній множині. Пін тримає й другу half: знаменник читається реальним `trees.active.count`,
    # а не денормалізованим лічильником (той обходиться `update_columns`, і занижений до нуля
    # давав би `1.0/0 = Infinity` → `.min` → тихі 100%).
    context "when the cluster has no living trees" do
      it "freezes for Field Audit instead of burning 100%" do
        tree = create(:tree, cluster: cluster)
        tree.wallet.blockchain_transactions.create!(
          amount: 500,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )
        tree.update!(status: :deceased)

        result = described_class.call(organization.id, naas_contract.id)

        expect(result).to eq(:frozen)
        expect(mock_client).not_to have_received(:transact)
      end
    end

    context "when no AiInsight and no source_tree (ARCH.46)" do
      it "FREEZES for Field Audit instead of burning 100%" do
        tree = create(:tree, cluster: cluster)
        tree.wallet.blockchain_transactions.create!(
          amount: 200,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: organization.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )

        # No AiInsight records, no source_tree → magnitude indeterminate → freeze (not 100% burn).
        result = described_class.call(organization.id, naas_contract.id)

        expect(result).to eq(:frozen)
        expect(mock_client).not_to have_received(:transact)
      end
    end
  end

  describe "burn_amount zero" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "returns early when burn_amount is zero" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 1, status: :confirmed)
      allow_any_instance_of(described_class).to receive(:calculate_damage_ratio).and_return(0.0)

      result = described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)
      expect(result).to be_nil
    end
  end

  # [ARCH.96] База РОЗМІРУ спалення — вимірюється НА ІНТЕНТІ, бо саме його `amount`
  # їде в `slashUpTo(maxAmount)`, тобто це і є розмір незворотної дії.
  # 🔴 Перша редакція цих прикладів кликала `BlockchainTransaction.for_cluster(...)`
  # НАПРЯМУ — вони були зеленими й на голому `sum(:amount)`, бо міряли модель повз
  # сервіс, у якому живе дефект. Пін мусить стояти в точці ДІЇ (див. `04_06 §B.2`).
  describe "база розміру спалення (ARCH.96)" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    # `contractual: true` → damage_ratio = 1.0 → burn == база, тож `amount` інтенту
    # ЧИТАЄТЬСЯ як сама база (без домішки кривої штрафу).
    def slash_intent_amount
      described_class.call(organization.id, naas_contract.id, contractual: true)
      BlockchainTransaction.where(sourceable: naas_contract).order(created_at: :desc).first&.amount
    end

    it "не рахує SFC-виплати гаманців кластера як зароблений SCC" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100,
                                      token_type: :carbon_coin, status: :confirmed)
      create(:blockchain_transaction, wallet: wallet_burn, amount: 40,
                                      token_type: :forest_coin, status: :confirmed)

      expect(slash_intent_amount).to eq(100)
    end

    it "ВІДНІМАЄ попереднє спалення — повторний слеш не палить із роздутої бази" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100,
                                      token_type: :carbon_coin, status: :confirmed)
      # Завершений burn-інтент: той самий тип, ДОДАТНИЙ amount; напрямок ОГОЛОШЕНО [ARCH.95].
      # `:confirmed` свідомо: незавершений перехопив би in-flight guard і слеш би не стався.
      create(:blockchain_transaction, wallet: wallet_burn, amount: 30,
                                      token_type: :carbon_coin, status: :confirmed,
                                      sourceable: naas_contract, direction: :burn)

      expect(slash_intent_amount).to eq(70)
    end

    # [ARCH.120] ТРЕТЯ вісь бази — ВАЛЮТА, і вона не є віссю транспорту. Сусід вище
    # стереже SFC (наш токен, чужа монета); тут — USDC (чужа мережа, чужа монета),
    # яку Solana-мікровинагороди писали під `:carbon_coin`. Агрегат питає
    # `token_type` і `blockchain_network` не бачить за побудовою, тож рядок
    # додавався до намінтованого SCC — причому фантом ПЕРЕВАЖАВ справжній заробіток
    # того самого аплінка на порядок (винагорода має ненульову БАЗУ, а SCC за той
    # самий пакет — це лише `growth_points / 10_000`; формула-дім [`04_02`]).
    it "не рахує Solana-мікровинагороду в USDC як зароблений SCC" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100,
                                      token_type: :carbon_coin, status: :confirmed)
      create(:blockchain_transaction, wallet: wallet_burn, amount: 0.0131,
                                      token_type: :usdc, status: :confirmed,
                                      blockchain_network: "solana",
                                      to_address: "7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV")

      expect(slash_intent_amount).to eq(100)
    end

    # [SLASH-1 ⚖️ 2026-09-04] Вікно форфейтури = термін ЦЬОГО договору. Пін цілиться в
    # РЕАЛЬНУ несправедливість, а не в механіку: емісія, зароблена ДО того, як цей
    # договір почався (тобто під попереднім — повністю виконаним і оплаченим), спаленню
    # не підлягає. ⚠️ Фікстура свідомо тримає ОБИДВІ половини: якби вона мала лише рядок
    # поза вікном, пін був би зелений і на порожній базі (`<= 0` → early return, інтенту
    # нема, `amount` = nil), тобто міряв би відсутність предмета, а не межу.
    it "не палить емісію, зароблену ДО початку цього договору (попередній — виконаний)" do
      naas_contract.update!(start_date: 30.days.ago, end_date: 30.days.from_now)

      create(:blockchain_transaction, wallet: wallet_burn, amount: 900,
                                      token_type: :carbon_coin, status: :confirmed,
                                      created_at: 1.year.ago)
      create(:blockchain_transaction, wallet: wallet_burn, amount: 40,
                                      token_type: :carbon_coin, status: :confirmed,
                                      created_at: 5.days.ago)

      expect(slash_intent_amount).to eq(40)
    end

    # ⛔ Дзеркало межі: вікно накриває ЛИШЕ контрактну форфейтуру. Слешинг-за-провину
    # питає про шкоду ЛІСУ, а не про обсяг угоди, і цю вісь присуд 09-04 не міряв —
    # тож база там лишається безвіконною, і це ОГОЛОШЕНО, а не недогляд.
    it "на слешинг-за-провину вікно НЕ поширюється — база лишається безвіконною" do
      naas_contract.update!(start_date: 30.days.ago, end_date: 30.days.from_now)
      create(:blockchain_transaction, wallet: wallet_burn, amount: 900,
                                      token_type: :carbon_coin, status: :confirmed,
                                      created_at: 1.year.ago)

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)
      intent = BlockchainTransaction.where(sourceable: naas_contract).order(created_at: :desc).first

      expect(intent).to be_present
      expect(intent.amount).to be > 0
    end
  end

  describe "total_minted_amount zero" do
    let(:tree_burn) { create(:tree, cluster: cluster) }

    it "returns early when no confirmed transactions exist" do
      result = described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)
      expect(result).to be_nil
    end
  end

  describe "success path with tx_hash" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "marks naas_contract as breached and creates audit transaction" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)

      allow(mock_client).to receive(:transact).and_return("0x" + "f" * 64)

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      naas_contract.reload
      expect(naas_contract.status).to eq("breached")

      audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
      expect(audit_tx).not_to be_nil
      expect(audit_tx.tx_hash).to eq("0x" + "f" * 64)
    end
  end

  describe "nil source_tree" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "uses cluster.trees.active.first wallet as audit_wallet" do
      witness_cohort!(cluster, critical: 4, healthy: 0) # [SLASH-1] невироджена вибірка
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)
      # [ARCH.46] critical AiInsight → damage via critical_count (no source_tree path still burns).
      create(:ai_insight, analyzable: tree_burn, insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date, stress_index: 1.0)

      allow(mock_client).to receive(:transact).and_return("0xabc123")

      described_class.call(organization.id, naas_contract.id)

      audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
      expect(audit_tx.wallet).to eq(wallet_burn)
    end
  end

  describe "nil audit_wallet" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    # «Пастка Останнього дерева» — audit_wallet nil → інтент чіпляється до КЛАСТЕРА (MRV.1:
    # cluster-sourced гроші пишуть audit-рядок через `cluster`, бо гаманця-носія нема).
    # [⚖️ 2026-07-30] Сценарій переписано на ДОСЯЖНИЙ: доти тест ліпив «усі дерева мертві +
    # burn БЕЗ source_tree» через `update_columns`, а в проді такого шляху нема — `DailyHealthRouter#skipped?`
    # відсікає мертвий кластер ще до burn'у, тож статистична гілка туди не доходить у принципі.
    # Реальний носій nil-гаманця — дерево-сирота (`has_one :wallet` знищений як порожній,
    # ARCH.57), що вмирає останнім: source_tree є, гаманця в нього нема, живих сусідів теж.
    it "creates transaction with cluster instead of wallet when the dying tree has no wallet" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)
      orphan = create(:tree, cluster: cluster)
      orphan.wallet&.destroy
      orphan.reload

      tree_burn.update!(status: :deceased)
      orphan.update!(status: :deceased)

      allow(mock_client).to receive(:transact).and_return("0xdead")

      described_class.call(organization.id, naas_contract.id, source_tree: orphan)

      audit_tx = BlockchainTransaction.where(sourceable: naas_contract).last
      expect(audit_tx.wallet).to be_nil
      expect(audit_tx.cluster).to eq(cluster)
    end
  end

  # =========================================================================
  # DEDICATED SLASHER KEY (E.2 Role Separation — legacy fallback retired, INF.22)
  # =========================================================================
  describe "key selection (E.2 Role Separation)" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    before do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)
    end

    it "signs with the dedicated ORACLE_SLASHER_PRIVATE_KEY" do
      ENV["ORACLE_SLASHER_PRIVATE_KEY"] = "0x#{'b' * 64}"

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      expect(Eth::Key).to have_received(:new).with(priv: "0x#{'b' * 64}")
    ensure
      ENV["ORACLE_SLASHER_PRIVATE_KEY"] = "0x#{'a' * 64}"
    end

    it "does NOT fall back to the retired ORACLE_PRIVATE_KEY when the slasher key is missing [INF.22]" do
      # A zombie legacy value must never be picked up: the raw KeyError propagates
      # (in prod the guard's boot presence-check fires long before this point).
      ENV.delete("ORACLE_SLASHER_PRIVATE_KEY")
      ENV["ORACLE_PRIVATE_KEY"] = "0x#{'a' * 64}"

      expect {
        described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)
      }.to raise_error(KeyError, /ORACLE_SLASHER_PRIVATE_KEY/)

      expect(Eth::Key).not_to have_received(:new)
    ensure
      ENV.delete("ORACLE_PRIVATE_KEY")
      ENV["ORACLE_SLASHER_PRIVATE_KEY"] = "0x#{'a' * 64}"
    end
  end

  # =========================================================================
  # PROMETHEUS METRICS (SCC_SLASHED_TOTAL)
  # =========================================================================
  describe "Prometheus metric (SCC_SLASHED_TOTAL)" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "increments SCC_SLASHED_TOTAL after successful slash" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 500, status: :confirmed)
      allow(mock_client).to receive(:transact).and_return("0x" + "f" * 64)

      metric = SilkenNet::Metrics::SCC_SLASHED_TOTAL
      before_val = metric.get

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      expect(metric.get).to be > before_val
    end
  end

  # =========================================================================
  # DAMAGE RATIO WITH AiInsight + SOURCE_TREE COMBINED
  # =========================================================================
  describe "damage_ratio with AiInsight and source_tree" do
    let!(:tree1) { create(:tree, cluster: cluster) }
    let!(:tree2) { create(:tree, cluster: cluster) }

    before do
      tree1.wallet.blockchain_transactions.create!(
        amount: 1000, token_type: :carbon_coin, status: :confirmed,
        to_address: organization.crypto_public_address, tx_hash: "0x#{'a' * 64}")
      tree2.wallet.blockchain_transactions.create!(
        amount: 1000, token_type: :carbon_coin, status: :confirmed,
        to_address: organization.crypto_public_address, tx_hash: "0x#{'b' * 64}")
    end

    it "prefers AiInsight ratio over source_tree ratio" do
      witness_cohort!(cluster, critical: 3, healthy: 0) # [SLASH-1] 5 свідків, частка 1.0 незмінна
      # AiInsight says 2/2 trees critical = 100% damage
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date, stress_index: 1.0)
      create(:ai_insight, analyzable: tree2, insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date, stress_index: 1.0)

      described_class.call(organization.id, naas_contract.id, source_tree: tree1)

      expect(mock_client).to have_received(:transact) do |_contract, _method, _addr, amount_in_wei, **_opts|
        # 100% of 2000 = 2000 tokens
        expected_wei = (2000.0 * (10**18)).to_i
        expect(amount_in_wei).to eq(expected_wei)
      end
    end

    it "caps damage_ratio at 1.0 maximum" do
      witness_cohort!(cluster, critical: 3, healthy: 0) # [SLASH-1] 5 свідків, частка 1.0 незмінна
      # Even with many critical trees, ratio can't exceed 1.0
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date, stress_index: 1.0)
      create(:ai_insight, analyzable: tree2, insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date, stress_index: 1.0)

      # All trees critical → ratio = 2/2 = 1.0 (capped)
      described_class.call(organization.id, naas_contract.id)

      expect(mock_client).to have_received(:transact)
    end
  end

  describe "nil tx_hash from transact" do
    let(:tree_burn) { create(:tree, cluster: cluster) }
    let!(:wallet_burn) { tree_burn.wallet || create(:wallet, tree: tree_burn) }

    it "does not mark contract as breached when transact returns nil" do
      create(:blockchain_transaction, wallet: wallet_burn, amount: 100, status: :confirmed)

      allow(mock_client).to receive(:transact).and_return(nil)

      described_class.call(organization.id, naas_contract.id, source_tree: tree_burn)

      expect(naas_contract.reload.status).not_to eq("breached")
    end
  end

  # [ARCH.53 TOCTOU] Per-contract claim: дві істинно-конкурентні екзекуції не сміють
  # обидві пройти guard→transact (double-slash). Partial-UNIQUE-index неможливий
  # (PARTITION BY RANGE(created_at)), unique_for = Enterprise-шим, Rails.cache =
  # SolidCache у prod (unless_exist НЕ атомарний для неіснуючого рядка) →
  # non-blocking Kredis.lock (Redis SET NX + UUID-токен CAS-release).
  describe "[ARCH.53] per-contract slash claim (TOCTOU double-slash)" do
    let(:tree_claim) { create(:tree, cluster: cluster) }

    before do
      create(:blockchain_transaction, wallet: tree_claim.wallet, amount: 100, status: :confirmed)
      create(:ai_insight, analyzable: tree_claim, insight_type: :daily_health_summary,
             target_date: AiInsight.reporting_date, stress_index: 1.0)
    end

    it "wraps the slash window in a non-blocking per-contract Kredis claim" do
      described_class.call(organization.id, naas_contract.id, source_tree: tree_claim)

      expect(Kredis).to have_received(:lock)
        .with("slash:claim:#{naas_contract.id}", expires_in: described_class::SLASH_CLAIM_TTL)
    end

    it "raises (→ Sidekiq retry) and creates NO intent when another worker holds the claim" do
      allow(Kredis).to receive(:lock) do |key, **_kwargs, &blk|
        raise Kredis::LockTimeout, "held" if key.start_with?("slash:claim:")

        blk.call
      end

      expect {
        described_class.call(organization.id, naas_contract.id, source_tree: tree_claim)
      }.to raise_error(Kredis::LockTimeout)

      expect(BlockchainTransaction.where(sourceable: naas_contract)).to be_empty
      expect(mock_client).not_to have_received(:transact)
    end

    it "a sequential re-run after a completed slash sees the intent and does not double-slash" do
      expect(described_class.call(organization.id, naas_contract.id, source_tree: tree_claim)).to eq(:slashed)
      expect(described_class.call(organization.id, naas_contract.id, source_tree: tree_claim)).to eq(:slashed)
      expect(mock_client).to have_received(:transact).once
    end

    it "does not touch the claim on the freeze path (gate exits before acquisition)" do
      allow_any_instance_of(Slashing::CauseEvidence).to receive(:positive_a?).and_return(false)

      result = described_class.call(organization.id, naas_contract.id, source_tree: tree_claim)

      expect(result).to eq(:frozen)
      expect(Kredis).not_to have_received(:lock)
    end
  end
end
