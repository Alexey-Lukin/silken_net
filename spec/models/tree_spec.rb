# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tree, type: :model do
  before do
    allow_any_instance_of(described_class).to receive(:broadcast_map_update)
  end

  describe "after_create callbacks" do
    it "creates a wallet after creation" do
      tree = create(:tree)

      expect(tree.wallet).to be_present
      expect(tree.wallet.balance).to eq(0)
    end
  end

  describe ".critical_stress scope" do
    it "returns trees with high stress from yesterday's AI insights" do
      tree = create(:tree, status: :active)
      create(:ai_insight, :daily_health_summary,
             analyzable: tree,
             target_date: Time.current.utc.to_date - 1,
             stress_index: 0.95)

      expect(described_class.critical_stress).to include(tree)
    end

    it "excludes trees with low stress" do
      tree = create(:tree, status: :active)
      create(:ai_insight, :daily_health_summary,
             analyzable: tree,
             target_date: Time.current.utc.to_date - 1,
             stress_index: 0.5)

      expect(described_class.critical_stress).not_to include(tree)
    end
  end

  describe "DID validation" do
    it "normalizes DID to uppercase" do
      tree = build(:tree, did: "snet-00000abc")
      tree.valid?

      expect(tree.did).to eq("SNET-00000ABC")
    end

    it "accepts valid hardware DID format" do
      tree = build(:tree, did: "SNET-1A2B3C4D")
      expect(tree).to be_valid
    end

    it "rejects DID that does not match hardware format" do
      tree = build(:tree, did: "INVALID-DID")
      expect(tree).not_to be_valid
      expect(tree.errors[:did]).to be_present
    end

    it "rejects DID with wrong length" do
      tree = build(:tree, did: "SNET-123")
      expect(tree).not_to be_valid
    end
  end

  describe "#mark_seen!" do
    it "updates last_seen_at" do
      tree = create(:tree)
      expect(tree.last_seen_at).to be_nil

      tree.mark_seen!
      tree.reload

      expect(tree.last_seen_at).not_to be_nil
      expect(tree.last_seen_at).to be_within(2.seconds).of(Time.current)
    end

    it "updates latest_voltage_mv when provided" do
      tree = create(:tree)

      tree.mark_seen!(4100)
      tree.reload

      expect(tree.latest_voltage_mv).to eq(4100)
    end

    it "never regresses last_seen_at (GREATEST semantics)" do
      tree = create(:tree)
      future_time = 1.hour.from_now

      tree.update_columns(last_seen_at: future_time)
      tree.mark_seen!
      tree.reload

      expect(tree.last_seen_at).to be_within(2.seconds).of(future_time)
    end
  end

  # 🔴 [ARCH.99, присуд founder 2026-08-13] Носій ВИДАЛЕННЯ, не поведінки.
  # Тут стояло вісім прикладів, що доводили арифметику `charge_percentage` й
  # `low_power?` — і всі вісім були зелені на фабрикації: вони годували фікстуру
  # напруженнями 2800…5500, яких `latest_voltage_mv` не бачить НІКОЛИ (BQ25570
  # стабілізує ту шину на 3.3 В, `02_03 §7`). Тобто сюїта доводила формулу на
  # вході, недосяжному за побудовою. Величина знята; цей приклад стереже, щоб
  # шкала «скільки лишилось» не повернулась на той самий непридатний вхід.
  # Повертати можна ЛИШЕ разом із живим Vcap-каналом (`00_07` FW.50).
  describe "energy semantics [ARCH.99]" do
    it "derives no charge scale from the regulated supply rail" do
      tree = build(:tree, latest_voltage_mv: 3300)

      expect(tree).not_to respond_to(:charge_percentage)
      expect(tree).not_to respond_to(:low_power?)
      expect(described_class.constants).not_to include(:VCAP_MIN_MV, :VCAP_MAX_MV, :LOW_POWER_MV)
      expect(tree.supply_voltage_mv).to eq(3300)
    end

    it "reads low energy as SILENCE, sharing one threshold with the sweeper scope" do
      fresh = build(:tree, last_seen_at: 1.hour.ago)
      quiet = build(:tree, last_seen_at: (Tree::SILENCE_THRESHOLD + 1.hour).ago)
      unborn = build(:tree, last_seen_at: nil)

      expect(fresh).to be_fresh_signal
      expect(quiet).not_to be_fresh_signal
      # ⊥ Свідома розбіжність зі `scope :silent`: той NULL відкидає (sweeper не
      # гонить Field Audit на вузол, що ще не виходив в ефір), глядачеві ж
      # «жодного пакета» — така сама відсутність свіжого сигналу.
      expect(unborn).not_to be_fresh_signal
    end
  end

  describe "#supply_voltage_mv" do
    it "returns latest_voltage_mv when present" do
      tree = build(:tree, latest_voltage_mv: 4200)
      expect(tree.supply_voltage_mv).to eq(4200)
    end

    # [ARCH.84] Доти цей приклад стверджував `eq(0)` — тобто цементував
    # ридер-підстановку як контракт. Нуль тут не нейтральний: на шині VDDA він
    # означає БРАУНАУТ, тож вузол, що ніколи не виходив в ефір, друкувався
    # найгіршим МОЖЛИВИМ виміром. Пін іде парою, бо сама лише перевірка на `nil`
    # не відрізняє «не виміряно» від «виміряно нуль».
    it "returns nil when latest_voltage_mv is nil — не виміряно, а не браунаут" do
      tree = build(:tree, latest_voltage_mv: nil)
      expect(tree.supply_voltage_mv).to be_nil
    end

    it "keeps a genuinely measured zero distinguishable from silence" do
      tree = build(:tree, latest_voltage_mv: 0)
      expect(tree.supply_voltage_mv).to eq(0)
    end
  end

  describe "#under_threat?" do
    it "returns true when tree has unresolved alerts" do
      tree = create(:tree)
      create(:ews_alert, tree: tree, cluster: tree.cluster, status: :active, severity: :medium)

      expect(tree).to be_under_threat
    end

    it "returns false when tree has no alerts" do
      tree = create(:tree)
      expect(tree).not_to be_under_threat
    end

    it "returns false when all alerts are resolved" do
      tree = create(:tree)
      create(:ews_alert, tree: tree, cluster: tree.cluster, status: :resolved, severity: :medium)

      expect(tree).not_to be_under_threat
    end
  end

  describe "#current_stress" do
    # 🔴 [ARCH.84] Доти приклад звався «returns 0.0 when latest_stress_index is
    # default» — і саме той дефолт був дефектом: `numeric(4,3) DEFAULT 0.0 NOT NULL`
    # давав ніколи-не-аналізованому дереву найкращий можливий стрес, а `.to_f` у
    # ридері добивав порожнечу до нуля. Дефолту більше немає, і ридер читає як є.
    it "returns nil when the tree was never analysed" do
      tree = create(:tree)

      expect(tree.latest_stress_index).to be_nil
      expect(tree.current_stress).to be_nil
    end

    # ⊥ Ліхтар проти вакууму: нуль лишається ДОСЯЖНИМ виміром (здорове дерево дає
    # рівно 0.0 — обидва доданки евристики інертні до ENV-калібрування), тож
    # «не виміряно» й «виміряно нулем» мусять лишатись відрізнимими.
    it "returns 0.0 when zero was actually measured" do
      tree = create(:tree, latest_stress_index: 0.0)

      expect(tree.current_stress).to eq(0.0)
      expect(tree.current_stress).not_to be_nil
    end

    it "returns latest_stress_index from denormalized column" do
      tree = create(:tree, latest_stress_index: 0.75)

      expect(tree.current_stress).to eq(0.75)
    end
  end

  describe "scopes" do
    describe ".active" do
      it "returns only active trees" do
        active = create(:tree, status: :active)
        dormant = create(:tree, status: :dormant)

        expect(described_class.active).to include(active)
        expect(described_class.active).not_to include(dormant)
      end
    end

    describe ".geolocated" do
      it "returns trees with both latitude and longitude" do
        located = create(:tree, latitude: 49.4, longitude: 32.0)
        unlocated = create(:tree, latitude: nil, longitude: nil)

        expect(described_class.geolocated).to include(located)
        expect(described_class.geolocated).not_to include(unlocated)
      end
    end

    # [SILENCE-1] Аномальна тиша: active + вже виходив в ефір + мовчить довше порога.
    describe ".silent" do
      it "returns active trees not seen beyond the default 24h threshold" do
        silent = create(:tree)
        silent.update_columns(last_seen_at: 25.hours.ago)

        recent = create(:tree)
        recent.update_columns(last_seen_at: 1.hour.ago)

        expect(described_class.silent).to include(silent)
        expect(described_class.silent).not_to include(recent)
      end

      it "accepts a custom threshold" do
        tree = create(:tree)
        tree.update_columns(last_seen_at: 2.hours.ago)

        expect(described_class.silent(1.hour)).to include(tree)
        expect(described_class.silent).not_to include(tree)
      end

      it "excludes never-seen trees (last_seen_at NULL — мовчання ненародженого)" do
        never_seen = create(:tree, last_seen_at: nil)

        expect(described_class.silent).not_to include(never_seen)
      end

      it "excludes legitimately-silent statuses (dormant/removed/deceased)" do
        %i[dormant removed deceased].each do |status|
          tree = create(:tree)
          tree.update_columns(status: status, last_seen_at: 25.hours.ago)

          expect(described_class.silent).not_to include(tree)
        end
      end
    end
  end

  # =========================================================================
  # FIRMWARE UPDATE STATUS (OTA Status Tracking)
  # =========================================================================
  describe "firmware_update_status" do
    it "defaults to fw_idle" do
      tree = build(:tree)
      expect(tree.firmware_update_status).to eq("fw_idle")
    end

    it "supports all OTA lifecycle states" do
      tree = build(:tree)
      %w[fw_idle fw_pending fw_downloading fw_verifying fw_flashing fw_failed fw_completed].each do |state|
        tree.firmware_update_status = state
        expect(tree.firmware_update_status).to eq(state)
      end
    end

    it "provides prefixed query methods" do
      tree = build(:tree, firmware_update_status: :fw_downloading)
      expect(tree).to be_firmware_fw_downloading
      expect(tree).not_to be_firmware_fw_idle
    end
  end

  describe "#latest_telemetry_log" do
    it "returns the most recent telemetry log" do
      tree = create(:tree)
      _old = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      newest = create(:telemetry_log, tree: tree, created_at: 1.minute.ago)

      expect(tree.latest_telemetry_log).to eq(newest)
    end

    it "returns nil when no telemetry exists" do
      tree = create(:tree)
      expect(tree.latest_telemetry_log).to be_nil
    end

    it "memoizes the result" do
      tree = create(:tree)
      create(:telemetry_log, tree: tree)

      first_call = tree.latest_telemetry_log
      second_call = tree.latest_telemetry_log

      expect(first_call).to equal(second_call)
    end
  end

  describe "current_stress when cluster is nil" do
    # ⚠️ [ARCH.84] Значення тут ЗАПИСАНЕ свідомо: приклад стверджує, що наявність
    # кластера нерелевантна, а з `nil` обабіч він став би вакуумним — nil із
    # правильної причини (колонка порожня) і nil із хибної (щось зламалось у
    # ридері) нерозрізнимі. Записане число робить твердження перевірним.
    it "reads the denormalized column regardless of cluster presence" do
      tree = create(:tree, latest_stress_index: 0.42)
      allow(tree).to receive(:cluster).and_return(nil)

      expect(tree.current_stress).to eq(0.42)
    end
  end

  # 🔴 [ARCH.84] Множина тригерів мусить дорівнювати множині КОЛОНОК, які маркер
  # рендерить (`Dashboard::MapNode`: lat · lng · status · stress). Доти вона
  # розходилась ОБАБІЧ, і обидві розбіжності тихі: стресу серед тригерів не було
  # (чесний колір не доїжджав наживо ЖОДНОГО разу), а напруга була — хоч ARCH.99
  # прибрав `data-charge` з маркера, тобто вузол перемальовувався на величину,
  # якої більше не малює, у механізмі, збудованому саме щоб скоротити броадкасти.
  describe "тригери мапи = колонки, які маркер справді малює [ARCH.84]" do
    def broadcasts_on(tree, **change)
      allow(tree).to receive(:broadcast_map_update)
      tree.update!(**change)
      tree
    end

    it "перемальовує маркер на зміну СТРЕСУ" do
      tree = create(:tree, latest_stress_index: 0.1)
      expect(broadcasts_on(tree, latest_stress_index: 0.8)).to have_received(:broadcast_map_update)
    end

    # ⊥ Дзеркало, без якого приклад вище доводив би лише «щось стріляє»:
    # напруга маркером НЕ рендериться, тож і перемальовувати нема за чим.
    it "НЕ перемальовує на зміну напруги — її маркер не несе (ARCH.99)" do
      tree = create(:tree, latest_voltage_mv: 3300)
      expect(broadcasts_on(tree, latest_voltage_mv: 4200)).not_to have_received(:broadcast_map_update)
    end

    it "перемальовує на координати й статус, як і доти" do
      expect(broadcasts_on(create(:tree), latitude: 50.0)).to have_received(:broadcast_map_update)
      expect(broadcasts_on(create(:tree), status: :dormant)).to have_received(:broadcast_map_update)
    end
  end

  describe "broadcast_map_update when latitude is nil" do
    it "returns nil without broadcasting when latitude is absent" do
      allow_any_instance_of(described_class).to receive(:broadcast_map_update).and_call_original
      tree = create(:tree)
      tree.update_columns(latitude: nil)
      tree.reload

      result = tree.broadcast_map_update
      expect(result).to be_nil
    end
  end

  describe "broadcast_map_update when longitude is nil" do
    it "returns nil without broadcasting when longitude is absent" do
      allow_any_instance_of(described_class).to receive(:broadcast_map_update).and_call_original
      tree = create(:tree)
      tree.update_columns(longitude: nil)
      tree.reload

      result = tree.broadcast_map_update
      expect(result).to be_nil
    end
  end

  # Стрім мапи несе координати й DID — ім'я стріму і є межею тенанта.
  # Пін саме на АРГУМЕНТ: «броадкаст стався» лишався б зеленим і для
  # голого `"geospatial_matrix"`, тобто для крос-тенант витоку.
  describe "#broadcast_map_update stream scoping" do
    before { allow_any_instance_of(described_class).to receive(:broadcast_map_update).and_call_original }

    it "broadcasts into the stream of the owning organization" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      tree = create(:tree, cluster: cluster, latitude: 49.44, longitude: 32.06)

      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      tree.broadcast_map_update

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with("geospatial_matrix_org_#{organization.id}_e#{organization.stream_epoch}",
              hash_including(target: "map_node_#{tree.id}"))
    end

    # ⚠️ Обґрунтування переписано ⚖️ 2026-07-30: доти тут стояло «звичайний стан після
    # видалення сектора (`dependent: :nullify`)», а каскад став `restrict_with_error` —
    # безкластерне дерево більше не є станом домену. Приклад лишається як РЕГРЕСІЙНИЙ
    # захист гарда (колонка ще nullable), а не як модель штатного сценарію: адреси
    # стріму в такого дерева нема, і глобальний ефір тут не запасний варіант.
    it "does not broadcast at all when the tree has no cluster" do
      tree = create(:tree, latitude: 49.44, longitude: 32.06, cluster: nil)

      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      tree.broadcast_map_update

      # Пін лише на ФАКТ відсутності броадкасту. `expect(...).to be_nil` тут
      # стояло б декоративно: стаб і так повертає nil, тож приклад був би
      # зеленим в обох світах — той самий клас, що «спека стверджує факт
      # виклику замість його аргументу».
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end
  end

  describe "ensure_calibration when calibration already exists" do
    it "does not create a new calibration if one exists" do
      tree = create(:tree)
      existing_cal = tree.device_calibration
      expect(existing_cal).not_to be_nil

      tree.send(:ensure_calibration)
      expect(tree.device_calibration.id).to eq(existing_cal.id)
    end
  end

  describe "NormalizeIdentifier concern" do
    it "does not modify did when it is blank" do
      tree = described_class.new(did: "", cluster: create(:cluster), tree_family: create(:tree_family))
      expect(tree.did).to eq("")
    end

    it "strips and upcases when did is present" do
      tree = described_class.new(did: " snet-0000abcd ", cluster: create(:cluster), tree_family: create(:tree_family))
      expect(tree.did).to eq("SNET-0000ABCD")
    end
  end

  # =========================================================================
  # AASM STATE MACHINE
  # =========================================================================
  describe "AASM state machine" do
    before do
      allow_any_instance_of(described_class).to receive(:broadcast_map_update)
    end

    describe "initial state" do
      it "starts as active" do
        tree = build(:tree, status: :active)
        expect(tree).to be_active
      end
    end

    describe "#suspend!" do
      it "transitions from active to dormant" do
        tree = create(:tree, status: :active)
        tree.suspend!
        expect(tree.reload).to be_dormant
      end

      it "rejects transition from removed" do
        tree = create(:tree)
        tree.update_columns(status: described_class.statuses[:removed])
        tree.reload
        expect { tree.suspend! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#reactivate!" do
      it "transitions from dormant to active" do
        tree = create(:tree)
        tree.update_columns(status: described_class.statuses[:dormant])
        tree.reload
        tree.reactivate!
        expect(tree.reload).to be_active
      end
    end

    describe "#decommission!" do
      it "transitions from active to removed" do
        tree = create(:tree, status: :active)
        tree.decommission!
        expect(tree.reload).to be_removed
      end
    end

    describe "#declare_deceased!" do
      it "transitions from active to deceased" do
        tree = create(:tree, status: :active)
        tree.declare_deceased!
        expect(tree.reload).to be_deceased
      end
    end

    describe "may_ query methods" do
      it "reports valid transitions from active" do
        tree = build(:tree, status: :active)
        expect(tree.may_suspend?).to be true
        expect(tree.may_reactivate?).to be false
        expect(tree.may_decommission?).to be true
        expect(tree.may_declare_deceased?).to be true
      end
    end
  end

  # [MRV.1] Tree-destroy НЕ обходить wallet-guard MRV-доказів: has_one dependent: :destroy
  # каскадить у Wallet#guard_mrv_evidence! (settled tx → abort) → дерево і його
  # заякорені телеметрія-листи лишаються (деактивуй, не видаляй).
  describe "destroy with settled money evidence" do
    it "aborts tree.destroy while a confirmed blockchain_transaction exists" do
      tree = create(:tree)
      create(:blockchain_transaction, wallet: tree.wallet, status: :confirmed,
                                      tx_hash: "0x#{SecureRandom.hex(32)}")

      expect { tree.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(described_class.exists?(tree.id)).to be true
      expect(Wallet.exists?(tree.wallet.id)).to be true
    end
  end
end
