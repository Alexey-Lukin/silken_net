# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::EventRow do
  # Специфікації типово йдуть під :en, і саме англійські рядки тут асертуються.
  # ⚠️ Коментар на цьому місці доти казав, що рядки компонента «intentional display
  # text (not i18n-keyed)» — це було НЕПРАВДОЮ від першого дня: `event_summary`
  # увесь на `t(".…")`. Проза стереже читача, а не код, тож хибна проза переживає
  # будь-який зелений прогін.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  # [TEST.12] Реальні незбережені записи всюди: клас-ідентичність для `case/when`
  # незбережений `new` тримає так само добре, як колишній `allocate`, а enum-сеттер
  # ще й відкидає значення, яких модель не знає (синг触тон приймав будь-що).

  describe "with an EwsAlert event" do
    let(:event) do
      # Реальне значення enum'а, а не вигаданий display-рядок: із «Thermal
      # Anomaly» компонент їхав fail-open гілкою `humanize`, тож спека перевіряла
      # шлях, якого в проді не буває.
      EwsAlert.new(alert_type: "fire_detected", cluster: Cluster.new(name: "Carpathian-7"),
                   created_at: 30.seconds.ago)
    end
    let(:html) { render_component(event: event) }

    it "renders the threat summary" do
      expect(html).to include("Threat:")
      expect(html).to include("Fire Detected")
      expect(html).to include("Carpathian-7")
    end

    it "uses the danger accent for alert events" do
      expect(html).to include("text-status-danger-accent")
    end
  end

  # 🔴 [TEST.12] Грошові рядки будуються РЕАЛЬНИМ `new`, а не `.allocate` +
  # сингլетонами: `#ticker` і `#burn?` ВИВОДЯТЬСЯ з колонок (`token_type`,
  # `sourceable_type`), тож фікстура, що оголошувала б їх окремими полями, описувала
  # транзакцію, яку неможливо побудувати — і саме так тут роками жив пін, що
  # стверджував «Minted» для спалення. Клас ідентичності `case/when` незбережений
  # `new` тримає так само добре, як `allocate`.
  def money_row(token_type: :carbon_coin, amount: "0.005", wallet: nil, cluster: nil, sourceable_type: nil)
    BlockchainTransaction.new(
      token_type: token_type, amount: amount, wallet: wallet, cluster: cluster,
      sourceable_type: sourceable_type, created_at: 1.minute.ago
    )
  end

  def tree_wallet(did) = Wallet.new(tree: Tree.new(did: did))

  describe "with a BlockchainTransaction event" do
    let(:event) { money_row(wallet: tree_wallet("SNET-0DEADBEE")) }
    let(:html) { render_component(event: event) }

    it "renders the mint summary with amount, ticker and DID" do
      expect(html).to include("Minted")
      expect(html).to include("0.005")
      expect(html).to include("SCC")
      expect(html).to include("SNET-0DEADBEE")
    end

    it "uses the gaia text token for blockchain events" do
      expect(html).to include("text-gaia-text")
      # [ARCH.101] Друга половина пари: мінт НЕ дістає burn-акцента.
      expect(html).not_to include("text-status-danger-accent")
    end
  end

  describe "with a MaintenanceRecord event" do
    let(:event) do
      MaintenanceRecord.new(action_type: "repair", user: User.new(first_name: "Taras"),
                            created_at: 5.minutes.ago)
    end
    let(:html) { render_component(event: event) }

    it "renders the maintenance summary" do
      expect(html).to include("Repair")
      expect(html).to include("Taras")
    end

    it "uses warning color for maintenance events" do
      expect(html).to include("text-status-warning-text")
    end
  end

  describe "with an unknown event type" do
    let(:event) { OpenStruct.new(created_at: 10.seconds.ago) }
    let(:html) { render_component(event: event) }

    it "renders fallback text" do
      expect(html).to include("System pulse detected")
    end

    it "uses the gaia subtle text token for unknown events" do
      expect(html).to include("text-gaia-text-subtle")
    end
  end

  describe "best practices compliance" do
    let(:event) { OpenStruct.new(created_at: 1.minute.ago) }
    let(:html) { render_component(event: event) }

    it "uses semantic text-tiny instead of arbitrary sizes" do
      expect(html).to include("text-tiny")
      expect(html).not_to include("text-[")
    end

    it "uses gap instead of space-x for flex layout" do
      expect(html).to include("gap-4")
    end
  end

  describe "EwsAlert with no cluster" do
    let(:event) do
      alert = EwsAlert.allocate
      # 🔴 [TEST.12] Доти тут стояло `"Seismic"` — значення поза enum (`EwsAlert.new`
      # на ньому кидає `ArgumentError`). Приклад цього не асертував, тож дефект був
      # ЛАТЕНТНИЙ: `.allocate` пропускає те, що конструктор відкинув би, а перший пін
      # на заголовок зацементував би «Seismic» замість продового заголовка
      # (виміряно тоді: локаль-ключа `alerts.types.Seismic` немає → fail-open `humanize`).
      # [ARCH.102] Виправлений тоді `seismic_anomaly` сам покинув enum — семпл переїхав
      # на `system_fault`: тип, що в проді СПРАВДІ буває без кластера (його пише
      # монітор скарбниці, ARCH.82).
      alert.define_singleton_method(:alert_type) { "system_fault" }
      alert.define_singleton_method(:cluster) { nil }
      alert.define_singleton_method(:created_at) { 1.minute.ago }
      alert
    end

    it "falls back to the Unknown cluster label" do
      expect(render_component(event: event)).to include("Unknown")
    end
  end

  describe "BlockchainTransaction routed through Etherisc" do
    def etherisc_tx(to_address:)
      pi = ParametricInsurance.allocate
      pi.define_singleton_method(:uses_etherisc?) { true }
      tx = BlockchainTransaction.allocate
      tx.define_singleton_method(:amount) { "12.50" }
      tx.define_singleton_method(:to_address) { to_address }
      tx.define_singleton_method(:sourceable) { pi }
      # [ARCH.101] `event_color` тепер читає й деривацію напрямку; `.allocate`
      # вимагає стабити КОЖНЕ читане поле (04_06 §A.2 10б) — чесна колонка
      # insurance-рядка, тож `burn?` віддає false.
      tx.define_singleton_method(:sourceable_type) { "ParametricInsurance" }
      tx.define_singleton_method(:created_at) { 1.minute.ago }
      tx
    end

    it "renders an Etherisc DIP claim with a truncated address" do
      html = render_component(event: etherisc_tx(to_address: "0x1234567890abcdef1234"))
      expect(html).to include("Etherisc DIP claim")
      expect(html).to include("0x1234…1234")
    end

    it "labels the destination as Pool when the address is blank" do
      html = render_component(event: etherisc_tx(to_address: nil))
      expect(html).to include("Pool")
    end
  end

  describe "BlockchainTransaction mint with neither wallet nor cluster" do
    # ⚠️ Fail-open гілка, а НЕ спостережний стан: рядок без обох координат не бачить
    # `for_organization`, тож на цю сторінку він не потрапляє. Пін стереже форму
    # фолбеку, і саме тому не претендує описувати живі дані.
    let(:event) { money_row(amount: "0.001") }

    it "falls back to the System target" do
      html = render_component(event: event)
      expect(html).to include("Minted")
      expect(html).to include("→ System")
    end
  end

  # 🔴 НАПРЯМОК не є полем — він деривується з `sourceable_type`, і знак `amount`
  # його НЕ видає (slash-інтент пишеться ДОДАТНИМ). Доти обидва приклади нижче
  # друкувались «⬢ Minted … SCC», тобто екран стверджував емісію на спаленні.
  describe "BlockchainTransaction that is a slash burn" do
    it "names the burn and points the arrow away from the tree that paid" do
      html = render_component(
        event: money_row(amount: "3.0", wallet: tree_wallet("SNET-0BADCAFE"),
                         sourceable_type: "NaasContract")
      )
      expect(html).to include("Burned 3.0 SCC ← SNET-0BADCAFE")
      expect(html).not_to include("Minted")
    end

    # [ARCH.101 ⚖️ 08-20] Колір читається раніше за текст: спалення дістає accent,
    # мінт лишається на нейтральному токені (дзеркальний пін у mint-блоці вище
    # тримає протилежний бік — безумовний акцент червонить саме його).
    it "paints the burn with the danger accent, not the neutral text token" do
      html = render_component(
        event: money_row(amount: "3.0", wallet: tree_wallet("SNET-0BADCAFE"),
                         sourceable_type: "NaasContract")
      )
      expect(html).to include("text-status-danger-accent")
    end

    it "names the CLUSTER when the last tree is gone and the row carries no wallet" do
      html = render_component(
        event: money_row(amount: "3.0", cluster: Cluster.new(name: "Карпати-7"),
                         sourceable_type: "NaasContract")
      )
      expect(html).to include("Burned 3.0 SCC ← Карпати-7")
      expect(html).not_to include("System")
    end
  end

  # [ARCH.98] Cluster-sourced гроші живуть БЕЗ гаманця, тож джерело події доводиться
  # брати тією самою парою, якою `for_organization` резолвить приналежність.
  describe "cluster-sourced Celo reward" do
    let(:html) do
      render_component(
        event: money_row(token_type: :cusd, amount: "5.0", cluster: Cluster.new(name: "Карпати-7"))
      )
    end

    it "signs the amount with the token's OWN ticker" do
      expect(html).to include("5.0 cUSD")
      expect(html).not_to include("SCC")
    end

    it "names the cluster instead of inventing a System actor" do
      expect(html).to include("→ Карпати-7")
      expect(html).not_to include("System")
    end
  end

  describe "MaintenanceRecord with no user or action" do
    let(:event) do
      record = MaintenanceRecord.allocate
      record.define_singleton_method(:action_type) { nil }
      record.define_singleton_method(:user) { nil }
      record.define_singleton_method(:created_at) { 1.minute.ago }
      record
    end

    it "renders the maintenance summary with the System fallback user" do
      expect(render_component(event: event)).to include("by System")
    end
  end
end
