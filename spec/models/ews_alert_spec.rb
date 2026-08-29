# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EwsAlert, type: :model do
  before do
    allow(AlertNotificationWorker).to receive(:perform_async)
    silence_broadcasts!(:alert_notify, :alert_update, :alert_new)
  end

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to cluster (optional)" do
      association = described_class.reflect_on_association(:cluster)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be(true)
    end

    it "belongs to tree (optional)" do
      association = described_class.reflect_on_association(:tree)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be(true)
    end

    it "belongs to resolver (optional User)" do
      association = described_class.reflect_on_association(:resolver)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:class_name]).to eq("User")
      expect(association.options[:foreign_key]).to eq("resolved_by")
      expect(association.options[:optional]).to be(true)
    end
  end

  # =========================================================================
  # ENUMS
  # =========================================================================
  describe "enums" do
    it "defines status enum with prefix" do
      alert = build(:ews_alert)
      expect(alert).to respond_to(:status_active?)
      expect(alert).to respond_to(:status_resolved?)
      expect(alert).to respond_to(:status_ignored?)
    end

    it "defines severity enum with prefix" do
      alert = build(:ews_alert)
      expect(alert).to respond_to(:severity_low?)
      expect(alert).to respond_to(:severity_medium?)
      expect(alert).to respond_to(:severity_critical?)
    end

    it "defines alert_type enum with prefix" do
      alert = build(:ews_alert)
      expect(alert).to respond_to(:alert_type_severe_drought?)
      expect(alert).to respond_to(:alert_type_fire_detected?)
      expect(alert).to respond_to(:alert_type_system_fault?)
      expect(alert).to respond_to(:alert_type_field_audit?)
    end

    it "defines satellite_status enum with satellite prefix" do
      alert = build(:ews_alert)
      expect(alert).to respond_to(:satellite_unverified?)
      expect(alert).to respond_to(:satellite_verified?)
      expect(alert).to respond_to(:satellite_rejected_fraud?)
      expect(alert).to respond_to(:satellite_inconclusive?)
    end

    it "defaults satellite_status to unverified" do
      alert = build(:ews_alert)
      expect(alert).to be_satellite_unverified
    end

    it "defines firmware_fault alert type (SLASH-1: wire vm_error, NOT vandalism)" do
      alert = build(:ews_alert, alert_type: :firmware_fault)
      expect(alert).to be_alert_type_firmware_fault
    end
  end

  # [SLASH-1] Dedup cluster-level Field-Audit ескалацій: одна АКТИВНА на кластер —
  # щоденні crons (freeze/blackout/insurance no-data) не плодять дубль щодоби.
  describe ".escalate_field_audit!" do
    let(:cluster) { create(:cluster) }

    it "creates an active cluster-level field_audit alert" do
      alert = described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")

      expect(alert).to be_persisted
      expect(alert.alert_type).to eq("field_audit")
      expect(alert.severity).to eq("critical")
      expect(alert.tree_id).to be_nil
    end

    it "skips (returns nil) while an active cluster field_audit already exists" do
      described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")

      expect {
        result = described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")
        expect(result).to be_nil
      }.not_to change(described_class, :count)
    end

    it "creates a fresh escalation after the previous one is resolved" do
      first = described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")
      first.update!(status: :resolved)

      second = described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")
      expect(second).to be_persisted
    end

    it "does not dedup across different clusters" do
      other_cluster = create(:cluster)
      described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")

      expect(described_class.escalate_field_audit!(cluster: other_cluster, message_key: "cluster_data_blackout")).to be_persisted
    end

    # 🔴 [ARCH.110] Дедуп тепер за (кластер, ПРИЧИНА). Доти продюсер, що приходив
    # другим, діставав `nil`, а виклик-сайти на `nil` не реагують за побудовою —
    # тобто після slash-freeze справжній blackout не був би записаний НІДЕ, хоч
    # це протилежні за змістом вироки з різними діями людини.
    it "не конфлатить РІЗНІ вердикти на одному кластері" do
      freeze = described_class.escalate_field_audit!(cluster: cluster,
                                                     message_key: "slash_frozen_no_evidence_cluster")
      blackout = described_class.escalate_field_audit!(cluster: cluster,
                                                       message_key: "cluster_data_blackout")

      expect(freeze).to be_persisted
      expect(blackout).to be_persisted
      expect(blackout.id).not_to eq(freeze.id)
    end

    # Дзеркало, без якого правило вище знімає анти-спам: ТОЙ САМИЙ продюсер
    # (щоденний cron при тривалій деградації) дедуплікується далі.
    it "той самий вердикт дедуплікується, як і доти" do
      described_class.escalate_field_audit!(cluster: cluster, message_key: "slash_frozen_no_evidence_cluster")

      expect(described_class.escalate_field_audit!(cluster: cluster,
                                                   message_key: "slash_frozen_no_evidence_cluster")).to be_nil
    end

    # Програна unique-гонка МУСИТЬ гаситись SAVEPOINT'ом: викликач (arm_candidate!)
    # тримає відкриту транзакцію — без requires_new PG-абортована транзакція тихо
    # перетворює імпліцитний COMMIT на ROLLBACK і trigger! зникає без ексепшена.
    it "does not poison an enclosing transaction when losing the unique race (savepoint)" do
      described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")
      # Сліпимо dedup-скан → create! реально б'ється об partial unique index.
      allow(described_class).to receive(:active_cluster_field_audit_for).and_return(nil)

      sibling = nil
      ActiveRecord::Base.transaction do
        sibling = create(:ews_alert, cluster: cluster, alert_type: :fire_detected, severity: :critical)
        expect(described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")).to be_nil
      end

      expect(sibling.reload).to be_persisted # зовнішня транзакція КОМІТНУЛАСЬ
    end
  end

  # [SILENCE-1] Per-tree гілка: dedup тримають модельна валідація + частковий
  # unique-index (..._unique_active_per_tree); скоупи ⊥ cluster-level.
  describe ".escalate_field_audit! (per-tree, SILENCE-1)" do
    let(:cluster) { create(:cluster) }
    let(:tree) { create(:tree, cluster: cluster) }

    it "creates an active per-tree field_audit alert" do
      alert = described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")

      expect(alert).to be_persisted
      expect(alert.alert_type).to eq("field_audit")
      expect(alert.severity).to eq("critical")
      expect(alert.tree_id).to eq(tree.id)
    end

    it "skips (returns nil) while an active per-tree field_audit already exists" do
      described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")

      expect {
        expect(described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")).to be_nil
      }.not_to change(described_class, :count)
    end

    it "coexists with an active cluster-level escalation in BOTH directions (⊥ dedup-скоупи)" do
      cluster_level = described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")
      per_tree = described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")

      expect(cluster_level).to be_persisted
      expect(per_tree).to be_persisted
      # І назад: активний per-tree не блокує новий cluster-level після resolve першого.
      cluster_level.update!(status: :resolved)
      expect(described_class.escalate_field_audit!(cluster: cluster, message_key: "cluster_data_blackout")).to be_persisted
    end

    it "does not dedup across different trees" do
      other_tree = create(:tree, cluster: cluster)
      described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")

      expect(
        described_class.escalate_field_audit!(cluster: cluster, tree: other_tree, message_key: "cluster_data_blackout")
      ).to be_persisted
    end

    it "creates a fresh escalation after the previous one is resolved" do
      first = described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")
      first.update!(status: :resolved)

      expect(described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")).to be_persisted
    end

    # 🔴 ДРУГИЙ КІНЕЦЬ ДИСКРИМІНАТОРА. `rescue RecordInvalid` ловить ВУЗЬКО —
    # `raise unless tree && e.record.errors.of_kind?(:alert_type, :taken)`, — і доти
    # пінили лише ту гілку, що ковтає (програну гонку). Тобто «вузькість» була
    # заявою без піна: якби гард розширили до голого `rescue RecordInvalid`, жоден
    # приклад не почервонів би, а справжній баг тихо повертав би `nil` замість
    # летіти. Тут пін на протилежний вихід: валідаційний збій, що НЕ є `:taken`,
    # мусить пробити rescue наскрізь.
    it "re-raises a validation failure that is NOT the dedup race (вузьке перехоплення)" do
      allow(described_class).to receive(:active_tree_field_audit_for).and_return(nil)
      invalid = described_class.new(cluster: cluster, tree: tree, severity: :critical,
                                    alert_type: :field_audit, message_key: nil)
      invalid.validate
      expect(invalid.errors.of_kind?(:alert_type, :taken)).to be(false) # не гонка — справжній збій
      allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

      expect {
        described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "does not poison an enclosing transaction when losing the unique race (savepoint)" do
      described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")
      # Сліпимо dedup-скан → create! б'ється об модельну uniqueness-валідацію
      # (committed-переможець видимий її SELECT'у) → вузький RecordInvalid-rescue
      # (:taken) → nil. TOCTOU-шлях повз валідацію (uncommitted-паралель →
      # RecordNotUnique з індексу) ділить rescue з cluster-гілкою — тест вище.
      allow(described_class).to receive(:active_tree_field_audit_for).and_return(nil)

      sibling = nil
      ActiveRecord::Base.transaction do
        sibling = create(:ews_alert, cluster: cluster, alert_type: :fire_detected, severity: :critical)
        expect(described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")).to be_nil
      end

      expect(sibling.reload).to be_persisted # зовнішня транзакція КОМІТНУЛАСЬ
    end

    # TOCTOU-шлях per-tree гілки ЧЕРЕЗ ІНДЕКС: переможець закомітився ПІСЛЯ
    # валідаційного SELECT'а, але ДО INSERT'а — валідація гонку не бачила (тут це
    # емулює зняття perform_validations), тож дубль бʼється об частковий
    # unique-index → RecordNotUnique → та сама ковтальна гілка, що в cluster-гонки,
    # але лог мусить назвати ДЕРЕВО. Доти tree-половина цього rescue жила без прогону.
    it "swallows a tree-side duplicate that slips past validation (TOCTOU → index), naming the tree" do
      described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")
      allow(described_class).to receive(:active_tree_field_audit_for).and_return(nil)
      allow_any_instance_of(described_class).to receive(:perform_validations).and_return(true)
      allow(Rails.logger).to receive(:info).and_call_original

      expect(
        described_class.escalate_field_audit!(cluster: cluster, tree: tree, message_key: "cluster_data_blackout")
      ).to be_nil
      expect(Rails.logger).to have_received(:info).with(/дереву #{Regexp.escape(tree.did)}/)
    end
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    describe "presence" do
      it "requires severity" do
        alert = build(:ews_alert, severity: nil)
        expect(alert).not_to be_valid
        expect(alert.errors[:severity]).to be_present
      end

      it "requires alert_type" do
        alert = build(:ews_alert, alert_type: nil)
        expect(alert).not_to be_valid
        expect(alert.errors[:alert_type]).to be_present
      end

      it "requires message_key (the message itself is now a render, not a column)" do
        alert = build(:ews_alert, message_key: nil)
        expect(alert).not_to be_valid
        expect(alert.errors[:message_key]).to be_present
        expect(alert.message).to be_nil
      end
    end

    describe "deduplication (Storm Protection)" do
      it "prevents duplicate active alerts for the same tree and alert_type" do
        tree = create(:tree)
        cluster = tree.cluster

        create(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :active)
        duplicate = build(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :active)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:alert_type]).to include("вже є активним для цього вузла")
      end

      it "allows same alert_type on different trees" do
        cluster = create(:cluster)
        tree_a = create(:tree, cluster: cluster)
        tree_b = create(:tree, cluster: cluster)

        create(:ews_alert, tree: tree_a, cluster: cluster, alert_type: :fire_detected, status: :active)
        second = build(:ews_alert, tree: tree_b, cluster: cluster, alert_type: :fire_detected, status: :active)

        expect(second).to be_valid
      end

      it "allows different alert_types on the same tree" do
        tree = create(:tree)
        cluster = tree.cluster

        create(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :active)
        second = build(:ews_alert, tree: tree, cluster: cluster, alert_type: :severe_drought, status: :active)

        expect(second).to be_valid
      end

      it "allows duplicate alert_type if previous alert is resolved" do
        tree = create(:tree)
        cluster = tree.cluster

        create(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :resolved)
        second = build(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :active)

        expect(second).to be_valid
      end

      it "skips uniqueness check when tree_id is nil (cluster-level alert)" do
        cluster = create(:cluster)

        create(:ews_alert, tree: nil, cluster: cluster, alert_type: :system_fault, status: :active)
        second = build(:ews_alert, tree: nil, cluster: cluster, alert_type: :system_fault, status: :active)

        expect(second).to be_valid
      end

      it "skips uniqueness check for non-active statuses" do
        tree = create(:tree)
        cluster = tree.cluster

        create(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :ignored)
        second = build(:ews_alert, tree: tree, cluster: cluster, alert_type: :fire_detected, status: :ignored)

        expect(second).to be_valid
      end
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".unresolved" do
      it "returns only active alerts" do
        active = create(:ews_alert, status: :active)
        _resolved = create(:ews_alert, status: :resolved)
        _ignored = create(:ews_alert, status: :ignored)

        expect(described_class.unresolved).to eq([ active ])
      end
    end

    describe ".critical" do
      it "returns only critical active alerts" do
        critical_active = create(:ews_alert, :fire)
        _medium_active = create(:ews_alert, :drought)
        _critical_resolved = create(:ews_alert, severity: :critical, alert_type: :fire_detected, status: :resolved)

        expect(described_class.critical).to eq([ critical_active ])
      end
    end

    describe ".recent" do
      it "returns alerts ordered by created_at desc, limited to 20" do
        old_alert = create(:ews_alert, created_at: 2.days.ago)
        new_alert = create(:ews_alert, created_at: 1.minute.ago)

        results = described_class.recent
        expect(results.first).to eq(new_alert)
        expect(results.last).to eq(old_alert)
      end
    end
  end

  # =========================================================================
  # CALLBACKS
  # =========================================================================
  describe "callbacks" do
    describe "after_create_commit :dispatch_notifications!" do
      it "enqueues AlertNotificationWorker" do
        restore_broadcasts!(:alert_notify)
        create(:ews_alert, :fire)

        expect(AlertNotificationWorker).to have_received(:perform_async).with(kind_of(Integer))
      end
    end

    # 🔴 [INF.26] Дім лічильника переїхав сюди з `DclimateVerificationWorker`, де він
    # стояв ще й під `if result`. Пін навмисно бере тип, якого СТАРИЙ сайт порахувати не
    # міг у принципі: `system_fault` не проходить `requires_satellite_consensus?`, тож у
    # dClimate-тракт не потрапляє — а метрика зветься «total EWS alerts». Плюс рядок без
    # кластера, бо такі теж лічаться (їх пише монітор скарбниці).
    describe "after_create_commit :count_created_alert" do
      it "counts an alert the satellite tract never sees (cluster-less system_fault)" do
        metric = SilkenNet::Metrics::EWS_ALERTS_TOTAL
        before_val = metric.get(labels: { alert_type: "system_fault" })

        create(:ews_alert, alert_type: :system_fault, severity: :critical, cluster: nil, tree: nil)

        expect(metric.get(labels: { alert_type: "system_fault" }) - before_val).to eq(1)
      end
    end

    describe "after_update_commit :count_satellite_verdict" do
      # [INF.26] Дім лічби — модель, а не сайт у `Dclimate::VerificationService`:
      # термінальних писачів `satellite_status` чотири, і один із них —
      # `sidekiq_retries_exhausted` у воркері, тобто ПОЗА сервісом. Пін на ПРИРІСТ,
      # не на `be > before`: другий зелений і при хибній мітці.
      it "рахує ТЕРМІНАЛЬНИЙ вердикт під його власною міткою" do
        metric = SilkenNet::Metrics::DCLIMATE_VERIFICATION_TOTAL
        alert  = create(:ews_alert, :fire)
        before_val = metric.get(labels: { result: "rejected_fraud" })

        alert.update!(satellite_status: :rejected_fraud)

        expect(metric.get(labels: { result: "rejected_fraud" }) - before_val).to eq(1)
      end

      # Початковий стан вердиктом не є — інакше лічильник рахував би СТВОРЕННЯ
      # алертів під виглядом супутникової відповіді.
      it "НЕ рахує повернення в `unverified` і зміни, що статусу не торкаються" do
        metric = SilkenNet::Metrics::DCLIMATE_VERIFICATION_TOTAL
        alert  = create(:ews_alert, :fire)
        alert.update!(satellite_status: :verified)
        before_val = metric.get(labels: { result: "unverified" })
        verified_before = metric.get(labels: { result: "verified" })

        alert.update!(satellite_status: :unverified)
        alert.update!(message_params: { "probe" => "no-status-change" })

        expect(metric.get(labels: { result: "unverified" })).to eq(before_val)
        expect(metric.get(labels: { result: "verified" }) - verified_before).to eq(0)
      end
    end

    describe "after_create_commit :schedule_satellite_verification!" do
      it "enqueues DclimateVerificationWorker for fire_detected" do
        allow(DclimateVerificationWorker).to receive(:perform_in).with(1.hour, kind_of(Integer))
        create(:ews_alert, :fire)

        expect(DclimateVerificationWorker).to have_received(:perform_in).with(1.hour, kind_of(Integer))
      end

      it "enqueues DclimateVerificationWorker for severe_drought" do
        allow(DclimateVerificationWorker).to receive(:perform_in).with(1.hour, kind_of(Integer))
        create(:ews_alert, :drought)

        expect(DclimateVerificationWorker).to have_received(:perform_in).with(1.hour, kind_of(Integer))
      end

      it "does not enqueue DclimateVerificationWorker for vandalism_breach" do
        allow(DclimateVerificationWorker).to receive(:perform_in)
        create(:ews_alert, alert_type: :vandalism_breach)

        expect(DclimateVerificationWorker).not_to have_received(:perform_in)
      end

      it "does not enqueue DclimateVerificationWorker for system_fault" do
        allow(DclimateVerificationWorker).to receive(:perform_in)
        create(:ews_alert, alert_type: :system_fault)

        expect(DclimateVerificationWorker).not_to have_received(:perform_in)
      end
    end
  end

  # =========================================================================
  # METHODS
  # =========================================================================
  describe "#resolve!" do
    it "sets status and resolved_at" do
      alert = create(:ews_alert, :drought)
      user = create(:user, :forester)

      alert.resolve!(user: user, notes: "Irrigation activated manually")
      alert.reload

      expect(alert).to be_status_resolved
      expect(alert.resolved_at).not_to be_nil
      expect(alert.resolver).to eq(user)
      # [I18N.1] Людська нотатка — text-запис як є (мова резолвера, не каталог).
      expect(alert.resolution_texts).to eq([ "Irrigation activated manually" ])
    end

    # [I18N.1] У БД лежить КЛЮЧ, не проза; дефолт деривується від агента закриття —
    # доти «Закрито системою» діставав і оператор, що лишив поле порожнім.
    it "logs a system_closed key when neither notes nor resolver are given" do
      alert = create(:ews_alert, :drought)
      alert.resolve!
      alert.reload

      expect(alert.resolution_log.last["key"]).to eq("system_closed")
      I18n.with_locale(:uk) do
        expect(alert.resolution_texts.join).to include("Закрито системою")
      end
    end

    it "logs an operator_closed key when a resolver leaves the note empty" do
      alert = create(:ews_alert, :drought)
      alert.resolve!(user: create(:user, :forester))
      alert.reload

      expect(alert.resolution_log.last["key"]).to eq("operator_closed")
    end

    it "returns true on success" do
      alert = create(:ews_alert, :drought)
      expect(alert.resolve!).to be true
    end

    it "clears the Redis silence filter" do
      alert = create(:ews_alert, :fire)
      silence_key = "ews_silence:#{alert.tree_id}:#{alert.alert_type}"
      Rails.cache.write(silence_key, true)

      alert.resolve!

      expect(Rails.cache.exist?(silence_key)).to be false
    end

    it "closes associated maintenance records" do
      alert = create(:ews_alert, :fire)

      allow(MaintenanceRecord).to receive(:where)
        .with(ews_alert_id: alert.id)
        .and_return(instance_double(ActiveRecord::Relation, update_all: 0))

      alert.resolve!

      expect(MaintenanceRecord).to have_received(:where).with(ews_alert_id: alert.id)
    end
  end

  describe "#message (param-label resolve)" do
    # [I18N.1] Свідок механізму живе в НЕ-базовій локалі навмисно: в en мітка
    # і сирий enum надто схожі, щоб приклад міг упасти на знятому резолві.
    it "резолвить token_type у мітку локалі глядача, а не сирий enum" do
      alert = build_stubbed(:ews_alert,
                            message_key: "mint_volume_anomaly",
                            message_params: { "token_type" => "forest_coin",
                                              "volume" => 12.5, "window" => "24h", "ceiling" => 10 })

      I18n.with_locale(:uk) do
        expect(alert.message).to include("Лісова монета Silken")
        expect(alert.message).not_to include("forest_coin")
      end
    end

    it "у базовій локалі мітка дорівнює ERC20-імені токена" do
      alert = build_stubbed(:ews_alert,
                            message_key: "mint_volume_anomaly",
                            message_params: { "token_type" => "carbon_coin",
                                              "volume" => 1, "window" => "24h", "ceiling" => 10 })

      expect(alert.message).to include("Silken Carbon Coin")
    end

    it "параметри без резолвера проходять у фразу як є" do
      alert = build_stubbed(:ews_alert,
                            message_key: "mint_volume_anomaly",
                            message_params: { "token_type" => "forest_coin",
                                              "volume" => 42.75, "window" => "24h", "ceiling" => 10 })

      expect(alert.message).to include("42.75")
    end

    it "resolution_texts резолвить той самий параметр тим самим домом" do
      alert = build_stubbed(:ews_alert, resolution_log: [
                              { "at" => "2026-08-20T06:00:00Z", "key" => "mint_volume_recovered",
                                "params" => { "token_type" => "forest_coin", "volume" => 5, "max" => 10 } }
                            ])

      I18n.with_locale(:uk) do
        text = alert.resolution_texts.join
        expect(text).to include("Лісова монета Silken")
        expect(text).not_to include("forest_coin")
      end
    end
  end

  describe "#coordinates" do
    it "returns tree coordinates when tree is present" do
      alert = create(:ews_alert, :drought)
      coords = alert.coordinates

      expect(coords).to eq([ alert.tree.latitude, alert.tree.longitude ])
    end

    it "falls back to cluster geo_center when tree has no GPS" do
      cluster = create(:cluster)
      tree = create(:tree, cluster: cluster, latitude: nil, longitude: nil)
      alert = create(:ews_alert, tree: tree, cluster: cluster)

      geo_center = { lat: 50.0, lng: 30.0 }
      allow(cluster).to receive(:geo_center).and_return(geo_center)

      coords = alert.coordinates
      expect(coords).to eq([ 50.0, 30.0 ])
    end

    # 🔴 [ARCH.82] Доти тут стояло `[0.0, 0.0]` «щоб не ламати Leaflet.js» — і
    # три піни цементували це як контракт. Нульова точка не є відсутністю: (0,0)
    # — Гвінейська затока. Ціна не косметична: єдиний споживач
    # (`Dclimate::VerificationService`) годує координати в ЗАПИТ ПРО ПОЖЕЖУ, а
    # його вердикт лягає на алерт як `satellite_status`, тобто як ДОКАЗ.
    it "віддає nil, коли координат немає — вигаданої точки більше нема" do
      cluster = create(:cluster)
      alert = create(:ews_alert, tree: nil, cluster: cluster)

      allow(cluster).to receive(:geo_center).and_return(nil)

      coords = alert.coordinates
      expect(coords).to be_nil
    end

    # Regression: cluster is optional (одиноке дерево / тестова інсталяція).
    # Раніше друга гілка крашила NoMethodError: undefined method `geo_center'
    # for nil, бо ішла через `cluster.geo_center` без safe-nav.
    it "does not raise when both tree and cluster are nil" do
      alert = build(:ews_alert, tree: nil, cluster: nil)
      expect { alert.coordinates }.not_to raise_error
      expect(alert.coordinates).to be_nil
    end

    it "віддає nil, коли дерево без GPS і кластера немає" do
      tree = create(:tree, latitude: nil, longitude: nil)
      alert = build(:ews_alert, tree: tree, cluster: nil)

      expect { alert.coordinates }.not_to raise_error
      expect(alert.coordinates).to be_nil
    end
  end

  describe "#actionable?" do
    it "returns true for critical fire" do
      alert = create(:ews_alert, :fire)
      expect(alert).to be_actionable
    end

    it "returns true for critical drought" do
      alert = create(:ews_alert, severity: :critical, alert_type: :severe_drought)
      expect(alert).to be_actionable
    end

    it "returns false for medium drought" do
      alert = create(:ews_alert, :drought)
      expect(alert).not_to be_actionable
    end

    it "returns false for critical vandalism" do
      alert = create(:ews_alert, severity: :critical, alert_type: :vandalism_breach)
      expect(alert).not_to be_actionable
    end

    it "returns false for low fire" do
      alert = create(:ews_alert, severity: :low, alert_type: :fire_detected)
      expect(alert).not_to be_actionable
    end
  end

  describe "#requires_satellite_consensus?" do
    it "returns true for fire_detected" do
      alert = build(:ews_alert, :fire)
      expect(alert.requires_satellite_consensus?).to be true
    end

    it "returns true for severe_drought" do
      alert = build(:ews_alert, :drought)
      expect(alert.requires_satellite_consensus?).to be true
    end

    it "returns false for vandalism_breach" do
      alert = build(:ews_alert, alert_type: :vandalism_breach)
      expect(alert.requires_satellite_consensus?).to be false
    end

    # [SLASH-1] chainsaw — НЕ страховий, але критичний acoustic-детект потребує незалежної
    # перевірки → non-fire маршрут dClimate веде у Field-Audit (без FIRMS-«ясне небо»-тавра).
    it "returns true for chainsaw_detected" do
      alert = build(:ews_alert, alert_type: :chainsaw_detected)
      expect(alert.requires_satellite_consensus?).to be true
    end

    it "returns false for system_fault" do
      alert = build(:ews_alert, alert_type: :system_fault)
      expect(alert.requires_satellite_consensus?).to be false
    end
  end

  # =========================================================================
  # THROTTLING
  # =========================================================================
  describe "broadcast throttling" do
    # 🔴 [UI.4] Пін на НАСЛІДОК, а не на механізм: попередній блок тут пінив
    # саму наявність константи й те, що `should_broadcast?` віддає `false` у
    # вікні, — тобто цементував поведінку, яка й була дефектом.
    #
    # Тротл був **leading-edge з ВИКИДАННЯМ**: перший виклик у вікні проходив,
    # решта гинули. Для сигналу «перечитай сторінку» це втрата саме ОСТАННЬОГО
    # оновлення — а останнє на тривозі це закриття. Ланцюг досяжний двома
    # акторами на ОДНІЙ тривозі: `Dclimate::VerificationService` пише
    # `satellite_status` (сигнал 1, ставить ключ), оператор тисне «закрити» в
    # тому ж вікні (сигнал 2 — у нікуди). Власна сторінка оператора оновиться
    # редиректом, а в усіх інших тривога лишиться активною.
    #
    # Гем при цьому вже робить правильну річ: `broadcast_refresh_later_to`
    # обгорнутий у `refresh_debouncer_for(...).debounce`, ключований ІМЕНЕМ
    # СТРІМУ і **trailing-edge** — останній виклик завжди виграє.
    it "сигналить і на оновлення, що йде ОДРАЗУ за попереднім (закриття не губиться)" do
      restore_broadcasts!(:alert_update)

      cluster = create(:cluster)
      alert   = create(:ews_alert, cluster: cluster, tree: nil)

      signals = []
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to) { |*args| signals << args }

      alert.log_resolution(text: "супутник підтвердив")
      alert.save!
      after_first = signals.size

      # Ліхтар: без непорожньої першої множини приклад був би зелений на нулі.
      expect(after_first).to be > 0,
                             "перше оновлення не дало жодного сигналу — приклад безпредметний"

      alert.resolve!(notes: "закрито оператором")

      expect(signals.size).to be > after_first,
                              "сигнал про ЗАКРИТТЯ не пішов — чужі відкриті сторінки лишаться з активною тривогою"
    end
  end

  # =========================================================================
  # NIL-SAFE BROADCAST (regression for одиноке дерево / cluster: nil)
  # =========================================================================
  describe "#broadcast_alert_update (nil-safe)" do
    it "is a silent no-op when cluster is nil (no NoMethodError on cluster.organization_id)" do
      # Дозволяємо реальний broadcast_alert_update (знімаємо outer stub) лише
      # для цього прикладу — інакше тест перевіряв би тільки stub.
      restore_broadcasts!(:alert_update)

      alert = create(:ews_alert, tree: nil, cluster: nil)

      # Без guard на `return unless cluster` `cluster.organization_id`
      # підриває NoMethodError при будь-якому update.
      expect { alert.update!(message_key: "hydrological_stress") }.not_to raise_error
    end
  end

  # =========================================================================
  # PRIVATE METHODS
  # =========================================================================
  describe "#clear_silence_filter! (private)" do
    it "deletes the Redis silence key for tree+alert_type" do
      alert = create(:ews_alert, :fire)
      silence_key = "ews_silence:#{alert.tree_id}:#{alert.alert_type}"
      Rails.cache.write(silence_key, true)

      alert.send(:clear_silence_filter!)

      expect(Rails.cache.exist?(silence_key)).to be false
    end

    it "does nothing when tree_id is nil" do
      alert = create(:ews_alert, tree: nil)

      allow(Rails.cache).to receive(:delete)
      alert.send(:clear_silence_filter!)

      expect(Rails.cache).not_to have_received(:delete)
    end
  end

  # =========================================================================
  # FACTORY TRAITS
  # =========================================================================
  describe "factory" do
    it "creates a valid default ews_alert" do
      expect(build(:ews_alert)).to be_valid
    end

    it "creates a valid drought alert" do
      alert = build(:ews_alert, :drought)
      expect(alert).to be_valid
      expect(alert).to be_severity_medium
      expect(alert).to be_alert_type_severe_drought
    end

    it "creates a valid fire alert" do
      alert = build(:ews_alert, :fire)
      expect(alert).to be_valid
      expect(alert).to be_severity_critical
      expect(alert).to be_alert_type_fire_detected
    end
  end

  describe "coordinates when tree is nil" do
    let(:cluster_coord) { create(:cluster) }

    it "falls back to cluster geo_center when tree is nil" do
      alert = create(:ews_alert, cluster: cluster_coord, tree: nil)
      allow(cluster_coord).to receive(:geo_center).and_return({ lat: 50.0, lng: 30.0 })
      expect(alert.coordinates).to eq([ 50.0, 30.0 ])
    end

    it "віддає nil, коли дерева немає, а кластер без geo_center" do
      alert = create(:ews_alert, cluster: cluster_coord, tree: nil)
      allow(cluster_coord).to receive(:geo_center).and_return(nil)
      expect(alert.coordinates).to be_nil
    end
  end

  describe "broadcast_alert_update execution" do
    let(:cluster_bc) { create(:cluster) }

    # 🔴 [UI.4] Тут стояли ТРИ блоки, що пінили знятий `should_broadcast?` —
    # включно з прикладом «skips broadcast when throttle cache exists», тобто
    # сюїта вимагала саме тієї поведінки, яка губила сигнал про закриття
    # тривоги. Живий інваріант — нижче: сигналів РІВНО два (панель кластера ⊥
    # org-список), і жоден із них не `replace`.
    it "sends both refresh signals and never a replace" do
      tree = create(:tree, cluster: cluster_bc)
      restore_broadcasts!(:alert_update)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
      alert = create(:ews_alert, cluster: cluster_bc, tree: tree)

      alert.send(:broadcast_alert_update)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).twice
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    # Пін саме на АДРЕСИ обох сигналів: «броадкаст стався» лишався б зеленим
    # і тоді, коли одна з двох поверхонь випала (саме так `Alerts::Index`
    # роками не бачила нових тривог — продюсер і підписник були на різних
    # стрімах). Плюс негативна половина: жодного рендереного HTML — рядок
    # несе десять `t()` і `TextFormatter`, тож push повернув би локаль
    # продюсера всім підписникам.
    it "signals BOTH surfaces and pushes no rendered markup to either" do
      tree = create(:tree, cluster: cluster_bc)
      restore_broadcasts!(:alert_update)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
      alert = create(:ews_alert, cluster: cluster_bc, tree: tree)

      Rails.cache.delete("ews_alert_broadcast_throttle:#{alert.id}")

      alert.send(:broadcast_alert_update)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with("ews_alerts_org_#{cluster_bc.organization_id}_e#{cluster_bc.organization.stream_epoch}")
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with([ cluster_bc, :alerts ])
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    # Осиротілий кластер. Досяжний лише не-AR записом (`belongs_to :organization`
    # обовʼязковий), АЛЕ два інші продюсери цієї осі його гасять явно, а тут ціна
    # мовчазно змінилась із переїздом на дім імен: до — броадкаст у мертве
    # СПІЛЬНЕ імʼя `ews_alerts_org_`, після — виняток усередині `after_*_commit`,
    # тобто Sidekiq-retry на вже закоміченій тривозі (їх створює й money-шлях).
    # Пін саме на fail-closed: панель кластера жива, org-сигнал просто мовчить.
    it "stays silent on the org stream when the cluster lost its organization" do
      tree = create(:tree, cluster: cluster_bc)
      # ⚠️ `and_call_original` тут ОБОВʼЯЗКОВИЙ, як і в сусідньому прикладі: у
      # цьому файлі метод заглушено, тож без нього `send` бʼє в заглушку й
      # приклад «проходить», не виконавши нічого — саме так він і збрехав під
      # час написання (0 викликів при цілком живому стані).
      restore_broadcasts!(:alert_update)
      alert = create(:ews_alert, cluster: cluster_bc, tree: tree)
      cluster_bc.update_columns(organization_id: nil)
      alert.cluster.reload

      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
      Rails.cache.delete("ews_alert_broadcast_throttle:#{alert.id}")

      expect { alert.send(:broadcast_alert_update) }.not_to raise_error
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with([ alert.cluster, :alerts ])
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_refresh_later_to)
        .with(a_string_matching(/\Aews_alerts_org_/))
    end
  end

  # =========================================================================
  # BROADCAST NEW ALERT (after_create_commit)
  # =========================================================================
  describe "broadcast_new_alert" do
    let(:cluster_bc) { create(:cluster) }

    before do
      restore_broadcasts!(:alert_new)
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_later_to)
    end

    it "signals the cluster panel instead of pushing a row into it" do
      tree = create(:tree, cluster: cluster_bc)

      create(:ews_alert, cluster: cluster_bc, tree: tree)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with([ cluster_bc, :alerts ])
      # Негативна половина несуча: панель тримає список як `<div>`-и, тож
      # будь-який повернутий сюди prepend знову вставляв би `<tr>` у `<div>`.
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_later_to)
    end

    # Регресія на дірку, що прожила непоміченою: сторінка списку підписана на
    # ОРГ-стрім, а продюсер слав лише в cluster-стрім — обидва кінці існували,
    # адреси не збігались, і нова тривога не з'являлась без перезавантаження.
    it "also signals the organization-wide alert list" do
      tree = create(:tree, cluster: cluster_bc)

      create(:ews_alert, cluster: cluster_bc, tree: tree)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with("ews_alerts_org_#{cluster_bc.organization_id}_e#{cluster_bc.organization.stream_epoch}")
    end

    it "skips broadcast when cluster is nil" do
      create(:ews_alert, cluster: nil, tree: nil)

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_refresh_later_to)
    end
  end

  # =========================================================================
  # AASM STATE MACHINE
  # =========================================================================
  describe "AASM state machine" do
    let(:cluster) { create(:cluster, organization: create(:organization)) }
    let(:tree) { create(:tree, cluster: cluster) }

    describe "initial state" do
      it "starts as active" do
        alert = build(:ews_alert, cluster: cluster, tree: tree, status: :active)
        expect(alert).to be_active
      end
    end

    describe "AASM #resolve via mark_resolved" do
      it "transitions from active to resolved" do
        alert = create(:ews_alert, cluster: cluster, tree: tree, status: :active)
        alert.resolve!
        expect(alert.reload).to be_resolved
      end

      it "rejects transition from ignored" do
        alert = create(:ews_alert, cluster: cluster, tree: tree)
        alert.update_columns(status: described_class.statuses[:ignored])
        alert.reload
        expect { alert.resolve! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "AASM #ignore event" do
      it "transitions from active to ignored" do
        alert = create(:ews_alert, cluster: cluster, tree: tree, status: :active)
        alert.ignore!
        expect(alert.reload).to be_ignored
      end
    end

    describe "AASM #reopen event" do
      it "transitions from resolved to active" do
        alert = create(:ews_alert, cluster: cluster, tree: tree)
        alert.update_columns(status: described_class.statuses[:resolved])
        alert.reload
        alert.reopen!
        expect(alert.reload).to be_active
      end
    end

    describe "may_ query methods" do
      it "reports valid transitions from active" do
        alert = build(:ews_alert, cluster: cluster, tree: tree, status: :active)
        expect(alert.may_mark_resolved?).to be true
        expect(alert.may_ignore?).to be true
        expect(alert.may_reopen?).to be false
      end
    end
  end

  # =========================================================================
  # [E.20] ДИСПЕТЧЕРИЗАЦІЯ — «хто зараз на гачку» ⊥ «хто закрив»
  # =========================================================================
  describe "assignment" do
    let(:organization) { create(:organization) }
    let(:forester) { create(:user, :forester, organization: organization) }
    let(:other_forester) { create(:user, :forester, organization: organization) }
    let(:admin) { create(:user, :admin, organization: organization) }
    # Фабрика сама будує cluster+tree — власні `let` тут не потрібні.
    let(:alert) { create(:ews_alert, status: :active) }

    describe "#claim!" do
      it "records the assignee and the moment of joining" do
        freeze_time do
          expect(alert.claim!(forester)).to be_truthy
          expect(alert.reload.assignee).to eq(forester)
          expect(alert.assigned_at).to eq(Time.current)
        end
      end

      # 🔴 Найдорожчий пін групи: `update!` на повторі зсунув би `assigned_at`,
      # тобто другий клік по власній кнопці МОВЧКИ покращував би власний SLA —
      # а саме різниця `assigned_at − created_at` і є Кат-A-сигналом `05_05 §2`.
      it "is a no-op on re-claim by the same user — the SLA clock must not move" do
        alert.claim!(forester)
        original = alert.reload.assigned_at

        travel 30.minutes do
          expect(alert.claim!(forester)).to be_truthy
          expect(alert.reload.assigned_at).to eq(original)
        end
      end

      it "refuses a claim on an alert someone else already took" do
        alert.claim!(forester)

        expect { alert.claim!(other_forester) }.to raise_error(EwsAlert::AlreadyAssigned)
        expect(alert.reload.assignee).to eq(forester)
      end

      # Гард стану живе на МОДЕЛІ, не лише в кнопці: інакше API фіксував би
      # приєднання після резолюції й отруював метрику, заради якої колонка є.
      it "refuses a claim on a closed alert" do
        alert.resolve!(user: forester)

        expect { alert.reload.claim!(other_forester) }.to raise_error(EwsAlert::AlertClosed)
        expect(alert.reload.assigned_to_id).to be_nil
      end
    end

    describe "#release!" do
      before { alert.claim!(forester) }

      it "clears both halves of the assignment" do
        expect(alert.release!(forester)).to be_truthy
        expect(alert.reload.assignee).to be_nil
        expect(alert.assigned_at).to be_nil
      end

      # Без цієї гілки один хибний клік замикав би тривогу на людині назавжди —
      # тобто ми створили б стан без виходу.
      it "lets an admin release someone else's alert" do
        expect(alert.release!(admin)).to be_truthy
        expect(alert.reload.assignee).to be_nil
      end

      it "refuses release by an unrelated forester" do
        expect { alert.release!(other_forester) }.to raise_error(EwsAlert::NotAssignee)
        expect(alert.reload.assignee).to eq(forester)
      end
    end
  end
end
