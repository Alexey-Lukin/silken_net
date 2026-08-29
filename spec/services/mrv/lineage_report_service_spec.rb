# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "open3"

RSpec.describe Mrv::LineageReportService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) do
    w = tree.wallet
    w.update!(balance: 5000)
    allow(w.tree).to receive(:active?).and_return(true)
    w
  end

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    silence_broadcasts!(:wallet_balance, :tree_map)
  end

  def mint_confirmed!(points = 500)
    tx = wallet.reload.lock_and_mint!(points, 100)
    tx.process!
    tx.mark_as_sent!("0x#{SecureRandom.hex(32)}")
    tx.confirm!(12_345, 0.01)
    tx.reload
  end

  def anchor_confirmed!
    root_data = Ethereum::StateAnchorService.new.generate_state_root
    EthereumAnchor.create!(
      root_data.merge(status: :confirmed, tx_hash: "0x#{SecureRandom.hex(32)}", block_number: 1)
    )
  end

  # Реальний писач страхової виплати: `InsurancePayoutWorker` кличе
  # `create_blockchain_transaction!` БЕЗ `direction:`, тож напрямок дає DB-default
  # `'mint'` — і саме тому виплата проходила фільтр `credits:` [ARCH.95] наскрізь.
  # Пін мусить іти ЦИМ шляхом, а не власноруч зібраним рядком: інакше він пінує
  # мою гіпотезу про писача, а не писача.
  def insurance_payout_confirmed!(amount: 100.0)
    insurance = create(:parametric_insurance, :triggered, organization: organization, cluster: cluster)
    tx = insurance.create_blockchain_transaction!(
      wallet: wallet, amount: amount, token_type: :carbon_coin,
      to_address: "0x#{SecureRandom.hex(20)}", status: :pending
    )
    tx.process!
    tx.mark_as_sent!("0x#{SecureRandom.hex(32)}")
    tx.confirm!(12_347, 0.01)
    tx.reload
  end

  def bundle
    described_class.call(organization: organization, from: 1.day.ago, to: 1.minute.from_now)
  end

  it "builds a self-contained bundle whose proofs the OFFLINE verifier accepts; tamper → exit 1" do
    log = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    tx = mint_confirmed!
    anchor = anchor_confirmed!

    result = bundle
    expect(result[:credits].size).to eq(1)
    credit = result[:credits].first
    expect(credit[:tx][:id]).to eq(tx.id)
    expect(credit[:seal]).to eq("sealed")
    expect(credit[:telemetry_merkle_root]).to eq(MerkleTree.root([ Mrv::TelemetryLeaf.cid_for(log) ]))

    leaf = credit[:leaves].first
    expect(leaf[:telemetry_log_id]).to eq(log.id)
    expect(leaf[:anchor_proof][:status]).to eq("anchored")
    expect(leaf[:anchor_proof][:anchor][:state_root]).to eq(anchor.state_root)

    path = Rails.root.join("tmp/lineage_bundle_spec_#{Process.pid}.json")
    File.write(path, JSON.generate(result))
    verifier = Rails.root.join("scripts/verify_lineage_bundle.rb").to_s
    expect(system(RbConfig.ruby, verifier, path.to_s, out: File::NULL)).to be(true), "верифікатор мав пройти"
  ensure
    FileUtils.rm_f(path) if path
  end

  it "офлайн-верифікатор валить кожен tamper-клас: payload · mint-root · dup-key" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    result = bundle
    path = Rails.root.join("tmp/lineage_tamper_spec_#{Process.pid}.json")
    verifier = Rails.root.join("scripts/verify_lineage_bundle.rb").to_s

    tampered = JSON.parse(JSON.generate(result))
    tampered["credits"][0]["leaves"][0]["payload"]["z_value"] = "999.99"
    File.write(path, JSON.generate(tampered))
    expect(system(RbConfig.ruby, verifier, path.to_s, out: File::NULL)).to be(false), "payload-tamper мав дати exit 1"

    # Пін mint-root НЕ-вакуумний (fable №2): тамперимо ЛИШЕ root на ЧИСТОМУ bundle
    # і assert'имо САМЕ mint-root-помилку — видалення check'а з верифікатора = RED.
    clean = JSON.parse(JSON.generate(result))
    clean["credits"][0]["telemetry_merkle_root"] = "ff" * 32
    File.write(path, JSON.generate(clean))
    out, status = Open3.capture2e(RbConfig.ruby, verifier, path.to_s)
    expect(status.success?).to be(false), "root-tamper мав дати exit 1"
    expect(out).to include("mint-root mismatch")

    # Dup-key smuggling (fable №2: json ≥ 2.20 дедуплікує ДО object_class —
    # захист двошаровий, пін ловить регресію на будь-якій версії json)
    dup_json = JSON.generate(JSON.parse(JSON.generate(result)))
                   .sub('"telemetry_merkle_root":', "\"telemetry_merkle_root\":\"#{'aa' * 32}\",\"telemetry_merkle_root\":")
    File.write(path, dup_json)
    out, status = Open3.capture2e(RbConfig.ruby, verifier, path.to_s)
    expect(status.success?).to be(false), "dup-key мав дати відхилення"
    expect(out).to include("duplicate")
  ensure
    FileUtils.rm_f(path) if path
  end

  it "marks leaves newer than the last confirmed anchor as pending_anchor (чесно, не фейл)" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!

    leaf = bundle[:credits].first[:leaves].first
    expect(leaf[:anchor_proof]).to eq({ status: "pending_anchor" })
  end

  it "scopes credits to the given organization only (IDOR)" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    stranger = create(:organization)

    result = described_class.call(organization: stranger, from: 1.day.ago, to: 1.minute.from_now)
    expect(result[:credits]).to be_empty
  end

  # 🔴 [ARCH.101 → ARCH.95] Пара «своє лишається ⊥ своє відпадає», і ОБИДВА боки свої: чужа
  # організація довела б тенант-скоуп (сусідній приклад це вже робить), а не напрямок.
  # Форма спалення взята з реального писача — `BlockchainBurningService#create_slash_intent!`
  # кладе `sourceable: naas_contract`, `direction: :burn`, `token_type: :carbon_coin` і
  # ДОДАТНУ суму, — а стан проганяється тим самим AASM, бо загроза реалізується лише на
  # `:confirmed`. ⚠️ Назва прикладу казала «напрямок ДЕРИВУЄТЬСЯ» — після ARCH.95 це
  # неправда: він ОГОЛОШУЄТЬСЯ, і саме тому ESG-погашення (яке `sourceable` не має)
  # більше не проскакує в credits емісією.
  it "тримає мінт у credits і НЕ пускає туди спалення — напрямок оголошено, не читається зі знака" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint = mint_confirmed!

    contract = create(:naas_contract, cluster: cluster)
    slash = BlockchainTransaction.create!(
      wallet: wallet, sourceable: contract, to_address: "0x#{SecureRandom.hex(20)}",
      amount: 3.0, token_type: :carbon_coin, status: :pending, direction: :burn
    )
    slash.process!
    slash.mark_as_sent!("0x#{SecureRandom.hex(32)}")
    slash.confirm!(12_346, 0.01)

    ids = bundle[:credits].map { |c| c.dig(:tx, :id) }

    # ⊥ Позитивна половина несуча окремо: мінт має `sourceable_type IS NULL`, тож
    # наївний `where.not(sourceable_type: …)` викинув би САМЕ його — тобто зникнення
    # спалення без цього рядка не відрізнити від зникнення всього бандла.
    expect(ids).to include(mint.id)
    expect(ids).not_to include(slash.id)
    expect(slash.reload).to be_burn
  end

  it "inherits failed-attempt windows into the next successful credit (чесна межа (г))" do
    old_log = create(:telemetry_log, tree: tree, created_at: 3.hours.ago)
    failed_tx = wallet.lock_and_mint!(300, 100)
    failed_tx.fail!("rpc down")
    new_log = create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
    tx = mint_confirmed!(600)

    credit = bundle[:credits].find { |c| c[:tx][:id] == tx.id }
    expect(credit[:inherited_windows].map { |w| w[:tx_id] }).to eq([ failed_tx.id ])
    own = credit[:leaves].select { |l| l[:window_source] == tx.id }.map { |l| l[:telemetry_log_id] }
    inherited = credit[:leaves].select { |l| l[:window_source].nil? }.map { |l| l[:telemetry_log_id] }
    expect(own).to eq([ new_log.id ])
    expect(inherited).to eq([ old_log.id ])
  end

  it "marks unprovable_regrouped when the anchor has no subtree entry for the tree's current cluster" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    tree.update!(cluster: create(:cluster, organization: organization))

    leaf = bundle[:credits].first[:leaves].first
    expect(leaf[:anchor_proof][:status]).to eq("unprovable_regrouped")
  end

  # [ARCH.70 ⚖️ 2026-08-29] Цей приклад ЗАВЖДИ описував integrity-розбіжність — сама
  # його назва казала «subroot mismatch», — але очікував статус про перегрупування,
  # бо власного імені для третього стану не існувало. Тепер очікує своє.
  it "reports subroot_diverged when the cluster subroot no longer matches the anchor" do
    other_tree = create(:tree, cluster: create(:cluster, organization: organization))
    create(:telemetry_log, tree: other_tree, created_at: 2.hours.ago)
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    tree.update!(cluster: other_tree.cluster) # entry існує, але recompute ≠ stored

    leaf = bundle[:credits].first[:leaves].first
    expect(leaf[:anchor_proof][:status]).to eq("subroot_diverged")
    # Негативна половина: розбіжність складу більше НЕ рапортується аудиторові
    # як «дерево змінило кластер» — ми віддаємо НАСЛІДОК, бо причини не знаємо.
    expect(leaf[:anchor_proof][:status]).not_to eq("unprovable_regrouped")
  end

  it "serializes an empty-window credit honestly (unsealed, nil window bounds)" do
    tx = mint_confirmed! # жодного лога → window_upper nil

    credit = bundle[:credits].find { |c| c[:tx][:id] == tx.id }
    expect(credit[:seal]).to eq("unsealed")
    expect(credit[:window]).to eq({ from_at: nil, from_id: nil, to_at: nil, to_id: nil })
    expect(credit[:leaves]).to be_empty
  end

  it "inherits only failed attempts AFTER the previous confirmed mint" do
    create(:telemetry_log, tree: tree, created_at: 4.hours.ago)
    mint_confirmed! # перший confirmed — його вікно спожито
    failed_between = wallet.reload.lock_and_mint!(300, 100)
    failed_between.fail!("boom")
    create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
    tx2 = mint_confirmed!(600)

    credit = bundle[:credits].find { |c| c[:tx][:id] == tx2.id }
    expect(credit[:inherited_windows].map { |w| w[:tx_id] }).to eq([ failed_between.id ])
  end

  it "proves against a second anchor whose window chains from the first (window_from present)" do
    create(:telemetry_log, tree: tree, created_at: 3.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    # created_at МУСИТЬ бути > anchor1.window_to (= now−GRACE): у проді created_at
    # ставиться при INSERT, тож рядок не може «просочитись» у вже-заякорене вікно.
    late_log = create(:telemetry_log, tree: tree, created_at: 2.minutes.ago)
    travel_to(1.hour.from_now) do
      tx2 = mint_confirmed!(600)
      anchor2 = anchor_confirmed!
      expect(anchor2.window_from).to be_present

      credit = bundle[:credits].find { |c| c[:tx][:id] == tx2.id }
      leaf = credit[:leaves].find { |l| l[:telemetry_log_id] == late_log.id }
      expect(leaf[:anchor_proof][:status]).to eq("anchored")
      expect(leaf[:anchor_proof][:anchor][:state_root]).to eq(anchor2.state_root)
    end
  end

  # 🔴 [DOC-T.89, ⚖️ 2026-08-26] Страхова виплата — емісія за ЗБИТОК, і в `credits:` їй
  # не місце: її вікно вимірів ПОРОЖНЄ за конструкцією, тож bundle стверджував би
  # виміряний ріст, якого не було (ISO 14064/Verra — це не незручність, а хибний клейм).
  # Дискримінатор — `sourceable_type`, бо напрямок тут ЧЕСНО `:mint`; пін тримає й це.
  it "не пускає страхову виплату в credits — вона їде окремою секцією з чесним «вимірів немає»" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    growth = mint_confirmed!
    payout = insurance_payout_confirmed!

    # ⊥ Несуче окремо: виплата — СПРАВЖНІЙ `direction: :mint`, тобто [ARCH.95]-фільтр її
    # НЕ ловить. Без цього рядка приклад не відрізняє «відсіяв sourceable» від
    # «відсіяв напрямок» — і зелень нічого не доводила б.
    expect(payout).to be_direction_mint

    result = bundle
    expect(result[:credits].map { |c| c.dig(:tx, :id) }).to eq([ growth.id ])

    payouts = result[:insurance_payouts]
    expect(payouts.map { |p| p.dig(:tx, :id) }).to eq([ payout.id ])
    expect(payouts.first[:lineage]).to eq("none_by_construction")
    expect(payouts.first[:on_chain_identifier_prefix]).to eq(BlockchainMintingService::INSURANCE_MINT_PREFIX)

    # ⊥ Секція мусить бути ВИДНОЮ в консолі аудитора, а не лише лежати у файлі: мовчазну
    # він прийме за перевірену. Тому пін іде через сам верифікатор — і тримає обидва
    # твердження: bundle із новим ключем усе ще exit 0, і виплати в звіті НАЗВАНІ.
    path = Rails.root.join("tmp/lineage_payout_spec_#{Process.pid}.json")
    File.write(path, JSON.generate(result))
    out, status = Open3.capture2e(RbConfig.ruby, Rails.root.join("scripts/verify_lineage_bundle.rb").to_s, path.to_s)
    expect(status.success?).to be(true), "верифікатор мав пройти з новою секцією: #{out}"
    expect(out).to include("insurance_payouts=1")
    expect(out).to include("НЕ вуглецеві")
  ensure
    FileUtils.rm_f(path) if path
  end

  # 🔴 [DOC-T.89] Друга половина ТОГО САМОГО предиката: `prev`-межа успадкування читала
  # «будь-який confirmed рядок гаманця», тож confirmed-виплата (або спалення) МІЖ
  # провалом і наступним кредитом обрізала успадкування — вікно вимірів, що доказує
  # кредит, тихо зникало з доказового bundle. Межа мусить бути тим самим «виміряним
  # кредитом», що й `credits:`, інакше фікс лишається половинчастим.
  it "не дає страховій виплаті обрізати успадкування failed-вікон (межа = виміряний кредит)" do
    old_log = create(:telemetry_log, tree: tree, created_at: 3.hours.ago)
    failed_tx = wallet.lock_and_mint!(300, 100)
    failed_tx.fail!("rpc down")

    insurance_payout_confirmed! # confirmed МІЖ провалом і наступним кредитом

    create(:telemetry_log, tree: tree, created_at: 1.hour.ago)
    tx = mint_confirmed!(600)

    credit = bundle[:credits].find { |c| c[:tx][:id] == tx.id }
    expect(credit[:inherited_windows].map { |w| w[:tx_id] }).to eq([ failed_tx.id ])
    inherited = credit[:leaves].select { |l| l[:window_source].nil? }.map { |l| l[:telemetry_log_id] }
    expect(inherited).to eq([ old_log.id ])
  end
end
