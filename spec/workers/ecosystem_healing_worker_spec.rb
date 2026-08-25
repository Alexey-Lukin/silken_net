# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EcosystemHealingWorker, type: :worker do
  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
  end

  describe "#perform" do
    context "when target is an Actuator with repair" do
      it "marks actuator as idle after repair" do
        actuator = create(:actuator, state: :maintenance_needed)
        record = build(:maintenance_record, :repair, maintainable: actuator)
        record.photos.attach(io: StringIO.new("fake"), filename: "photo.jpg", content_type: "image/jpeg")
        record.save!

        described_class.new.perform(record.id)

        actuator.reload
        expect(actuator.state).to eq("idle")
      end
    end

    context "when target is an already-idle Actuator with repair (preventive)" do
      it "skips deactivate (may_deactivate? false) without AASM::InvalidTransition" do
        actuator = create(:actuator, state: :idle)
        record = build(:maintenance_record, :repair, maintainable: actuator)
        record.photos.attach(io: StringIO.new("fake"), filename: "photo.jpg", content_type: "image/jpeg")
        record.save!

        expect { described_class.new.perform(record.id) }.not_to raise_error
        expect(actuator.reload.state).to eq("idle")
      end
    end

    context "when target is an already-removed Tree with decommissioning" do
      it "skips decommission (may_decommission? false) without raising" do
        tree = create(:tree, status: :removed)
        record = create(:maintenance_record, maintainable: tree, action_type: :decommissioning)

        expect { described_class.new.perform(record.id) }.not_to raise_error
        expect(tree.reload.status).to eq("removed")
      end
    end

    context "when target is a Tree with decommissioning" do
      it "sets tree status to removed" do
        tree = create(:tree, status: :active)
        record = create(:maintenance_record, maintainable: tree, action_type: :decommissioning)

        described_class.new.perform(record.id)

        tree.reload
        expect(tree.status).to eq("removed")
      end
    end

    # 🔴 [ARCH.76] Дзеркало прикладу вище, і саме воно було відсутнє: те, що для
    # Дерева є переходом стану, для Королеви не існує як механізм узагалі —
    # її enum це операційна петля без точки виходу. Доти такий запис
    # створювався, валідувався й тихо не робив нічого, тобто журнал стверджував
    # дію, якої не сталося. Пін тримає ГУЧНІСТЬ, а не стан: термінального стану
    # свідомо немає (присуд власника 2026-08-14 — відкликання довіри без
    # фізичного re-provision є театром).
    context "when target is a Gateway with decommissioning" do
      it "кричить у лог замість тихого no-op" do
        gateway = create(:gateway)
        record = create(:maintenance_record, maintainable: gateway, action_type: :decommissioning)

        allow(Rails.logger).to receive(:error).with(/ARCH\.76.*НЕ змінив стан/m)

        described_class.new.perform(record.id)

        expect(Rails.logger).to have_received(:error).with(/ARCH\.76.*НЕ змінив стан/m)
      end

      it "не вигадує шлюзу термінального стану" do
        gateway = create(:gateway)
        record = create(:maintenance_record, maintainable: gateway, action_type: :decommissioning)
        before_state = gateway.state

        described_class.new.perform(record.id)

        # Ліхтар: пін не про «нічого не сталось», а про те, що НЕ ЗʼЯВИВСЯ стан,
        # якого enum не має — інакше приклад був би зелений і на порожньому enum'і.
        expect(Gateway.states.keys).not_to include("retired", "revoked", "decommissioned")
        expect(gateway.reload.state).to eq(before_state)
      end
    end

    # -----------------------------------------------------------------
    # [ARCH.109] Людський запис НЕ пише машинний канал живості.
    #
    # 🔬 Піни навмисно читають СТАН ПІСЛЯ прогону воркера, а не мок на
    # `mark_seen!`: попередня форма пінила виклик, тож будь-яка інша дорога до
    # `last_seen_at` пройшла б повз неї. Дім класу — скіл `backend` #78.
    # -----------------------------------------------------------------
    describe "запис обслуговування на мовчазному вузлі" do
      it "лишає дерево мовчазним — пульс, тиша й вердикт про залізо незмінні" do
        silent_since = 3.days.ago
        tree = create(:tree, status: :active, last_seen_at: silent_since)
        record = create(:maintenance_record, maintainable: tree,
                                             action_type: :inspection, performed_at: 1.hour.ago)

        described_class.new.perform(record.id)

        expect(tree.reload.last_seen_at).to be_within(1.second).of(silent_since)
        expect(Tree.silent).to include(tree)
        expect(tree.fresh_signal?).to be false
        expect(record.reload.hardware_pulse_confirmed?).to be false
      end

      it "лишає шлюз мовчазним — `Gateway#online?` не оживає з паперу" do
        gateway = create(:gateway, last_seen_at: 3.days.ago)
        record = create(:maintenance_record, maintainable: gateway, action_type: :inspection)

        expect { described_class.new.perform(record.id) }
          .not_to change { gateway.reload.last_seen_at }

        expect(gateway.online?).to be false
      end
    end

    context "when associated EWS alert is active" do
      it "resolves the alert" do
        tree = create(:tree)
        alert = create(:ews_alert, cluster: tree.cluster, tree: tree, status: :active)
        record = build(:maintenance_record, :repair, maintainable: tree, ews_alert: alert)
        record.photos.attach(io: StringIO.new("fake"), filename: "photo.jpg", content_type: "image/jpeg")
        record.save!

        described_class.new.perform(record.id)

        alert.reload
        expect(alert.status).to eq("resolved")
        # [I18N.1] Ключ замість зашитої укр. прози; тип дії у фразі відсутній
        # СВІДОМО (сирий enum у перекладеному реченні — окремий клас).
        expect(alert.resolution_log.last["key"]).to eq("maintenance_restored")
        expect(alert.resolution_log.last["params"]["record_id"]).to eq(record.id)
        I18n.with_locale(:uk) do
          expect(alert.resolution_texts.join).to include("Відновлено")
        end
      end
    end

    context "when alert is already resolved" do
      it "does not re-resolve" do
        tree = create(:tree)
        alert = create(:ews_alert, cluster: tree.cluster, tree: tree, status: :resolved,
                                   resolved_at: 1.hour.ago,
                                   resolution_log: [ { "text" => "Already done" } ])
        record = create(:maintenance_record, maintainable: tree, ews_alert: alert)

        described_class.new.perform(record.id)

        alert.reload
        expect(alert.resolution_texts).to eq([ "Already done" ])
      end
    end

    it "raises RecordNotFound for missing record" do
      expect { described_class.new.perform(-1) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context "when target is a Gateway" do
      it "completes without error" do
        gateway = create(:gateway)
        record = create(:maintenance_record, maintainable: gateway, action_type: :inspection)

        expect { described_class.new.perform(record.id) }.not_to raise_error
      end
    end

    # -----------------------------------------------------------------
    # Afterlife Economy — Biomass Extraction (Puro.earth)
    # -----------------------------------------------------------------
    context "when target is a Tree with biomass_extraction" do
      # ⚖️ [E.20, 2026-08-25] Заявка більше НЕ вбиває дерево — обидві незворотні
      # дії (смерть + CORC-паспорт) переїхали за підпис другої пари очей.
      it "лишає дерево живим — смерть оголошує підпис, не заявка" do
        tree = create(:tree, status: :active)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, maintainable: tree)

        allow(PuroEarthPassportWorker).to receive(:perform_async)

        described_class.new.perform(record.id)

        expect(tree.reload.status).to eq("active")
      end

      it "не чіпає вже мертве дерево й не падає" do
        tree = create(:tree, status: :deceased)
        record = create(:maintenance_record, :biomass_extraction, :with_evidence, maintainable: tree)

        allow(PuroEarthPassportWorker).to receive(:perform_async)

        expect { described_class.new.perform(record.id) }.not_to raise_error

        tree.reload
        expect(tree.status).to eq("deceased")
      end

  # 🔴 [E.20, ⚖️ founder 2026-08-24] Контракт ЗМІНЕНО: пускачем незворотної заявки
  # є ПІДПИС, а не зцілення — цей воркер її більше не ставить у чергу ВЗАГАЛІ.
  # Доти enqueue був безумовним, і атестатор мав рівно стільки часу, скільки живе
  # джоба (`retry: 5` без власного `sidekiq_retry_in` ≈ 7–10 хв до DeadSet) —
  # дедлайн, що селектує підпис не дивлячись, тобто рівно ту профанацію, проти
  # якої правило «атестатор ≠ бенефіціар» і стоїть.
  it "не оголошує смерті й не подає заявки — обидва пускачі переїхали в підпис" do
    tree = create(:tree, status: :active)
    record = create(:maintenance_record, :biomass_extraction, :with_evidence, maintainable: tree)

    allow(PuroEarthPassportWorker).to receive(:perform_async)

    described_class.new.perform(record.id)

    # ⚖️ [E.20, 2026-08-25] Присуд ухвалено: гейт стереже ОБИДВІ незворотні ланки,
    # тож і смерть дерева тепер за підписом. Заявка сама по собі не робить нічого,
    # чого не можна відкликати.
    expect(tree.reload.status).to eq("active")
    expect(PuroEarthPassportWorker).not_to have_received(:perform_async)
  end

  # ⚠️ І для ЗААТЕСТОВАНОГО запису теж — інакше заявка подавалась би двічі
  # (вдруге вже з `attest!`). Пін мусить бути саме тут: «не ставить нікому»
  # відрізняється від «не ставить неатестованому» рівно цим прикладом.
  it "files no claim even for an already attested record (single trigger)" do
    tree = create(:tree, status: :active)
    record = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, maintainable: tree)

    allow(PuroEarthPassportWorker).to receive(:perform_async)

    described_class.new.perform(record.id)

    expect(PuroEarthPassportWorker).not_to have_received(:perform_async)
  end
end

# -----------------------------------------------------------------
# Transaction Safety (P0 Fix)
# -----------------------------------------------------------------
context "when the transaction rolls back mid-perform" do
  # 🔴 Пін ПЕРЕЦІЛЕНО двічі, і другий раз — цією ж сесією. Спершу він стеріг
  # «джоба не ставиться в чергу всередині транзакції»; далі — відкат
  # `declare_deceased!`. Після ⚖️ [E.20, 2026-08-25] смерть переїхала в
  # `attest!`, тож обидва предмети тут зникли, і приклад лишився б ЗЕЛЕНИМ на
  # порожній множині (мок на метод, якого воркер більше не кличе).
  # Дзеркало відкату підпису стоїть у `spec/models/maintenance_record_spec.rb`.
  #
  # Тут лишається інваріант, який у воркера ЖИВИЙ: крах у життєвому циклі дерева
  # мусить відкотити й закриття тривоги — інакше журнал стверджував би усунення
  # проблеми, якої ніхто не усунув.
  it "не закриває тривогу, коли життєвий цикл дерева впав" do
    tree = create(:tree, status: :active)
    alert = create(:ews_alert, cluster: tree.cluster, tree: tree, status: :active)
    record = create(:maintenance_record, maintainable: tree, ews_alert: alert,
                                         action_type: :decommissioning)

    allow_any_instance_of(Tree).to receive(:decommission!).and_raise(StandardError, "DB constraint violation")

    expect { described_class.new.perform(record.id) }.to raise_error(StandardError, /DB constraint/)

    expect(alert.reload.status).to eq("active")
    expect(tree.reload.status).to eq("active")
  end
    end
  end
end
