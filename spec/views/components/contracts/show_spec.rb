# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::Show do
  def build_org(name: "Cherkasy Forest Fund")
    Organization.new(name: name)
  end

  # [TEST.12] Реальний незбережений `Cluster`. ⚠️ `active_threats?` лишається стабом
  # НАВМИСНО — це запит у БД (`ews_alerts.unresolved.critical.exists?`), а не дані
  # запису; підміняємо звертання до сховища, не поведінку моделі.
  def build_cluster(name: "Carpathian-Alpha", health_index: 0.85,
                    total_active_trees: 42, active_threats: false)
    c = Cluster.new(name: name, health_index: health_index, active_trees_count: total_active_trees)
    allow(c).to receive(:active_threats?).and_return(active_threats)
    c
  end

  # ⚠️ `burn:` ЯВНИЙ і обовʼязково задається: `OpenStruct` віддає `nil` на будь-який
  # незнаний метод, тож `tx.burn?` мовчки читався б як «мінт» — тобто фікстура
  # відтворювала б рівно той дефолт, який ARCH.101 і лікує.
  def mock_blockchain_tx(tx_hash: "0xdeadbeef1234567890abcdef", amount: "5.00", created_at: 2.hours.ago, burn: false)
    OpenStruct.new(tx_hash: tx_hash, amount: amount, created_at: created_at, "burn?" => burn)
  end

  # 🔴 [TEST.12] Тут мок розщепив ОДНЕ сховище на два незалежні поля.
  # `early_exit_fee_percent` / `burn_accrued_points` / `min_days_before_exit` —
  # не колонки, а `store_accessor` НАД `cancellation_terms`: на реальному записі
  # заповнити хеш означає заповнити акцесори, і навпаки. `OpenStruct` цього зв'язку
  # не має, тож фікстура з правильними ключами лишала акцесори порожніми, і секція
  # розірвання рендерилась із `0` / `no` / `—` — тобто саме там, де спека вважала
  # її заповненою. Слід розщеплення видно в самій спеці: третій контекст
  # («populated values») існував ЛИШЕ щоб дописати те, чого хеш не дав.
  # [ARCH.103] Емісії в контракту НЕМАЄ свідомо: величина кластерна, компонент дістає
  # її kwarg'ом `cluster_emission:` — фікстурне поле на контракті вигадувало б
  # семантику, зняту ⚖️-присудом.
  def build_contract(id: 99, status: :active, org: nil, cluster: nil,
                     total_funding: 50_000,
                     start_date: 6.months.ago, end_date: 6.months.from_now,
                     cancellation_terms: nil)
    NaasContract.new(
      id: id,
      status: status,
      organization: org || build_org,
      cluster: cluster,
      total_funding: total_funding,
      start_date: start_date,
      end_date: end_date,
      cancellation_terms: cancellation_terms
    )
  end

  def render_component(contract:, history:, cluster_emission: 1234.56)
    ApplicationController.renderer.render(
      component_class.new(contract: contract, history: history,
                          cluster_emission: cluster_emission),
      layout: false
    )
  end

  describe "contract header" do
    let(:contract) { build_contract(id: 99, status: "active") }
    let(:html) { render_component(contract: contract, history: []) }

    it "renders the contract ID in the hero" do
      expect(html).to include("#99")
    end

    it "renders organization name" do
      expect(html).to include("Cherkasy Forest Fund")
    end

    it "renders Contract Identity label" do
      expect(html).to include("Contract Identity")
    end

    it "renders the status in uppercase" do
      expect(html).to include("ACTIVE")
    end

    # 🔴 [ARCH.103] Мітка поїхала РАЗОМ зі значенням: «Emission Progress» обіцяла
    # прогрес ЦЬОГО контракту, а герой-цифра тепер показує емісію КЛАСТЕРА. Пін на
    # старий текст і був тим, що не дало б перепідписати поверхню.
    it "renders the Cluster Emission label" do
      expect(html).to include("Cluster Emission")
    end

    it "renders the cluster emission as the hero figure" do
      expect(html).to include("1234.56")
    end
  end

  describe "cluster backing asset panel" do
    context "when cluster is present" do
      let(:contract) { build_contract(cluster: build_cluster) }
      let(:html) { render_component(contract: contract, history: []) }

      it "renders Backing Asset Health section" do
        expect(html).to include("Backing Asset Health")
      end

      it "renders Cluster Vitality metric" do
        expect(html).to include("Cluster Vitality")
      end

      it "renders Active Soldiers count" do
        expect(html).to include("42")
      end
    end

    context "when cluster is nil" do
      let(:contract) { build_contract(cluster: nil) }
      let(:html) { render_component(contract: contract, history: []) }

      it "does not render backing asset panel" do
        expect(html).not_to include("Backing Asset Health")
      end
    end
  end

  describe "emission ledger" do
    context "with blockchain history" do
      let(:tx) { mock_blockchain_tx(tx_hash: "0xdeadbeef1234567890abcdef", amount: "7.50") }
      let(:html) { render_component(contract: build_contract, history: [ tx ]) }

      it "renders Blockchain Emission History heading" do
        expect(html).to include("Blockchain Emission History")
      end

      it "renders truncated tx hash" do
        expect(html).to include("0xdeadbeef12")
      end

      it "renders amount with SCC" do
        expect(html).to include("7.50 SCC")
      end
    end

    # 🔴 [ARCH.101] Слеш САМЕ ЦЬОГО контракту потрапляє в його ж «Emission History»
    # (`create_slash_intent!` ставить `sourceable: @naas_contract`), а знак «плюс»
    # був зашитий у сам рядок локалі — тобто вилучення друкувалось надходженням на
    # сторінці для інвестора. Пін тримає ОБИДВІ осі, бо самого мінуса в моноширинному
    # рядку майже не видно: знак ⊕ колір. Мутація «прибрати `burn?`-тернар» червонить
    # його на першому ж рядку.
    context "with a burn row in the history" do
      let(:tx) { mock_blockchain_tx(amount: "7.50", burn: true) }
      let(:html) { render_component(contract: build_contract, history: [ tx ]) }

      it "renders the burn with a minus sign, never a plus" do
        expect(html).to include("− 7.50 SCC")
        expect(html).not_to include("+ 7.50 SCC")
      end

      it "renders the burn in the danger tone, not the neutral one" do
        expect(html).to include("text-status-danger-text")
      end
    end

    context "with no blockchain history" do
      let(:html) { render_component(contract: build_contract, history: []) }

      it "shows no emissions recorded message" do
        expect(html).to include("No emissions recorded.")
      end
    end
  end

  describe "legal vault" do
    context "with cancellation_terms present" do
      let(:contract) do
        build_contract(cancellation_terms: {
          "early_exit_fee_percent" => 15,
          "burn_accrued_points" => true,
          "min_days_before_exit" => 30
        })
      end

      let(:html) { render_component(contract: contract, history: []) }

      it "renders Cancellation Terms section" do
        expect(html).to include("Cancellation Terms")
      end

      # [ARCH.84] «0%» комісії за дострокове розірвання — ЗАКОННА умова договору,
      # тож `|| 0` робив «умову не задано» невідрізнимим від «розірвання
      # безкоштовне», і саме в панелі LEGAL VAULT. Чесний сусід у тому ж блоці —
      # `min_days_before_exit || "—"`. ⚖️ Грошовий двійник
      # (`NaasContract#calculate_early_exit_fee`) лишається відкритим присудом.
      context "when the fee term itself is absent" do
        let(:contract) do
          build_contract(cancellation_terms: { "burn_accrued_points" => true })
        end

        it "does not print a fabricated zero percent" do
          expect(html).to include("Cancellation Terms")
          expect(html).not_to match(/Early Exit Fee[^<]*<\/[^>]*>\s*<[^>]*>\s*0\s*%/i)
          expect(html).not_to include("0%")
        end
      end

      it "renders the Smart Contract Data section" do
        expect(html).to include("Smart Contract Data")
      end

      # 🔴 Ці три ассерти доти жили в ОКРЕМОМУ контексті, що виставляв акцесори
      # руками поверх хеша-заглушки `{"present" => true}` — ключа, якого в схемі
      # немає. Контекст був не зайвою ретельністю, а протезом: мок розщепив
      # сховище, тож заповнений хеш не давав значень, і їх довелося дописувати
      # другим шляхом. На реальному записі шлях один, тож і контекст один.
      it "renders the values the terms hash itself carries" do
        expect(html).to include(">15%<")
        expect(html).to include(">Yes<")
        expect(html).to include(">30<")
      end
    end

    context "without cancellation terms" do
      let(:html) { render_component(contract: build_contract(cancellation_terms: nil), history: []) }

      it "still renders the legal vault without cancellation section" do
        expect(html).to include("Smart Contract Data")
      end
    end
  end

  describe "backing asset alert states" do
    it "flags vitality in red when cluster health is below 70%" do
      contract = build_contract(cluster: build_cluster(health_index: 0.5))
      html = render_component(contract: contract, history: [])
      expect(html).to include(">50%<")
      expect(html).to include("text-red-500")
    end

    it "renders a DANGER threat status when the cluster has active threats" do
      contract = build_contract(cluster: build_cluster(active_threats: true))
      html = render_component(contract: contract, history: [])
      expect(html).to include("DANGER")
    end

    # 🔴 [ARCH.84] Передумова цього приклада ПОМЕРЛА. Тут стояло «гард проти nil, якого
    # модель не вміє віддати» — і воно було правдою рівно доти, доки ридер підставляв
    # `|| 1.0`. Тепер `nil` є ЗВИЧАЙНИМ станом кластера, тож гілка не гард, а поведінка,
    # і пінити її треба як поведінку: не «0%» (це вимір, і то найгірший), а власний стан.
    it "renders «not measured» — never a fabricated 0% — when the cluster has no reading" do
      cluster = build_cluster
      allow(cluster).to receive(:health_index).and_return(nil)

      html = render_component(contract: build_contract(cluster: cluster), history: [])

      expect(html).to include(I18n.t("ui.measurement.not_measured"))
      expect(html).not_to include(">0%<")
    end

    # 🔴 Пара до попереднього, і саме вона робить його доказовим: невиміряний кластер
    # НЕ сміє дістати тривожну пульсацію (її підстава — вимір), а виміряний поганий —
    # мусить. Без цієї пари обидва стани злились би в «не зелений».
    it "withholds the degradation alarm from an unmeasured cluster but keeps it for a measured bad one" do
      unmeasured = build_cluster
      allow(unmeasured).to receive(:health_index).and_return(nil)
      measured_bad = build_cluster(health_index: 0.2)

      unmeasured_html = render_component(contract: build_contract(cluster: unmeasured), history: [])
      measured_html   = render_component(contract: build_contract(cluster: measured_bad), history: [])

      # [UI.3] Детектор ПЕРЕНЕСЕНО з `animate-pulse` на колір: рух знято з вузла,
      # що несе текст, а розрізняльну роль ніс і несе колір. Логіка пари
      # (невиміряний ⊥ виміряний-поганий) лишається та сама.
      expect(unmeasured_html).not_to include("text-red-500")
      expect(measured_html).to include("text-red-500")
    end
  end

  describe "emission ledger pending block" do
    it "shows the pending-block placeholder when a tx has no hash yet" do
      tx = mock_blockchain_tx(tx_hash: nil)
      html = render_component(contract: build_contract, history: [ tx ])
      expect(html).to include("PENDING_BLOCK")
    end
  end

  describe "hero with missing optional fields [coverage / defensive]" do
    it "renders the hero when organization and contract dates are nil" do
      contract = build_contract(start_date: nil, end_date: nil)
      contract.organization = nil
      html = render_component(contract: contract, history: [])
      expect(html).to include("Contract Identity")
    end
  end
end
