# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organization, type: :model do
  # [SEC.27] `logo` — єдине вкладення дерева з живим upload-шляхом
  # (`settings_controller` кладе `:logo` у `permit`), тож валідація тут не
  # гігієна, а межа довіри. Кожна вісь пінить ПАРУ «проходить ⊥ відпадає»:
  # приклад лише на успіху зелений і при знятій валідації.
  describe "logo attachment validation" do
    let(:organization) { create(:organization) }

    def attach_logo(content_type:, bytes: "x")
      organization.logo.attach(
        io: StringIO.new(bytes), filename: "logo", content_type: content_type
      )
    end

    it "accepts a web raster image" do
      attach_logo(content_type: "image/png")
      expect(organization).to be_valid
    end

    it "rejects a content type outside the allow-list" do
      attach_logo(content_type: "application/pdf")
      expect(organization).not_to be_valid
      expect(organization.errors[:logo]).to be_present
    end

    # SVG свідомо поза списком: Rails віддає його `attachment`, а не inline,
    # але allow-list лишається рівно растровим — вектор тут не потрібен.
    it "rejects SVG" do
      attach_logo(content_type: "image/svg+xml")
      expect(organization).not_to be_valid
    end

    it "rejects a file over the size ceiling" do
      attach_logo(content_type: "image/png", bytes: "x" * 6.megabytes)
      expect(organization).not_to be_valid
      expect(organization.errors[:logo]).to be_present
    end
  end

  describe "associations" do
    it "has gateways through clusters" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      gateway = create(:gateway, cluster: cluster)

      expect(organization.gateways).to include(gateway)
    end

    it "has wallets directly via organization_id (denormalized)" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      tree = create(:tree, cluster: cluster)
      wallet = tree.wallet

      expect(wallet.organization).to eq(organization)
      expect(organization.wallets).to include(wallet)
    end

    # [ARCH.57] Compliance-журнал переживає організацію (був delete_all —
    # знищення Org стирало integrity-chain).
    it "has audit_logs with restrict_with_error dependency strategy" do
      reflection = described_class.reflect_on_association(:audit_logs)
      expect(reflection.options[:dependent]).to eq(:restrict_with_error)
    end

    it "has wallets with nullify dependency strategy" do
      reflection = described_class.reflect_on_association(:wallets)
      expect(reflection.options[:dependent]).to eq(:nullify)
    end

    # [SEC.26 / ARCH.76] «Безкластерний запис не належить НІКОМУ» — це продуктовий
    # присуд (⚖️ 2026-07-30), а не властивість ActiveRecord: він тримається на тому,
    # що обидві асоціації йдуть `through: :clusters`, а не прямою колонкою. Доти
    # єдиними виконуваними твердженнями про це були приклади `TreePolicy::Scope` /
    # `EwsAlertPolicy::Scope`; політики знято як мертвий код, і присуд лишився б без
    # жодного сторожа. ⚠️ Сирота конструйована СЬОГОДНІ (`cluster_id` штатно nullable,
    # `AlertDispatchService` створює тривогу для безкластерного дерева), тож ці два
    # приклади не гіпотетичні — вони стережуть, щоб `OR cluster_id IS NULL` не
    # повернувся копі-пейстом у будь-який майбутній скоуп.
    # ⚠️ Позитивна половина в кожному прикладі обовʼязкова: без неї порожня асоціація
    # (напр. зламане `through:`) давала б зелений негатив, тобто пін не міг би впасти.
    it "не показує безкластерне дерево жодній організації" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      own = create(:tree, cluster: cluster)
      clusterless = create(:tree, cluster: nil)

      expect(organization.trees).to include(own)
      expect(organization.trees).not_to include(clusterless)
    end

    it "не показує безкластерну тривогу жодній організації" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      own = create(:ews_alert, cluster: cluster)
      clusterless = create(:ews_alert, cluster: nil)

      expect(organization.ews_alerts).to include(own)
      expect(organization.ews_alerts).not_to include(clusterless)
    end
  end

  describe "#total_carbon_points" do
    it "sums wallet balances via direct association" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      tree1 = create(:tree, cluster: cluster)
      tree2 = create(:tree, cluster: cluster)

      tree1.wallet.update!(balance: 100)
      tree2.wallet.update!(balance: 250)

      expect(organization.total_carbon_points).to eq(350)
    end
  end

  describe "#health_score" do
    # [ARCH.84] Доти: «returns 1.0 when organization has no clusters» — вигадане
    # ідеальне здоров'я на структурну порожнечу, тоді як та сама організація з
    # НЕВИМІРЯНИМИ кластерами діставала 0.0. Два вигадані числа, призначені навпаки.
    it "returns nil when there is nothing to measure, and says so through coverage" do
      org = create(:organization)

      expect(org.health_score).to be_nil
      expect(org.health_coverage).to be_no_clusters
    end

    it "distinguishes «nothing to measure» from «clusters exist but none measured»" do
      org = create(:organization)
      create(:cluster, organization: org)
      create(:cluster, organization: org)

      coverage = org.health_coverage

      expect(coverage.average).to be_nil
      expect(coverage).not_to be_no_clusters
      expect(coverage).to be_unmeasured
      expect(coverage.total).to eq(2)
    end

    it "reports partial coverage rather than passing a subset average off as the whole" do
      org = create(:organization)
      measured = create(:cluster, organization: org)
      create(:cluster, organization: org)
      measured.update_column(:health_index, 0.9)

      coverage = org.health_coverage

      expect(coverage.average).to eq(0.9)
      expect(coverage).to be_partial
      expect([ coverage.measured, coverage.total ]).to eq([ 1, 2 ])
    end

    it "calculates average of denormalized health_index" do
      organization = create(:organization)
      create(:cluster, organization: organization, health_index: 0.8)
      create(:cluster, organization: organization, health_index: 0.6)

      expect(organization.health_score).to eq(0.7)
    end
  end

  describe "#total_clusters" do
    it "returns the count of clusters" do
      organization = create(:organization)
      create_list(:cluster, 3, organization: organization)

      expect(organization.total_clusters).to eq(3)
    end

    it "returns 0 when organization has no clusters" do
      organization = create(:organization)
      expect(organization.total_clusters).to eq(0)
    end
  end

  describe "#total_contracted" do
    it "returns the sum of all contract funding" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      create(:naas_contract, organization: organization, cluster: cluster, total_funding: 30_000)
      create(:naas_contract, organization: organization, cluster: cluster, total_funding: 20_000)

      expect(organization.total_contracted).to eq(50_000.0)
    end

    it "returns 0.0 when no contracts exist" do
      organization = create(:organization)
      expect(organization.total_contracted).to eq(0.0)
    end
  end

  describe "#active_tokens_count" do
    it "returns the sum of total_funding for active contracts" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      create(:naas_contract, organization: organization, cluster: cluster, total_funding: 10_000, status: :active)
      create(:naas_contract, organization: organization, cluster: cluster, total_funding: 5_000, status: :active)
      create(:naas_contract, organization: organization, cluster: cluster, total_funding: 3_000, status: :draft)

      expect(organization.active_tokens_count).to eq(15_000)
    end

    it "returns 0 when no active contracts exist" do
      organization = create(:organization)
      expect(organization.active_tokens_count).to eq(0)
    end
  end

  describe "#under_threat?" do
    it "returns true when organization has unresolved critical alerts" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      create(:ews_alert, cluster: cluster, severity: :critical, status: :active, alert_type: :fire_detected)

      expect(organization).to be_under_threat
    end

    it "returns false when no critical alerts exist" do
      organization = create(:organization)
      expect(organization).not_to be_under_threat
    end
  end

  describe "validations" do
    it "requires name" do
      org = build(:organization, name: nil)
      expect(org).not_to be_valid
    end

    it "requires unique name" do
      create(:organization, name: "Unique Org")
      duplicate = build(:organization, name: "Unique Org")
      expect(duplicate).not_to be_valid
    end

    it "requires billing_email" do
      org = build(:organization, billing_email: nil)
      expect(org).not_to be_valid
    end

    it "validates billing_email format" do
      org = build(:organization, billing_email: "not-an-email")
      expect(org).not_to be_valid
    end

    it "requires crypto_public_address" do
      org = build(:organization, crypto_public_address: nil)
      expect(org).not_to be_valid
    end

    it "validates crypto_public_address format" do
      org = build(:organization, crypto_public_address: "not-a-wallet")
      expect(org).not_to be_valid
    end

    it "accepts valid Ethereum address with mixed case (EIP-55)" do
      org = build(:organization, crypto_public_address: "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B")
      expect(org).to be_valid
    end

    it "validates alert_threshold_critical_z must be positive" do
      org = build(:organization, alert_threshold_critical_z: -1)
      expect(org).not_to be_valid
    end

    it "validates alert_threshold_critical_z must be at most 10" do
      org = build(:organization, alert_threshold_critical_z: 11)
      expect(org).not_to be_valid
    end

    it "accepts valid alert_threshold_critical_z" do
      org = build(:organization, alert_threshold_critical_z: 3.5)
      expect(org).to be_valid
    end

    it "validates ai_sensitivity must be between 0 and 1" do
      org = build(:organization, ai_sensitivity: 1.5)
      expect(org).not_to be_valid
    end

    it "accepts valid ai_sensitivity" do
      org = build(:organization, ai_sensitivity: 0.85)
      expect(org).to be_valid
    end

    # --- Data Residency (Zone 4) ---
    it "accepts valid data_region" do
      Organization::SUPPORTED_DATA_REGIONS.each do |region|
        org = build(:organization, data_region: region)
        expect(org).to be_valid, "Expected #{region} to be valid"
      end
    end

    it "rejects invalid data_region" do
      org = build(:organization, data_region: "mars-north")
      expect(org).not_to be_valid
      expect(org.errors[:data_region]).to be_present
    end

    it "allows nil data_region" do
      org = build(:organization, data_region: nil)
      expect(org).to be_valid
    end

    it "defaults data_region to eu-west" do
      org = described_class.new
      expect(org.data_region).to eq("eu-west")
    end
  end

  # [UI.7] Форма налаштувань шле «не обрано» порожнім РЯДКОМ, а `allow_nil`
  # покриває лише `nil` — тож без нормалізації намір «скинути мову» був
  # невиразимий і давав 422 на кожному збереженні. Колонка — звичайний varchar,
  # тож касту blank→nil, який рятує сусідні enum/numeric-поля, тут не буває.
  describe "locale normalization" do
    it "перетворює порожній рядок на nil — «не обрано» мусить бути виразимим" do
      org = build(:organization, locale: "")

      expect(org.locale).to be_nil
      expect(org).to be_valid
    end

    it "лишає обрану локаль недоторканою" do
      expect(build(:organization, locale: "uk").locale).to eq("uk")
    end

    it "відхиляє локаль поза каталогом — нормалізація не є послабленням" do
      org = build(:organization, locale: "klingon")

      expect(org).not_to be_valid
      expect(org.errors[:locale]).to be_present
    end
  end

  describe "SUPPORTED_DATA_REGIONS" do
    it "contains five regions" do
      expect(Organization::SUPPORTED_DATA_REGIONS).to contain_exactly(
        "eu-west", "eu-central", "us-east", "us-west", "ap-southeast"
      )
    end
  end

  # [KYC.1] KYC чіпляється до адреси-бенефіціара — зміна адреси = ре-верифікація.
  describe "Hadron KYC lifecycle" do
    it "defaults to pending and validates the status set" do
      org = create(:organization)
      expect(org.hadron_kyc_status).to eq("pending")

      org.hadron_kyc_status = "weird"
      expect(org).not_to be_valid
    end

    it "enqueues verification on create (address bound at birth)" do
      expect {
        create(:organization)
      }.to change { HadronKycVerificationWorker.jobs.size }.by(1)
    end

    it "resets approved → pending and re-enqueues when the address changes" do
      org = create(:organization, hadron_kyc_status: "approved")

      expect {
        org.update!(crypto_public_address: "0x" + "e" * 40)
      }.to change { HadronKycVerificationWorker.jobs.size }.by(1)

      expect(org.reload.hadron_kyc_status).to eq("pending")
      expect(HadronKycVerificationWorker.jobs.last["args"]).to eq([ "Organization", org.id ])
    end

    it "keeps an explicitly-set status when address and status change together" do
      org = create(:organization)
      org.update!(crypto_public_address: "0x" + "f" * 40, hadron_kyc_status: "approved")

      expect(org.reload.hadron_kyc_status).to eq("approved")
    end
  end

  # [SEC.25 Ф3] Відкликання виданих імен стрімів. Форма — «покинути адресу», а не
  # «гейтити підписника»: клас каналу обирає клієнт, а `reject` тихий і
  # незворотний, тож обидві альтернативи били б лише по чесних (`04_04 §8.1`).
  describe "#rotate_stream_epoch! [SEC.25 Ф3]" do
    let(:org) { create(:organization) }

    # Ланцюг ARCH.57 вимагає актора; у ручної ops-дії людського ініціатора немає,
    # тож ним стає системний `oracle_executioner`. Без цього запису
    # `record_audit_trail!` WARN-скіпає — дію не валить, але й сліду не лишає.
    let!(:oracle) do
      create(:user, :super_admin, email_address: "oracle.executioner@system.silkennet.com",
                                  first_name: "Oracle", last_name: "Executioner")
    end

    before { allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_to) }

    it "advances the epoch and persists it" do
      expect { org.rotate_stream_epoch! }.to change { org.reload.stream_epoch }.by(1)
    end

    # 🔴 Несучий пін усієї фази, і саме напрямок тут головний. Tombstone мусить
    # летіти в адресу, яку ми ЩОЙНО ПОКИНУЛИ — там сидять відкриті сторінки. Постав
    # його в нову епоху, і сигнал піде в канал, на який ще ніхто не підписаний:
    # ротація стала б тихою, а кожен глядач — глухим до наступної навігації.
    it "pushes the tombstone into the OLD address, never the new one" do
      previous = org.stream_epoch
      org.rotate_stream_epoch!

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_to)
        .with("telemetry_stream_org_#{org.id}_e#{previous}")
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_refresh_to)
        .with("telemetry_stream_org_#{org.id}_e#{org.stream_epoch}")
    end

    # `:map` виключено СВІДОМО: `broadcast_refresh_to` туди вбив би Leaflet у
    # кожного чесного глядача дашборда (morph зносить дітей вузла, а
    # `disconnect()` не спрацьовує, бо сам вузол лишається — тобто мапа більше
    # не переініціалізується). Пін тримає саме виняток: якщо хтось «полагодить»
    # перелік, додавши `:map`, це почервоніє.
    it "never tombstones the map stream — morph would kill Leaflet for honest viewers" do
      previous = org.stream_epoch
      org.rotate_stream_epoch!

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_refresh_to)
        .with("geospatial_matrix_org_#{org.id}_e#{previous}")
    end

    it "leaves an audit trail of the revocation" do
      previous = org.stream_epoch

      expect { org.rotate_stream_epoch! }.to change { AuditLogWorker.jobs.size }.by(1)

      attrs = AuditLogWorker.jobs.last["args"].first
      expect(attrs["action"]).to eq("stream_epoch_rotated")
      expect(attrs["organization_id"]).to eq(org.id)
      expect(attrs["metadata"]).to include("from" => previous, "to" => previous + 1)
    end

    # Tombstone доїжджає лише до ПІДКЛЮЧЕНИХ у ту мить сокетів — Solid Cable
    # ставить точку приєднання нової підписки на поточний максимум, тож backlog
    # не реплеїться. Вкладка, що спала під час bump'а, лишиться на мертвій адресі
    # й виглядатиме `connected`. Тому повторний поштовх — штатна дія оператора, і
    # вона мусить бути викликом, а не інструкцією в коментарі.
    it "can re-push a past epoch's tombstone without advancing the epoch again" do
      org.rotate_stream_epoch!
      previous = org.stream_epoch - 1

      expect { org.broadcast_stream_tombstone!(previous) }
        .not_to change { org.reload.stream_epoch }
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_to)
        .with("ews_alerts_org_#{org.id}_e#{previous}").twice
    end
  end
end
