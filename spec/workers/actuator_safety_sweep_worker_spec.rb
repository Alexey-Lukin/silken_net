# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActuatorSafetySweepWorker, type: :worker do
  subject(:sweep) { described_class.new.perform }

  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, cluster: cluster, last_seen_at: Time.current) }

  # Актуатор, що числиться active довше за вікно свого наказу.
  #
  # Порядок несучий і сам є фактом про систему: звичайні накази мусять
  # народитись, доки актуатор ще `idle` — на активному `dispatch_to_edge!`
  # вбиває нову команду як «Актуатор недоступний» ще до того, як вона стане
  # pending. (Виняток — override: він гейт минає, і саме тому власний STOP
  # sweep'а створюється на ще-активному актуаторі без проблем.) Тому блок, де
  # тест створює решту наказів, виконується ПЕРЕД активацією.
  def stuck(duration: 60, elapsed: 2.hours, actuator: nil)
    actuator ||= create(:actuator, gateway: gateway)
    command = create(:actuator_command, actuator: actuator, duration_seconds: duration)
    yield(actuator) if block_given?
    actuator.mark_active!
    command.dispatch!
    command.acknowledge!
    command.update_columns(sent_at: elapsed.ago, executed_at: elapsed.ago)
    [ actuator.reload, command.reload ]
  end

  # Повторне залипання ПІСЛЯ проходу. Без нього тести дедупу зеленіли б
  # безпідставно: sweep повертає актуатор у `idle`, а прохід сканує лише
  # `Actuator.active` — тобто другий `perform` таку ціль не бачить узагалі, і
  # обидва гарди (self-STOP-як-pending, `stuck_alert_exists?`) можна було б
  # стерти без жодного червоного. Механізм, який вони стережуть, живе саме тут.
  def re_stick(actuator, elapsed: 2.hours)
    # `reload` ОБОВ'ЯЗКОВИЙ і саме тут: фабрика присвоює переданий ЕКЗЕМПЛЯР в
    # асоціацію, тож `dispatch_to_edge!` прочитав би стан із памʼяті («active»
    # з часів до проходу) і мовчки зафейлив би новий наказ як «недоступний».
    actuator.reload
    command = create(:actuator_command, actuator: actuator, duration_seconds: 60)
    actuator.mark_active!
    command.dispatch!
    command.acknowledge!
    command.update_columns(sent_at: elapsed.ago, executed_at: elapsed.ago)
    command.reload
  end

  describe "предикат залипання" do
    it "розчакловує актуатор, що пережив вікно свого наказу" do
      actuator, = stuck
      expect { sweep }.to change { actuator.reload.state }.from("active").to("idle")
    end

    it "НЕ чіпає актуатор, вікно якого ще триває" do
      actuator, = stuck(duration: 300, elapsed: 1.minute)
      expect { sweep }.not_to change { actuator.reload.state }
    end

    it "НЕ чіпає актуатор рівно на межі вікна (люфт ще не вичерпано)" do
      actuator, = stuck(duration: 60, elapsed: 60.seconds + described_class::STUCK_MARGIN - 30.seconds)
      expect { sweep }.not_to change { actuator.reload.state }
    end

    it "НЕ чіпає idle-актуатор із давнім наказом" do
      actuator, = stuck
      actuator.mark_idle!
      expect { sweep }.not_to change { actuator.reload.state }
    end

    it "мовчить про активний актуатор без жодного підтвердженого наказу (вікна нема)" do
      actuator = create(:actuator, gateway: gateway)
      actuator.mark_active!
      expect { sweep }.not_to change(EwsAlert, :count)
      expect(actuator.reload.state).to eq("active")
    end

    it "бере ВІКНО НАЙНОВІШОГО наказу, а не найстарішого" do
      fresh = nil
      actuator, = stuck(duration: 60, elapsed: 3.hours) do |a|
        fresh = create(:actuator_command, actuator: a, duration_seconds: 300)
      end
      fresh.dispatch!
      fresh.acknowledge!
      expect { sweep }.not_to change { actuator.reload.state }
    end
  end

  describe "нога STOP" do
    it "ставить override-STOP у чергу, коли живих наказів немає" do
      actuator, = stuck
      expect { sweep }.to change { actuator.commands.where(command_payload: "STOP").count }.by(1)
      stop = actuator.commands.find_by(command_payload: "STOP")
      expect(stop.priority_override?).to be(true)
      expect(stop.expires_at).to be > Time.current
    end

    it "НЕ ставить STOP, коли в черзі є живий наказ (його видача переозброїть Reset)" do
      actuator, = stuck { |a| create(:actuator_command, :with_ttl, actuator: a, duration_seconds: 60) }
      expect { sweep }.not_to change { actuator.commands.where(command_payload: "STOP").count }
    end

    it "протермінований наказ НЕ лічиться живим — STOP усе одно їде" do
      actuator, = stuck { |a| create(:actuator_command, :expired, actuator: a, duration_seconds: 60) }
      expect { sweep }.to change { actuator.commands.where(command_payload: "STOP").count }.by(1)
    end

    it "не плодить другий STOP при ПОВТОРНОМУ залипанні (власний STOP = живий pending)" do
      actuator, = stuck
      sweep
      re_stick(actuator)

      expect { described_class.new.perform }
        .not_to change { ActuatorCommand.where(command_payload: "STOP").count }
    end

    # Дзеркальний бік того самого гарду: коли власний STOP уже протермінувався,
    # він більше не «живий», і наступне залипання має право на новий.
    it "видає новий STOP, коли попередній уже протермінувався" do
      actuator, = stuck
      sweep
      actuator.commands.find_by(command_payload: "STOP").update_columns(expires_at: 1.minute.ago)
      re_stick(actuator)

      expect { described_class.new.perform }
        .to change { ActuatorCommand.where(command_payload: "STOP").count }.by(1)
    end

    # ⚠️ Перевіряємо на ОФЛАЙН-шлюзі свідомо. Наївна форма («на ще-активному
    # актуаторі») стала вакуумною, щойно `recover!` обгорнули транзакцією:
    # `dispatch_to_edge!` — це `after_commit`, тож він тепер біжить ПІСЛЯ
    # `deactivate!`, коли актуатор уже `idle` і гейт пропустив би STOP і без
    # винятку. Мертвий шлюз тримає `ready_for_deployment?` хибним незалежно від
    # стану актуатора — і це саме той продовий випадок, заради якого sweep існує.
    it "STOP минає readiness-гейт навіть на мертвому шлюзі (де гейт закритий і для idle)" do
      dead_gateway = create(:gateway, cluster: cluster, last_seen_at: Time.current)
      actuator, = stuck(actuator: create(:actuator, gateway: dead_gateway))
      # Шлюз помирає ПІСЛЯ видачі — саме так і виглядає залипання в полі.
      # (Мертвий від початку не пустив би навіть підготовчий наказ — що вже
      # доводить, наскільки гейт закритий.)
      dead_gateway.update_columns(last_seen_at: 2.hours.ago)

      sweep

      expect(actuator.commands.find_by(command_payload: "STOP").status_issued?).to be(true)
    end

    # Вік-межа поверх `live_pending`: наказ БЕЗ `expires_at` (а такою є кожна
    # команда від контролера) протермінуватись не може, тож на мертвому шлюзі
    # він інакше глушив би ногу STOP вічно.
    it "наказ, старший за власний TTL нашого STOP, більше не лічиться живим" do
      actuator, = stuck { |a| create(:actuator_command, actuator: a, duration_seconds: 60) }
      actuator.commands.status_issued.update_all(created_at: (described_class::STOP_TTL + 1.hour).ago)

      expect { sweep }.to change { actuator.commands.where(command_payload: "STOP").count }.by(1)
    end
  end

  describe "бухгалтерія наказів" do
    it "закриває загублений наказ як failed, а НЕ confirmed (виконання не доведене)" do
      _actuator, command = stuck
      sweep
      expect(command.reload.status_failed?).to be(true)
      expect(command.error_message).to include("Слід наказу загублено")
    end

    it "не чіпає наказ, вікно якого ще не вичерпане" do
      fresh = nil
      stuck(elapsed: 3.hours) { |a| fresh = create(:actuator_command, actuator: a, duration_seconds: 300) }
      fresh.dispatch!
      fresh.acknowledge!
      sweep
      expect(fresh.reload.status_acknowledged?).to be(true)
    end

    it "не чіпає наказ у :sent — він лежить у .pending і залікується наступною видачею" do
      pending_cmd = nil
      stuck { |a| pending_cmd = create(:actuator_command, actuator: a, duration_seconds: 60) }
      pending_cmd.dispatch!
      pending_cmd.update_columns(sent_at: 3.hours.ago)
      sweep
      expect(pending_cmd.reload.status_sent?).to be(true)
    end
  end

  describe "алерт" do
    it "піднімає критичний actuator_stuck із дедупом по актуатору" do
      actuator, command = stuck
      expect { sweep }.to change { EwsAlert.alert_type_actuator_stuck.count }.by(1)
      alert = EwsAlert.alert_type_actuator_stuck.last
      expect(alert.severity_critical?).to be(true)
      expect(alert.cluster_id).to eq(cluster.id)
      expect(alert.message_params["actuator_id"]).to eq(actuator.id)
      expect(alert.message_params["command_id"]).to eq(command.id)
    end

    it "не дублює алерт по тому самому актуатору при ПОВТОРНОМУ залипанні" do
      actuator, = stuck
      sweep
      re_stick(actuator)

      expect { described_class.new.perform }
        .not_to change { EwsAlert.alert_type_actuator_stuck.count }
    end

    it "піднімає новий алерт, коли попередній уже розвʼязано людиною" do
      actuator, = stuck
      sweep
      EwsAlert.alert_type_actuator_stuck.last.resolve!(user: create(:user), notes: "Оглянув клапан.")
      re_stick(actuator)

      expect { described_class.new.perform }
        .to change { EwsAlert.alert_type_actuator_stuck.count }.by(1)
    end

    it "дедуп per-actuator, НЕ per-cluster: сусідній актуатор того ж кластера отримує свій алерт" do
      stuck
      sweep
      stuck(actuator: create(:actuator, gateway: gateway))
      expect { described_class.new.perform }
        .to change { EwsAlert.alert_type_actuator_stuck.count }.by(1)
    end

    it "несе ключ зі STOP, коли STOP поставлено" do
      stuck
      sweep
      expect(EwsAlert.alert_type_actuator_stuck.last.message_key).to eq("actuator_stuck_stop_queued")
    end

    it "несе ключ без STOP, коли черга зайнята живим наказом" do
      stuck { |a| create(:actuator_command, :with_ttl, actuator: a, duration_seconds: 60) }
      sweep
      expect(EwsAlert.alert_type_actuator_stuck.last.message_key).to eq("actuator_stuck")
    end
  end

  describe "стійкість проходу" do
    # Дві властивості за один тест, і вони РІЗНІ: (1) збій відкочує роботу по
    # СВОЄМУ актуатору цілком — не лишає напів-стану; (2) прохід іде далі.
    # Стуб падає лише на першому виклику, інакше довести (2) неможливо: він
    # завалив би обидва однаково.
    it "збій відкочує СВІЙ актуатор, але не обриває решту флоту" do
      first, = stuck
      second, = stuck(actuator: create(:actuator, gateway: gateway))
      call = 0
      allow(EwsAlert).to receive(:create!).and_wrap_original do |orig, *args, **kwargs|
        call += 1
        raise ActiveRecord::RecordInvalid, EwsAlert.new if call == 1

        orig.call(*args, **kwargs)
      end

      sweep

      states = [ first.reload.state, second.reload.state ].sort
      expect(states).to eq([ "active", "idle" ])
      expect(EwsAlert.alert_type_actuator_stuck.count).to eq(1)
    end

    it "відкочений актуатор дожинається наступним проходом" do
      actuator, = stuck
      allow(EwsAlert).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(EwsAlert.new))
      sweep
      expect(actuator.reload.state).to eq("active")

      RSpec::Mocks.space.proxy_for(EwsAlert).reset
      expect { described_class.new.perform }.to change { actuator.reload.state }.to("idle")
    end
  end

  describe "метрика" do
    it "інкрементить лічильник відновлень із типом пристрою" do
      stuck
      allow(SilkenNet::Metrics::ACTUATOR_STUCK_RECOVERED_TOTAL)
        .to receive(:increment).with(labels: { device_type: "water_valve" })
      sweep

      expect(SilkenNet::Metrics::ACTUATOR_STUCK_RECOVERED_TOTAL)
        .to have_received(:increment).with(labels: { device_type: "water_valve" })
    end

    it "не інкрементить, коли нічого не залипло" do
      stuck(duration: 300, elapsed: 1.minute)
      allow(SilkenNet::Metrics::ACTUATOR_STUCK_RECOVERED_TOTAL).to receive(:increment)
      sweep

      expect(SilkenNet::Metrics::ACTUATOR_STUCK_RECOVERED_TOTAL).not_to have_received(:increment)
    end
  end
end
