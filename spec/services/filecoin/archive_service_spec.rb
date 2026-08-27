# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filecoin::ArchiveService do
  let(:user) { create(:user) }
  let(:audit_log) do
    # [SEC.18] Фікстура моделює РЕАЛЬНИЙ archive-шлях — money/MRV-лог від
    # `BlockchainTransaction#record_audit_trail`. Доти тут стояв `update_settings`
    # із фабричними `field/old_value/new_value`, тобто ops-лог, який `Auditable`
    # свідомо НЕ архівує (`archive: false`, INF.22): спека цементувала сценарій,
    # заборонений каноном, і сама ж робила його виглядом норми.
    create(:audit_log,
      user: user,
      action: "blockchain_tx_confirm",
      metadata: { from: "sent", to: "confirmed", token_type: "SCC", amount: "12.5", tx_hash: "0xabc123" }
    )
  end

  before do
    allow(Rails.application.credentials).to receive(:filecoin_api_key).and_return("test-api-key")
  end

  describe "#archive!" do
    context "when upload succeeds" do
      before { stub_pinata_success }

      it "uploads audit log data and saves CID" do
        cid = described_class.new(audit_log).archive!

        expect(cid).to eq("QmTestCid12345")
        expect(audit_log.reload.ipfs_cid).to eq("QmTestCid12345")
      end

      it "includes chain_hash and metadata in the payload" do
        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmTestCid12345" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content[:chain_hash]).to eq(audit_log.chain_hash)
        expect(content[:action]).to eq("blockchain_tx_confirm")
        expect(content[:metadata]).to eq(
          "from" => "sent", "to" => "confirmed",
          "token_type" => "SCC", "amount" => "12.5", "tx_hash" => "0xabc123"
        )
      end

      it "embeds a deterministic content_cid witness in the payload (E.60)" do
        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmTestCid12345" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content[:content_cid]).to start_with("bafkrei")
        expect(content[:content_cid]).to eq(
          described_class.content_cid(described_class.content_attrs(audit_log))
        )
      end

      it "includes telemetry_summary key in the payload" do
        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmTestCid12345" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content).to have_key(:telemetry_summary)
      end

      it "sends Bearer authorization header" do
        expected_auth = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_auth = kwargs[:headers]["Authorization"]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmTestCid12345" }.to_json)
        end

        described_class.new(audit_log).archive!

        expect(expected_auth).to eq("Bearer test-api-key")
      end
    end

    context "when audit log already has CID" do
      it "skips upload and returns nil" do
        audit_log.update!(ipfs_cid: "QmExistingCid")

        result = described_class.new(audit_log).archive!

        expect(result).to be_nil
      end
    end

    # [SEC.18 / DPIA M6 проти R7] Стеля на вміст того, що пінується ПУБЛІЧНО.
    # Це гейт-ЗАБОРОНА: його перемога Є порожньою множиною (сьогодні недекларованих
    # ключів у проді нуль), тож живість йому дає ДЕТЕКТОР — позитивний контроль поруч
    # із негативним, — а не популяція. Обидві половини несучі: без першої недекларований
    # ключ їде в незворотний пін, без другої гейт червонить на законному money-лозі,
    # і найдешевшою реакцією на це стало б його послаблення.
    context "when metadata carries a key nobody declared [SEC.18]" do
      before { stub_pinata_success }

      it "refuses to pin it, naming the offending keys" do
        audit_log.update_column(:metadata, { "tx_hash" => "0xabc123", "reporter_email" => "forester@example.com" })

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Filecoin::ArchiveService::UndeclaredMetadataError, /reporter_email/)

        expect(audit_log.reload.ipfs_cid).to be_nil
      end

      it "still pins the FULL declared money-path shape (proves it is not over-broad)" do
        audit_log.update_column(:metadata, AuditLog::ARCHIVED_METADATA_KEYS.index_with { |key| "v-#{key}" })

        expect(described_class.new(audit_log).archive!).to eq("QmTestCid12345")
      end

      it "pins an empty metadata hash without complaint" do
        audit_log.update_column(:metadata, {})

        expect(described_class.new(audit_log).archive!).to eq("QmTestCid12345")
      end
    end

    context "when API key is missing" do
      before do
        allow(Rails.application.credentials).to receive(:filecoin_api_key).and_return(nil)
      end

      it "raises an error about missing credentials" do
        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(RuntimeError, /Missing filecoin_api_key/)
      end
    end

    context "when IPFS upload fails" do
      it "raises an error on HTTP failure" do
        stub_pinata_failure

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Web3::HttpClient::RequestError, /Filecoin API returned 401/)
      end
    end

    context "when IPFS upload times out" do
      it "raises a timeout error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Filecoin Timeout: execution expired"))

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Web3::HttpClient::RequestError, /Filecoin Timeout/)
      end
    end

    context "when IPFS response has no CID" do
      it "raises an error about missing CID" do
        response = Web3::HttpClient::Response.new({ "status" => "ok" }.to_json)
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(RuntimeError, /No CID returned/)
      end
    end

    context "when IPFS response body is invalid JSON" do
      it "raises a parse error" do
        response = Web3::HttpClient::Response.new("not json at all")
        allow(Web3::HttpClient).to receive(:post).and_return(response)

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Web3::HttpClient::RequestError, /Invalid JSON response/)
      end
    end

    context "when audit_log.created_at is nil" do
      it "sets telemetry_summary to nil in payload" do
        allow(audit_log).to receive(:created_at).and_return(nil)

        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmNilDate" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content[:telemetry_summary]).to be_nil
        expect(content[:created_at]).to be_nil
      end
    end

    context "when no AI insights exist for the date" do
      it "sets telemetry_summary to nil when summaries are empty" do
        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmNoInsights" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        # No AI insights exist, so telemetry_summary should be nil
        expect(content).to have_key(:telemetry_summary)
      end
    end

    # [ARCH.57] Дзеркало сусіда вище, і різниця несуча: там порожній набір при
    # org-ful лозі (тобто випадковість, а не правило), тут — org-less ланцюг при
    # ІСНУЮЧОМУ org-less кластері з інсайтом. Без цього прикладу гілка зелена на
    # старому коді через саму лише популяцію: `IS NULL` нічого не матчить, доки
    # org-less кластера не існує. Кластер створюється `update_columns` навмисно —
    # `belongs_to :organization` без `optional:` інакше не дасть його зберегти.
    context "when the audit log belongs to the GLOBAL system chain (no organization)" do
      it "omits the telemetry summary instead of scooping org-less clusters" do
        global_log = create(:audit_log, user: user, organization: nil,
          action: "system_parameter_changed", metadata: {})
        orphan_cluster = create(:cluster, organization: user.organization)
        Cluster.where(id: orphan_cluster.id).update_all(organization_id: nil)
        create(:ai_insight, :daily_health_summary,
               analyzable: orphan_cluster,
               target_date: global_log.created_at.to_date,
               stress_index: 0.42,
               total_growth_points: 500,
               summary: "Orphan cluster summary",
               fraud_detected: false)

        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmGlobalChain" }.to_json)
        end

        described_class.new(global_log).archive!

        content = expected_body[:pinataContent]
        # Ліхтар на ПЕРЕДУМОВУ: без нього приклад був би зелений і на порожній базі.
        expect(Cluster.where(organization_id: nil).count).to eq(1)
        expect(content[:organization_id]).to be_nil
        expect(content[:telemetry_summary]).to be_nil
      end
    end

    context "when AI insights exist for the date" do
      it "includes cluster telemetry summary data" do
        cluster = create(:cluster, organization: user.organization)
        create(:ai_insight, :daily_health_summary,
               analyzable: cluster,
               target_date: audit_log.created_at.to_date,
               stress_index: 0.42,
               total_growth_points: 500,
               summary: "Moderate health",
               fraud_detected: false)

        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmWithInsights" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content[:telemetry_summary]).to be_present
        expect(content[:telemetry_summary][:date]).to eq(audit_log.created_at.to_date.iso8601)
        expect(content[:telemetry_summary][:clusters]).to be_an(Array)
        expect(content[:telemetry_summary][:clusters].first[:cluster_id]).to eq(cluster.id)
        expect(content[:telemetry_summary][:clusters].first[:stress_index]).to eq(0.42)
      end

      # 🔴 [ARCH.84] Доказ мусить нести підставу: середнє по кластеру німе про
      # дерева, що мовчали, тож без покриття аудитор, який відкриє IPFS-артефакт,
      # не відрізнить лісу, виміряного повністю, від виміряного на пʼяту частину.
      it "carries the coverage of the cluster average into the immutable evidence" do
        cluster = create(:cluster, organization: user.organization)
        create(:ai_insight, :daily_health_summary,
               analyzable: cluster,
               target_date: audit_log.created_at.to_date,
               stress_index: 0.42,
               total_growth_points: 500,
               summary: "Partly measured",
               reasoning: { "measured_trees" => 1, "total_trees" => 5 },
               fraud_detected: false)

        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmCoverage" }.to_json)
        end

        described_class.new(audit_log).archive!

        row = expected_body[:pinataContent][:telemetry_summary][:clusters].first
        expect(row[:stress_index]).to eq(0.42)
        expect(row[:measured_trees]).to eq(1)
        expect(row[:total_trees]).to eq(5)
      end

      # 🔴 [SEC.18] Другий вільнотекстовий канал того самого піна. Пін цілиться в
      # ЗНАЧЕННЯ, не в наявність ключа — `have_key`-форма була б зелена й на сирому
      # реченні. Назва сектора є вільним рядком ЛЮДИНИ (`clusters.name` валідована
      # лише на presence+uniqueness), і вона їхала в НЕЗВОРОТНИЙ пін усередині
      # `AiInsight#summary`. Тому маркер шукається в УСЬОМУ тілі запиту, а не лише
      # в очікуваному ключі: інакше приклад стеріг би одну адресу замість каналу.
      it "never carries the human-entered cluster name into the irreversible pin" do
        cluster = create(:cluster,
                         organization: user.organization,
                         name: "Сектор Петренка Івана, вул. Лісова 7")
        create(:ai_insight, :daily_health_summary,
               analyzable: cluster,
               target_date: audit_log.created_at.to_date,
               stress_index: 0.42,
               total_growth_points: 500,
               summary: "⚠️ Сектор #{cluster.name}: Виявлено 3 вузлів із фрод-телеметрією.",
               reasoning: { "measured_trees" => 4, "total_trees" => 5, "fraud_trees" => 3 },
               fraud_detected: true)

        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmNoFreeText" }.to_json)
        end

        described_class.new(audit_log).archive!

        row = expected_body[:pinataContent][:telemetry_summary][:clusters].first
        # Магнітуда, що доти жила ЛИШЕ всередині речення, тепер структурна — зняття
        # прози не коштувало доказу.
        expect(row[:fraud_trees]).to eq(3)
        expect(row[:fraud_detected]).to be(true)
        # …а сам текст не виїхав ЖОДНИМ ключем. Порядок несучий: контракт КАНАЛУ
        # («цього рядка немає ніде в тілі») стоїть ПЕРШИМ, бо саме він мусить
        # червоніти при мутації — інакше його доводив би лише вужчий сусід нижче,
        # і витік під іншим імʼям ключа пройшов би зеленим.
        expect(expected_body.to_json).not_to include("Петренка")
        expect(expected_body.to_json).not_to include("вул. Лісова")
        expect(row).not_to have_key(:summary)
      end

      it "handles nil stress_index in insight" do
        cluster = create(:cluster, organization: user.organization)
        create(:ai_insight, :daily_health_summary,
               analyzable: cluster,
               target_date: audit_log.created_at.to_date,
               stress_index: nil,
               total_growth_points: 0,
               summary: "No data",
               fraud_detected: false)

        expected_body = nil
        allow(Web3::HttpClient).to receive(:post) do |_url, **kwargs|
          expected_body = kwargs[:body]
          Web3::HttpClient::Response.new({ "IpfsHash" => "QmNilStress" }.to_json)
        end

        described_class.new(audit_log).archive!

        content = expected_body[:pinataContent]
        expect(content[:telemetry_summary][:clusters].first[:stress_index]).to be_nil
      end
    end

    context "when Net::OpenTimeout is raised" do
      it "raises a timeout error" do
        allow(Web3::HttpClient).to receive(:post)
          .and_raise(Web3::HttpClient::RequestError.new("Filecoin Timeout: connection timeout"))

        expect {
          described_class.new(audit_log).archive!
        }.to raise_error(Web3::HttpClient::RequestError, /Filecoin Timeout/)
      end
    end
  end

  private

  def stub_pinata_success
    response = Web3::HttpClient::Response.new(
      { "IpfsHash" => "QmTestCid12345", "PinSize" => 1234, "Timestamp" => "2026-03-11T12:00:00Z" }.to_json
    )
    allow(Web3::HttpClient).to receive(:post).and_return(response)
  end

  def stub_pinata_failure
    allow(Web3::HttpClient).to receive(:post)
      .and_raise(Web3::HttpClient::RequestError.new("Filecoin API returned 401: Unauthorized"))
  end
end
