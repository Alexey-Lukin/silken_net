# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmergencyResponseService do
  before do
    allow(ActuatorCommandWorker).to receive(:perform_async)
  end

  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster, latitude: 49.4285, longitude: 32.0620) }
  let(:gateway) { create(:gateway, :online, :geolocated, cluster: cluster) }

  describe ".call" do
    context "with severe_drought alert" do
      let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

      it "splits 7200s duration into two 3600s commands per actuator" do
        valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)

        described_class.call(alert)

        commands = ActuatorCommand.where(actuator: valve, ews_alert: alert)
        expect(commands.count).to eq(2)
        expect(commands.pluck(:duration_seconds)).to all(eq(3600))
        expect(commands.pluck(:command_payload)).to all(eq("OPEN_VALVE"))
      end
    end

    context "with fire_detected alert" do
      let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

      it "splits 14400s duration into four 3600s valve commands" do
        valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)

        described_class.call(alert)

        commands = ActuatorCommand.where(actuator: valve, ews_alert: alert)
        expect(commands.count).to eq(4)
        expect(commands.pluck(:duration_seconds)).to all(eq(3600))
      end

      it "creates a single 3600s siren command" do
        # [ARCH.75] Сирена/маяк на РЕАЛЬНОМУ каденсі прошивки (1 год) недоставні
        # ЗАВЖДИ — це ратифікована поведінка, запінена окремим прикладом. Тут
        # предметом є ФОРМА протоколу, тож каденс стабимо.
        stub_const("Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S", 60)
        siren = create(:actuator, :fire_siren, gateway: gateway, state: :idle)

        described_class.call(alert)

        commands = ActuatorCommand.where(actuator: siren, ews_alert: alert)
        expect(commands.count).to eq(1)
        expect(commands.first.duration_seconds).to eq(3600)
        expect(commands.first.command_payload).to eq("ACTIVATE_SIREN")
      end
    end
  end

  describe "alert without a cluster" do
    it "returns early and dispatches nothing when the alert has no cluster" do
      alert_no_cluster = instance_double(EwsAlert, cluster: nil)

      expect {
        expect(described_class.call(alert_no_cluster)).to be_nil
      }.not_to change(ActuatorCommand, :count)
    end
  end

  describe "bulk insert (N+1 fix)" do
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

    it "creates commands for multiple actuators in a single insert" do
      3.times { create(:actuator, :water_valve, gateway: gateway, state: :idle) }

      # 3 actuators × 2 chunks (7200/3600) = 6 commands total
      expect { described_class.call(alert) }
        .to change(ActuatorCommand, :count).by(6)
    end

    it "does not push-enqueue the superseded worker (FW.60: доставку тягне poll Королеви)" do
      2.times { create(:actuator, :water_valve, gateway: gateway, state: :idle) }

      described_class.call(alert)

      # Push-ретраї в CGNAT-діру fail!'или б команду ДО першого poll'а;
      # створені команди (:issued) видимі poll-тракту через scope .pending
      expect(ActuatorCommandWorker).not_to have_received(:perform_async)
      expect(ActuatorCommand.pending.count).to eq(4)
    end
  end

  describe "gateway proximity prioritization" do
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

    it "orders actuators by gateway proximity to the alert tree" do
      near_gw = create(:gateway, :online, cluster: cluster, latitude: 49.4286, longitude: 32.0621)
      far_gw  = create(:gateway, :online, cluster: cluster, latitude: 50.0000, longitude: 33.0000)

      far_actuator  = create(:actuator, :water_valve, gateway: far_gw, state: :idle)
      near_actuator = create(:actuator, :water_valve, gateway: near_gw, state: :idle)

      described_class.call(alert)

      commands = ActuatorCommand.where(ews_alert: alert).order(:id)
      actuator_ids = commands.pluck(:actuator_id)

      # Посуха ріже 7200 на два чанки на актуатор: обидва накази ближнього мусять
      # ЦІЛКОМ передувати наказам дальнього (flat_map іде по відсортованих).
      expect(actuator_ids).to eq([ near_actuator.id, near_actuator.id, far_actuator.id, far_actuator.id ])
    end
  end

  # Гард тотальності приватного API: живий викликач порожній набір уже відсіює
  # (`report_step_unserved` → next), тож ця гілка досяжна лише прямим викликом —
  # пін тримає її свідомим no-op'ом, а не випадковим залишком.
  describe ".dispatch_commands із порожнім набором" do
    it "no-op'ає без жодного запису й без винятку" do
      alert = create(:ews_alert, :drought, cluster: cluster, tree: tree)
      expect {
        described_class.send(:dispatch_commands, [], "OPEN_VALVE",
                             duration: 3600, relevance: 1.hour, alert: alert)
      }.not_to change(ActuatorCommand, :count)
    end
  end

  describe ".duration_chunks" do
    it "returns single chunk for duration <= 3600" do
      expect(described_class.send(:duration_chunks, 3600)).to eq([ 3600 ])
      expect(described_class.send(:duration_chunks, 1800)).to eq([ 1800 ])
    end

    it "splits 7200 into two 3600 chunks" do
      expect(described_class.send(:duration_chunks, 7200)).to eq([ 3600, 3600 ])
    end

    it "splits 14400 into four 3600 chunks" do
      expect(described_class.send(:duration_chunks, 14400)).to eq([ 3600, 3600, 3600, 3600 ])
    end

    it "handles remainders correctly" do
      expect(described_class.send(:duration_chunks, 5400)).to eq([ 3600, 1800 ])
    end
  end

  # =========================================================================
  # [ARCH.75] НЕ-ДІЯ мусить свідчити про себе — інакше вона невідрізнима від успіху
  # =========================================================================
  # 🔴 Доти тут стояв рівно один приклад — «returns early when no actuators are
  # available» з піном на `Rails.logger.warn`, — і він ЦЕМЕНТУВАВ дефект: лог, якого
  # ніхто не читає, був єдиним слідом того, що аварійний протокол не виконався. Гірша
  # ж половина класу не мала прикладу взагалі: коли крок протоколу не має свого
  # інструмента, а сусідній має, відповідь іде НАПОЛОВИНУ й виглядає як повний успіх.
  describe "protocol steps that nothing can serve" do
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

    it "raises a critical alert instead of a log line when the cluster has no actuators at all" do
      expect { described_class.call(alert) }.not_to change(ActuatorCommand, :count)

      raised = EwsAlert.alert_type_emergency_response_undeliverable
                       .find_by(message_key: "emergency_response_no_actuator")
      expect(raised).to be_present
      expect(raised.severity).to eq("critical")
      expect(raised.message_params).to include("device_type" => "water_valve")
    end

    # 🔴 Найдорожча половина класу: пожежа на кластері, де є полив і НЕМАЄ сирени.
    # Пара «лишається ⊥ відпадає» тут несуча — без неї «алерт створено» не відрізнити
    # від «нічого не поїхало», а саме часткове виконання й читалось як успіх.
    it "fires the valve AND names the missing siren — a half-executed protocol is not a success" do
      valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)
      fire = create(:ews_alert, :fire, cluster: cluster, tree: tree)

      described_class.call(fire)

      expect(ActuatorCommand.where(ews_alert: fire).pluck(:actuator_id).uniq).to eq([ valve.id ])
      raised = EwsAlert.alert_type_emergency_response_undeliverable
                       .find_by(message_key: "emergency_response_no_actuator")
      expect(raised).to be_present
      expect(raised.message_params).to include("device_type" => "fire_siren")
    end

    # Два відсутні інструменти — ДВА факти, не один: кластер, у якому не поставили
    # нічого, мусить дізнатись про обидва кроки протоколу окремо.
    it "reports every unserved step separately" do
      fire = create(:ews_alert, :fire, cluster: cluster, tree: tree)

      described_class.call(fire)

      named = EwsAlert.alert_type_emergency_response_undeliverable
                      .pluck(:message_params).map { _1["device_type"] }
      expect(named).to match_array(%w[fire_siren water_valve])
    end

    # 🔴 Дискримінатор, заради якого фільтр придатності поїхав із SQL у памʼять:
    # «заліза немає» і «залізо є, але недосяжне» — різні дії людини, і доти вони
    # згорталися в один мовчазний `warn`.
    it "tells hardware that was never installed apart from hardware that cannot be reached" do
      silent_gateway = create(:gateway, :offline, cluster: cluster)
      create(:actuator, :water_valve, gateway: silent_gateway, state: :idle)
      create(:actuator, :water_valve, gateway: gateway, state: :maintenance_needed)

      expect { described_class.call(alert) }.not_to change(ActuatorCommand, :count)

      raised = EwsAlert.alert_type_emergency_response_undeliverable
                       .find_by(message_key: "emergency_response_all_unavailable")
      expect(raised).to be_present
      expect(raised.message_params).to include(
        "device_type" => "water_valve", "installed" => 2,
        "silent_gateway" => 1, "out_of_service" => 1
      )
    end

    # 🔴 GREEN-половина (§Guard-craft #52), і без неї клас закритий лише наполовину:
    # усі піни вище стверджують, що алерт Є, тобто over-broad писач — той, що кричить і
    # на ОБСЛУЖЕНОМУ кроці, — лишався б непоміченим. Виміряно мутацією: безумовний
    # виклик червонить рівно двох СУСІДІВ («still dispatches to the sibling», «does not
    # pile up a duplicate»), чиї назви про цю вісь мовчать — тобто механізм тримався на
    # чужих пінах, і наступний рефактор прочитав би ті падіння як «поправити фікстуру».
    it "stays SILENT when every protocol step has a healthy actuator" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      # Ліхтар обовʼязковий: без нього «нуль алертів» не відрізнити від «нічого не
      # виконувалось» — та сама порожня множина, що вже коштувала на `seismic_anomaly`.
      expect { described_class.call(alert) }.to change(ActuatorCommand, :count)
      expect(EwsAlert.alert_type_emergency_response_undeliverable.count).to eq(0)
    end

    # Дедуп ключується на ТИПІ, не на актуаторі — інакше крок, якому нема кому
    # виконуватись, писав би новий рядок на кожну тривогу кластера.
    # Другий тригер — той самий перил на ІНШОМУ дереві: модель не дає двох
    # активних алертів одного типу на одне дерево.
    it "does not pile up a duplicate alert for the same missing device type" do
      second = create(:ews_alert, :drought, cluster: cluster, tree: create(:tree, cluster: cluster))

      described_class.call(alert)
      described_class.call(second)

      expect(EwsAlert.alert_type_emergency_response_undeliverable.count).to eq(1)
    end
  end

  describe "nil organization chain" do
    it "handles nil cluster.organization_id gracefully" do
      alert = create(:ews_alert, :drought, cluster: cluster, tree: tree)
      valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)

      allow(cluster).to receive(:organization_id).and_return(nil)

      expect {
        described_class.call(alert)
      }.to change(ActuatorCommand, :count)
    end
  end

  describe "tree without coordinates" do
    it "skips proximity ordering when tree has no latitude/longitude" do
      tree_no_gps = create(:tree, cluster: cluster, latitude: nil, longitude: nil)
      alert = create(:ews_alert, :drought, cluster: cluster, tree: tree_no_gps)
      valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)

      expect {
        described_class.call(alert)
      }.to change(ActuatorCommand, :count)
    end
  end

  describe "unknown alert_type" do
    let(:alert) { create(:ews_alert, cluster: cluster, tree: tree, alert_type: :vandalism_breach, severity: :critical) }

    it "logs info but does not create commands" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      allow(Rails.logger).to receive(:info).with(/Тип тривоги.*обробляється лише сповіщенням/)

      expect {
        described_class.call(alert)
      }.not_to change(ActuatorCommand, :count)

      expect(Rails.logger).to have_received(:info).with(/Тип тривоги.*обробляється лише сповіщенням/)
    end
  end

  describe "tree without coordinates (proximity skip)" do
    let(:tree_no_coords) { create(:tree, cluster: cluster, latitude: nil, longitude: nil) }
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree_no_coords) }

    it "does not sort by proximity and still creates commands" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      expect {
        described_class.call(alert)
      }.to change(ActuatorCommand, :count).by(2) # посуха = 7200 → два чанки
    end
  end

  describe "alert tree is nil" do
    it "does not sort by proximity" do
      alert_no_tree = create(:ews_alert, cluster: cluster, tree: nil, severity: :critical, alert_type: :severe_drought)
      create(:actuator, :water_valve, gateway: gateway, state: :idle)
      expect { described_class.call(alert_no_tree) }.not_to raise_error
    end
  end

  describe "insert_all failure" do
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

    it "logs error when insert_all fails" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      allow(ActuatorCommand).to receive(:insert_all).and_raise(StandardError, "DB insert failed")

      allow(Rails.logger).to receive(:error).with(/Масове створення наказів провалене/)

      described_class.call(alert)

      expect(Rails.logger).to have_received(:error).with(/Масове створення наказів провалене/)
    end
  end

  # =========================================================================
  # FIRE: MIXED ACTUATOR TYPES (valve + siren)
  # =========================================================================
  describe "fire_detected dispatches both valves and sirens" do
    let(:alert) { create(:ews_alert, :fire, cluster: cluster, tree: tree) }

    it "creates valve AND siren commands for fire alert" do
      # [ARCH.75] Сирена/маяк на РЕАЛЬНОМУ каденсі прошивки (1 год) недоставні
      # ЗАВЖДИ — це ратифікована поведінка, запінена окремим прикладом. Тут
      # предметом є ФОРМА протоколу, тож каденс стабимо.
      stub_const("Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S", 60)
      valve = create(:actuator, :water_valve, gateway: gateway, state: :idle)
      siren = create(:actuator, :fire_siren, gateway: gateway, state: :idle)

      described_class.call(alert)

      valve_cmds = ActuatorCommand.where(actuator: valve, ews_alert: alert)
      siren_cmds = ActuatorCommand.where(actuator: siren, ews_alert: alert)

      expect(valve_cmds.count).to eq(4) # 14400 / 3600 = 4
      expect(siren_cmds.count).to eq(1) # 3600 / 3600 = 1
      expect(valve_cmds.pluck(:command_payload).uniq).to eq([ "OPEN_VALVE" ])
      expect(siren_cmds.pluck(:command_payload).uniq).to eq([ "ACTIVATE_SIREN" ])
    end
  end

  # =========================================================================
  # COMMAND ATTRIBUTES (org_id, idempotency, priority, expires_at)
  # =========================================================================
  describe "command attributes" do
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

    it "sets organization_id from cluster for Turbo broadcast" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      described_class.call(alert)

      cmd = ActuatorCommand.last
      expect(cmd.organization_id).to eq(cluster.organization_id)
    end

    it "assigns unique idempotency_token to each command" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      described_class.call(alert)

      tokens = ActuatorCommand.where(ews_alert: alert).pluck(:idempotency_token)
      expect(tokens.uniq.size).to eq(tokens.size) # all unique
      expect(tokens).to all(match(/\A[0-9a-f\-]{36}\z/)) # UUID format
    end

    it "sets priority to high for emergency commands" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      described_class.call(alert)

      cmd = ActuatorCommand.last
      expect(cmd.priority).to eq("high")
    end

    # [ARCH.75] TTL більше НЕ фіксовані 15 хв: це вікно РЕЛЕВАНТНОСТІ кроку, тобто
    # твердження про фізику події. Пін на дві різні величини в одному протоколі —
    # інакше «взяли з таблиці» не відрізнити від «знову одна константа».
    it "sets expires_at to the step's relevance window, not a flat constant" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      described_class.call(alert)

      cmd = ActuatorCommand.last
      expect(cmd.expires_at).to be_within(1.minute).of(6.hours.from_now)
    end

    it "gives the siren a SHORTER window than the valve in the same fire protocol" do
      # Каденс стабимо: на РЕАЛЬНОМУ (годинному) сирена недоставна за побудовою —
      # це ратифікована поведінка, запінена окремо нижче. Тут перевіряємо, що
      # вікна РІЗНІ, а не що сирена доїжджає.
      stub_const("Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S", 60)
      fire = create(:ews_alert, :fire, cluster: cluster, tree: tree)
      create(:actuator, :water_valve, gateway: gateway, state: :idle)
      create(:actuator, :fire_siren, gateway: gateway, state: :idle)

      described_class.call(fire)

      siren = ActuatorCommand.joins(:actuator).where(ews_alert: fire, actuators: { device_type: :fire_siren }).first
      valve = ActuatorCommand.joins(:actuator).where(ews_alert: fire, actuators: { device_type: :water_valve }).first
      expect(siren.expires_at).to be_within(1.minute).of(15.minutes.from_now)
      expect(valve.expires_at).to be_within(1.minute).of(2.hours.from_now)
    end

    # 🔴 Пін, якого НЕ БУЛО, і саме тому весь клас ARCH.75 прожив непоміченим:
    # `insert_all` обходить валідації, тож спеки роками пінили `duration_seconds`
    # і жодна не питала, чи створений рядок узагалі можна зберегти. Невалідний
    # наказ не вміє ні виконатись, ні померти.
    # ⚠️ Слабкий актуатор у наборі — НЕ декорація: без нього приклад вакуумний.
    # Виміряно мутацією: зі самим лише дефолтним пристроєм (стеля = чанк) зняття
    # перевірки стелі лишає цей пін ЗЕЛЕНИМ, бо в наборі немає нічого, що механізм
    # мусить відкинути. Фільтр доводиться парою «лишається ⊥ відпадає».
    it "creates only commands that pass their own model validations" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle, max_active_duration_s: 120)
      create(:actuator, :water_valve, gateway: gateway, state: :idle)

      described_class.call(alert)

      commands = ActuatorCommand.where(ews_alert: alert)
      expect(commands).to be_any
      expect(commands.reject(&:valid?)).to be_empty
    end
  end

  # =========================================================================
  # [ARCH.75] ГУЧНА ВІДМОВА замість тихого невалідного рядка
  # =========================================================================
  describe "undeliverable physical response" do
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

    context "when the protocol exceeds the actuator's physical ceiling" do
      it "issues NO command and raises a critical alert naming both numbers" do
        create(:actuator, :water_valve, gateway: gateway, state: :idle, max_active_duration_s: 120)

        expect { described_class.call(alert) }.not_to change(ActuatorCommand, :count)

        raised = EwsAlert.alert_type_emergency_response_undeliverable.last
        expect(raised.message_key).to eq("emergency_response_over_ceiling")
        expect(raised.severity).to eq("critical")
        expect(raised.message_params).to include("chunk_s" => 3600, "limit_s" => 120)
      end
    end

    # 🔴 Ратифікована поведінка (⚖️ 2026-08-15), а не побічний ефект: каденс флашу
    # Королеви — компайл-тайм константа прошивки (1 год), тож 15-хвилинна сирена
    # недоставна на БУДЬ-ЯКОМУ шлюзі, який платформа провіжинить. Каденс тут
    # СВІДОМО не стабиться — предметом піна є саме дефолт.
    context "when the response stays relevant for less than the fleet's real poll cadence" do
      it "issues NO siren command at all, and names the cadence rather than the ceiling" do
        create(:actuator, :fire_siren, gateway: gateway, state: :idle)
        fire = create(:ews_alert, :fire, cluster: cluster, tree: tree)

        expect { described_class.call(fire) }.not_to change(ActuatorCommand, :count)

        # 🔴 Адресація за КЛЮЧЕМ, не `.last`: у цьому кластері немає клапана, тож
        # пожежний протокол законно лишає ДВА сліди — недоставну сирену й невстановлений
        # полив. Доти приклад брав останній рядок і був би зелений на чужому факті.
        raised = EwsAlert.alert_type_emergency_response_undeliverable
                         .find_by(message_key: "emergency_response_too_slow")
        expect(raised).to be_present
        expect(raised.message_params).to include("relevance_min" => 15, "cadence_min" => 61)
      end
    end

    # Дзеркало «лишається ⊥ відпадає»: без нього «нуль порушень» не відрізнити
    # від «нуль доставки». Відмова мусить бути ПОАКТУАТОРНОЮ.
    it "still dispatches to the sibling actuator that CAN deliver" do
      weak = create(:actuator, :water_valve, gateway: gateway, state: :idle, max_active_duration_s: 120)
      strong = create(:actuator, :water_valve, gateway: gateway, state: :idle)

      described_class.call(alert)

      served = ActuatorCommand.where(ews_alert: alert).pluck(:actuator_id).uniq
      expect(served).to eq([ strong.id ])
      expect(EwsAlert.alert_type_emergency_response_undeliverable.count).to eq(1)
      expect(EwsAlert.alert_type_emergency_response_undeliverable.last.message_params["actuator_id"]).to eq(weak.id)
    end

    # Другий тригер — ІНШЕ дерево: модель не дає двох активних алертів одного
    # типу на одне дерево, а дедуп тут ключується на ПАРІ (причина, актуатор) —
    # не на алерті, що його спричинив. [ARCH.102] Інакший тип більше не годиться:
    # єдиний інший клапанний протокол (fire) тягне ще й сирену, чий unserved-слід
    # зашумив би лічильник.
    it "does not pile up a duplicate alert for the same actuator and cause" do
      create(:actuator, :water_valve, gateway: gateway, state: :idle, max_active_duration_s: 120)
      second = create(:ews_alert, :drought, cluster: cluster, tree: create(:tree, cluster: cluster))

      described_class.call(alert)
      described_class.call(second)

      expect(EwsAlert.alert_type_emergency_response_undeliverable.count).to eq(1)
    end
  end

  # =========================================================================
  # [ARCH.75] Ієрархія Виживання — сирена мусить ВИЙТИ З ЧЕРГИ першою
  # =========================================================================
  describe "fire dispatch order" do
    it "puts the siren ahead of the watering chunks in the poll queue" do
      stub_const("Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S", 60)
      fire = create(:ews_alert, :fire, cluster: cluster, tree: tree)
      create(:actuator, :water_valve, gateway: gateway, state: :idle)
      create(:actuator, :fire_siren, gateway: gateway, state: :idle)

      described_class.call(fire)

      # Королева дренажує лише QUEEN_POLL_MAX_PER_FLUSH=3 накази за флаш, тож
      # п'ята позиція = наступний флаш = смерть по TTL для 15-хвилинного вікна.
      first = ActuatorCommand.where(ews_alert: fire).by_priority.first
      expect(first.command_payload).to eq("ACTIVATE_SIREN")
    end
  end

  # =========================================================================
  # [ARCH.75] Парність таблиці протоколів проти обох enum'ів
  # =========================================================================
  # 🔴 Найдешевший гейт цього тракту, і доти його не існувало: `by_device_type.fetch(k, [])`
  # + `return if actuators.empty?` означає, що друкарська помилка в ключі (чи символ
  # замість рядка) дає НУЛЬ команд, НУЛЬ алертів і НУЛЬ логів — тобто аварійний
  # протокол мовчки зникає. `drone_launcher` уже показав, що enum-значення без гілки
  # диспетчеризації в цьому домені трапляється.
  describe "PROTOCOLS parity" do
    it "keys every step by a real Actuator#device_type" do
      declared = described_class::PROTOCOLS.values.flatten.map { _1[:device_type] }.uniq
      expect(declared - Actuator.device_types.keys).to be_empty
    end

    it "keys every protocol by a real EwsAlert#alert_type" do
      expect(described_class::PROTOCOLS.keys.map(&:to_s) - EwsAlert.alert_types.keys).to be_empty
    end

    it "declares a relevance window and a positive duration for every step" do
      described_class::PROTOCOLS.values.flatten.each do |step|
        expect(step[:relevance].to_i).to be > 0, "крок #{step[:payload]} без вікна релевантності"
        expect(step[:duration].to_i).to be > 0, "крок #{step[:payload]} без тривалості"
      end
    end
  end

  # =========================================================================
  # MIXED GATEWAY ONLINE/OFFLINE
  # =========================================================================
  describe "only uses actuators from online gateways" do
    let(:alert) { create(:ews_alert, :drought, cluster: cluster, tree: tree) }

    it "ignores actuators from offline gateways" do
      online_gw = create(:gateway, :online, cluster: cluster)
      offline_gw = create(:gateway, cluster: cluster, last_seen_at: 3.hours.ago)

      online_actuator = create(:actuator, :water_valve, gateway: online_gw, state: :idle)
      _offline_actuator = create(:actuator, :water_valve, gateway: offline_gw, state: :idle)

      described_class.call(alert)

      actuator_ids = ActuatorCommand.where(ews_alert: alert).pluck(:actuator_id).uniq
      expect(actuator_ids).to include(online_actuator.id)
      expect(actuator_ids).not_to include(_offline_actuator.id)
    end
  end

  describe "cluster with nil organization" do
    it "handles alert with cluster having nil organization_id" do
      cluster_no_org = create(:cluster, organization: organization)
      tree_no_org = create(:tree, cluster: cluster_no_org, latitude: nil, longitude: nil)
      gateway_online = create(:gateway, :online, cluster: cluster_no_org, latitude: 49.0, longitude: 32.0)
      create(:actuator, :water_valve, gateway: gateway_online, state: :idle)

      alert = create(:ews_alert, :drought, cluster: cluster_no_org, tree: tree_no_org)

      # This tests the proximity branch where tree has no coordinates
      expect {
        described_class.call(alert)
      }.not_to raise_error
    end
  end
end
