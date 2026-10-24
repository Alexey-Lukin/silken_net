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

  # ⚖️ [FW.66 (Б) · S8] Кредит, чиє вікно несе CCM-рядок: лист v2 (сирий кадр ефіру), мітка
  # кредиту — найвища версія вікна; верифікатор судить форму v2, а підміна DID кадру дає САМЕ
  # повідомлення перевірки форми (CID перераховано — падати на ньому підміна не може).
  it "лист v2 у кредиті проходить верифікатор, а кадр чужого DID — ні" do
    create(:telemetry_log, :ccm_leaf, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    result = JSON.parse(JSON.generate(bundle))
    credit = result["credits"].first
    expect([ result["schema"], credit["lineage_version"] ]).to eq([ "silken.mrv.lineage.v2", 2 ])
    expect(credit["leaves"].first["payload"]["leaf_version"]).to eq(2)

    path = Rails.root.join("tmp/lineage_v2_spec_#{Process.pid}.json")
    verifier = Rails.root.join("scripts/verify_lineage_bundle.rb").to_s
    File.write(path, JSON.generate(result))
    out, status = Open3.capture2e(RbConfig.ruby, verifier, path.to_s)
    expect(status.success?).to be(true), "бандл із v2 мав пройти: #{out}"

    leaf = result["credits"][0]["leaves"][0]
    leaf["payload"]["raw_record"] = "ffffffff" + leaf["payload"]["raw_record"][8..]
    leaf["leaf_cid"] = Filecoin::CidGenerator.cidv1(leaf["payload"])
    File.write(path, JSON.generate(result))
    out, status = Open3.capture2e(RbConfig.ruby, verifier, path.to_s)
    expect(status.success?).to be(false)
    expect(out).to include("DID кадру SNET-FFFFFFFF")
  ensure
    FileUtils.rm_f(path) if path
  end

  def run_lineage_verifier(data)
    path = Rails.root.join("tmp/lineage_verify_spec_#{Process.pid}.json")
    File.write(path, JSON.generate(data))
    out, status = Open3.capture2e(RbConfig.ruby, Rails.root.join("scripts/verify_lineage_bundle.rb").to_s, path.to_s)
    [ status.success?, out ]
  ensure
    FileUtils.rm_f(path)
  end

  # 🔴 [ARCH.122, ⚖️ founder 2026-10-24] Ланцюг організації запечатано, навіть коли останньою
  # перед якорем писала ІНША організація: доти leaf0 ніс голову лише того, хто писав останнім.
  # Бандл несе шлях від голови до кореня голів і рядок агрегату — і верифікатор це перевіряє.
  it "seals the organization's AuditLog chain under its anchor even when another org wrote last" do
    # Стороння — ПЕРШОЮ: менший id ставить її голову перед нашою, тож печатка не може
    # випадково брати «перший лист» і влучати.
    stranger = create(:organization)
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    AuditLog.create!(user: create(:user, organization: organization), organization: organization, action: "own_row")
    AuditLog.create!(user: create(:user, organization: stranger), organization: stranger, action: "stranger_last")
    anchor = anchor_confirmed!
    own_head = AuditLog.where(organization: organization).order(id: :desc).pick(:chain_hash)

    data = JSON.parse(JSON.generate(bundle))
    seal = data["audit_chain_seals"].sole
    expect(seal).to include("anchor_id" => anchor.id, "status" => "sealed", "chain_head" => own_head)

    ok, out = run_lineage_verifier(data)
    expect(ok).to be(true), out
    expect(out).to include("печатка ланцюга AuditLog")

    seal["chain_head"] = "f" * 64
    ok, out = run_lineage_verifier(data)
    expect(ok).to be(false)
    expect(out).to include("голова ланцюга не веде до кореня голів")
  end

  # Печатка мусить стояти на КОЖНОМУ якорі, на який спираються листи, і лише на них — інакше
  # емітент пропустив би її чи підклав чужу, а ✓ однаково обіцяв би «ланцюг запечатано».
  it "rejects a bundle whose anchor seal is missing, foreign or detached from its state_root" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    AuditLog.create!(user: create(:user, organization: organization), organization: organization, action: "own_row")
    anchor_confirmed!
    good = JSON.parse(JSON.generate(bundle))

    missing = good.merge("audit_chain_seals" => [])
    expect(run_lineage_verifier(missing)).to match([ false, /печатки ланцюга в бандлі немає/ ])

    foreign = JSON.parse(JSON.generate(good))
    foreign["audit_chain_seals"][0]["organization_id"] = organization.id + 1
    expect(run_lineage_verifier(foreign)).to match([ false, /печатка іншої організації/ ])

    detached = JSON.parse(JSON.generate(good))
    detached["audit_chain_seals"][0]["tier2_path"] = []
    expect(run_lineage_verifier(detached)).to match([ false, /рядок агрегату не веде до state_root/ ])
  end

  it "мітка кредиту й схема бандла звіряються з листям, а не довіряються емітенту" do
    create(:telemetry_log, :ccm_leaf, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    clean = JSON.parse(JSON.generate(bundle))

    labelled = JSON.parse(JSON.generate(clean)).tap { |b| b["credits"][0]["lineage_version"] = 1 }
    expect(run_lineage_verifier(labelled)).to match([ false, a_string_including("lineage_version 1 ≠ найвища версія") ])
    old_schema = clean.merge("schema" => "silken.mrv.lineage.v1")
    expect(run_lineage_verifier(old_schema)).to match([ false, a_string_including("схема silken.mrv.lineage.v1 не відповідає") ])
    # «unsealed» з коренем минав би і mint-root, і мітку версії — тож мітка seal теж судиться
    relabelled = JSON.parse(JSON.generate(clean)).tap { |b| b["credits"][0]["seal"] = "unsealed" }
    expect(run_lineage_verifier(relabelled)).to match([ false, a_string_including("мітка seal \"unsealed\" розходиться") ])
  end

  # Спільний лист у кількох кредитах — легальний (той самий CID); той самий запис чи кадр під
  # ІНШИМ листом, лист двічі в кредиті й мітки «вгору» на v1-листі — ні.
  it "розводить легальний спільний лист і підміни запису, кадру та міток" do
    create(:telemetry_log, :ccm_leaf, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    clean = JSON.parse(JSON.generate(bundle))
    # другий, незапечатаний кредит, що успадкував той самий лист
    shared = lambda do |b|
      copy = JSON.parse(JSON.generate(b["credits"][0]))
      copy["tx"]["id"] = 999_999
      copy.merge!("telemetry_merkle_root" => nil, "seal" => "unsealed", "lineage_version" => nil)
      copy["leaves"].each { |l| l["window_source"] = nil }
      b["credits"] << copy
      b
    end

    expect(run_lineage_verifier(shared.call(JSON.parse(JSON.generate(clean))))).to match([ true, anything ])

    other = shared.call(JSON.parse(JSON.generate(clean)))
    leaf = other["credits"][1]["leaves"][0]
    leaf["payload"]["raw_record"] = leaf["payload"]["raw_record"][0, 8] + "00" * 26
    leaf["leaf_cid"] = Filecoin::CidGenerator.cidv1(leaf["payload"])
    expect(run_lineage_verifier(other)).to match([ false, a_string_including("той самий запис стоїть під іншим листом") ])

    reframed = shared.call(JSON.parse(JSON.generate(clean)))
    leaf = reframed["credits"][1]["leaves"][0]
    leaf["payload"]["telemetry_log_id"] = leaf["telemetry_log_id"] = 424_242
    leaf["leaf_cid"] = Filecoin::CidGenerator.cidv1(leaf["payload"])
    expect(run_lineage_verifier(reframed)).to match([ false, a_string_including("сирий кадр уже стоїть під іншим листом") ])

    doubled = JSON.parse(JSON.generate(clean)).tap { |b| b["credits"][0]["leaves"] *= 2 }
    expect(run_lineage_verifier(doubled)).to match([ false, a_string_including("лист повторюється в межах кредиту") ])
  end

  # ⚖️ [FW.66 (Б) · S8b — ратифіковано 2026-10-11] Бандл несе підписані конверти, на які посилається
  # v2-листя, і запис реєстрації ключа Королеви. Ланцюг тут справжній: ключ зареєстровано ДО прийому,
  # конверт підписано OpenSSL (незалежно від серверного будівника), рядок посилається на збережений.
  describe "конверти QATT у бандлі [S8b]" do
    let(:gateway) { create(:gateway, cluster: cluster) }
    let(:queen_key) { OpenSSL::PKey.generate_key("ED25519") }
    let(:envelope) do
      # IV + шифртекст на один 31-байтний CCM-запис (вирівняний до 32): місткість конверта — один лист
      body = [ 0x02, 1_750_000_000, 7 ].pack("CNN") + ("\x00" * 8) + Random.bytes(16 + 32)
      body + queen_key.sign(nil, "SLKN-QATT2".b + [ gateway.uid.bytesize ].pack("C") + gateway.uid.b + body)
    end

    let(:operator) { create(:user, organization: organization) }
    let(:hw_key) { create(:hardware_key, device_uid: gateway.uid) }

    def envelope_bundle(growth_points: 38, register: true, leaves: 1)
      if register
        travel_to(3.hours.ago) { hw_key.register_attestation_key!(queen_key.raw_public_key.unpack1("H*"), user_id: operator.id) }
      else
        hw_key.update!(ed25519_public_key_hex: queen_key.raw_public_key.unpack1("H*"))
      end
      sha = QattEnvelope.record!(envelope: envelope, gateway: gateway, public_key_hex: hw_key.reload.ed25519_public_key_hex,
                                 received_at: 150.minutes.ago)
      leaves.times do
        create(:telemetry_log, :ccm_leaf, tree: tree, created_at: 2.hours.ago, qatt_envelope_sha256: sha,
                                          ema_delta_t_s: 3600, growth_points: growth_points)
      end
      mint_confirmed!
      anchor_confirmed!
      JSON.parse(JSON.generate(bundle))
    end

    def releafed(data)
      leaf = data["credits"][0]["leaves"][0]
      yield leaf["payload"]
      leaf["leaf_cid"] = Filecoin::CidGenerator.cidv1(leaf["payload"])
      data["credits"][0]["telemetry_merkle_root"] = MerkleTree.root([ leaf["leaf_cid"] ])
      data
    end

    it "несе конверт із записом реєстрації ключа, і верифікатор перевіряє підпис" do
      data = envelope_bundle
      entry = data["qatt_envelopes"].sole

      expect(entry).to include("gateway_uid" => gateway.uid, "envelope" => envelope.unpack1("H*"))
      expect(entry["key_registration"]).to include("public_key_hex" => entry["public_key_hex"])
      expect(run_lineage_verifier(data)).to match([ true, a_string_including("конвертів=1", "підписи конвертів QATT") ])
    end

    it "утримані бали рахуються, а не падають; третє значення балів — підробка листа" do
      expect(run_lineage_verifier(envelope_bundle(growth_points: 0))).to match([ true, a_string_including("бали утримано=1") ])

      forged = releafed(JSON.parse(JSON.generate(bundle))) { |payload| payload["growth_points"] = 40 }
      expect(run_lineage_verifier(forged)).to match([ false, a_string_including("growth_points 40 ∉ {0, 38}") ])
    end

    it "байт конверта, підставлений разом із хешем, ламає підпис Королеви" do
      data = envelope_bundle
      entry = data["qatt_envelopes"].sole
      bytes = [ entry["envelope"] ].pack("H*").tap { |b| b.setbyte(20, b.getbyte(20) ^ 0x01) }
      entry["envelope"] = bytes.unpack1("H*")
      entry["sha256"] = Digest::SHA256.hexdigest(bytes)

      expect(run_lineage_verifier(data)).to match([ false, a_string_including("не сходиться") ])
    end

    it "конверт, якого бракує, і конверт, на який ніхто не посилається, — відмова" do
      data = envelope_bundle
      missing = JSON.parse(JSON.generate(data)).tap { |b| b["qatt_envelopes"] = [] }
      stray = JSON.parse(JSON.generate(data)).tap { |b| b["qatt_envelopes"] << b["qatt_envelopes"].first.merge("sha256" => "ff" * 32) }

      expect(run_lineage_verifier(missing)).to match([ false, a_string_including("якого бандл не несе") ])
      expect(run_lineage_verifier(stray)).to match([ false, a_string_including("не посилається жоден лист") ])
    end

    # Дати судить час, запечатаний у листі: `received_at` і дата запису реєстрації — твердження емітента.
    it "реєстрація ключа чи прийом, заявлені ПІЗНІШЕ за найраніший лист, — відмова" do
      data = envelope_bundle
      late_key = JSON.parse(JSON.generate(data)).tap { |b| b["qatt_envelopes"].sole["key_registration"]["created_at"] = 1.minute.ago.utc.iso8601(6) }
      late_receipt = JSON.parse(JSON.generate(data)).tap { |b| b["qatt_envelopes"].sole["received_at"] = 1.minute.ago.utc.iso8601(6) }

      expect(run_lineage_verifier(late_key)).to match([ false, a_string_including("ключ зареєстровано ПІЗНІШЕ за найраніший лист") ])
      expect(run_lineage_verifier(late_receipt)).to match([ false, a_string_including("прийом заявлено ПІЗНІШЕ") ])
    end

    # Вибір за датою без ключа взяв би запис іншого ключа, зареєстрованого пізніше, — вічна хибна відмова.
    it "бере запис реєстрації САМЕ ключа, що перевірив конверт, а не останній за датою" do
      data = envelope_bundle
      travel_to(170.minutes.ago) { hw_key.register_attestation_key!("cd" * 32, user_id: operator.id) }

      entry = JSON.parse(JSON.generate(bundle))["qatt_envelopes"].sole
      expect(entry["key_registration"]["public_key_hex"]).to eq(data["qatt_envelopes"].sole["public_key_hex"])
    end

    it "листів на конверт більше, ніж CCM-записів уміщає його шифртекст, — відмова" do
      expect(run_lineage_verifier(envelope_bundle(leaves: 2))).to match([ false, a_string_including("несе щонайбільше 1 CCM-записів, а листів на нього 2") ])
    end

    it "конверт без запису реєстрації проходить, але ✓ не обіцяє дати ключа" do
      expect(run_lineage_verifier(envelope_bundle(register: false)))
        .to match([ true, a_string_including("лише самоузгодженість", "без дати реєстрації ключа)") ])
    end

    it "битий запис секції — відмова з причиною, а не виняток" do
      data = envelope_bundle.tap { |b| b["qatt_envelopes"] << nil }

      expect(run_lineage_verifier(data)).to match([ false, a_string_including("qatt_envelopes[1] не є обʼєктом JSON") ])
    end
  end

  it "мітки «вгору» на v1-листі — схема v2 і lineage_version 2 без жодного v2-листа — відмова" do
    create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
    mint_confirmed!
    anchor_confirmed!
    clean = JSON.parse(JSON.generate(bundle))

    expect(clean["schema"]).to eq("silken.mrv.lineage.v1")
    expect(run_lineage_verifier(clean.merge("schema" => "silken.mrv.lineage.v2")))
      .to match([ false, a_string_including("схема silken.mrv.lineage.v2 не відповідає") ])
    up = JSON.parse(JSON.generate(clean)).tap { |b| b["credits"][0]["lineage_version"] = 2 }
    expect(run_lineage_verifier(up)).to match([ false, a_string_including("lineage_version 2 ≠ найвища версія") ])
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
