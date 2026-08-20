# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::Show do
  # [TEST.12] Реальний незбережений `Actuator` — `device_type` ходить через справжній
  # enum, тож вигаданого `"valve"` тут більше не буває (модель приймає лише
  # `water_valve`/`fire_siren`/`seismic_beacon`/`drone_launcher`).
  def build_actuator(id: 1, device_type: :water_valve, state: :active, gateway_uid: "QUEEN-01")
    Actuator.new(id: id, device_type: device_type, state: state, gateway: Gateway.new(uid: gateway_uid))
  end

  # [TEST.12] Реальний незбережений `ActuatorCommand`, і `user:` — реальний `User.new`,
  # не рукописний `OpenStruct`. `user: nil` тепер прямий вхід замість другої обгортки
  # навколо фікстури: доти "SYSTEM operator" будувала ЩЕ ОДИН `OpenStruct`, копіюючи
  # поля з першого, бо `user_first_name: nil` давав користувача з ПОРОЖНІМ імʼям, а
  # не `nil` — фікстуру доводилось «домовляти» замість того, щоб просто подати `nil`.
  def build_command(id: 1, status: "confirmed", command_payload: "OPEN_VALVE", executed_at: Time.current,
                    completed_at: nil, user: User.new(first_name: "Ada"))
    ActuatorCommand.new(id: id, status: status, command_payload: command_payload, executed_at: executed_at,
                        completed_at: completed_at, user: user)
  end

  describe "rendering" do
    let(:commands) { [ build_command(id: 1), build_command(id: 2, status: "failed", command_payload: "RESET") ] }
    let(:html) { render_component(actuator: build_actuator, commands: commands) }


    it "renders the Command Execution Log heading" do
      expect(html).to include("Command Execution Log")
    end

    it "displays table headers" do
      expect(html).to include("ID")
      expect(html).to include("Operator")
      expect(html).to include("Payload")
      expect(html).to include("Status")
      # Колонка показує `executed_at`, який модель ставить у `acknowledge` —
      # момент, коли дія ФІЗИЧНО ПОЧИНАЄТЬСЯ (клапан відкривається, сирена
      # вмикається). Стара мітка «Executed At» / lv «Izpildīts» / lt «Įvykdyta»
      # називала завершення, тобто журнал казав «виконано 14:32» поруч із
      # бейджем «виконується». Справжнє завершення — це `completed_at`, і воно
      # в UI не показується взагалі (→ 00_07 UI.4).
      expect(html).to include("Started")
    end

    it "renders command IDs" do
      expect(html).to include("#1")
      expect(html).to include("#2")
    end

    it "displays operator name" do
      expect(html).to include("Ada")
    end

    it "displays command payload" do
      expect(html).to include("OPEN_VALVE")
      expect(html).to include("RESET")
    end

    it "renders with role=table for accessibility" do
      expect(html).to include('role="table"')
    end
  end

  describe "SYSTEM operator fallback" do
    it "displays SYSTEM when user is nil" do
      html = render_component(actuator: build_actuator, commands: [ build_command(user: nil) ])
      expect(html).to include("SYSTEM")
    end
  end

  # [I18N.1] Тут раніше жили сім пінів на ВЛАСНУ палітру `cmd_status_class` —
  # другий, розійдений рендерер того самого стану: рукописний `<span>` із сирим
  # enum'ом і власними `border-*`-класами, тоді як `CommandStatusBadge` малює ті
  # самі стани через `bg-*` і локалізовану мітку. Тобто спека сумлінно пінила
  # дублікат. Тепер вісь інша: сторінка мусить ходити ЧЕРЕЗ спільний компонент —
  # це те, що не сміє зламатись, а конкретні класи належать спеці бейджа.
  describe "command status rendering" do
    it "delegates the status cell to the shared CommandStatusBadge" do
      html = render_component(actuator: build_actuator, commands: [ build_command(status: "confirmed") ])

      # DOM-id ставить саме компонент — його ж чекає broadcast-таргет.
      expect(html).to include("command_status_")
      expect(html).to include("bg-emerald-800")
    end

    it "renders the localized label, not the raw enum value" do
      html = I18n.with_locale(:uk) do
        render_component(actuator: build_actuator, commands: [ build_command(status: "acknowledged") ])
      end

      expect(html).to include("виконується")
      expect(html).not_to include(">acknowledged<")
    end

    # Найгостріший випадок класу: два фізично різні стани мусять читатись різними
    # словами, інакше оператор не відрізнить «сирена виє» від «сирена замовкла».
    it "renders acknowledged and confirmed as DIFFERENT words" do
      html = I18n.with_locale(:uk) do
        render_component(
          actuator: build_actuator,
          commands: [ build_command(status: "acknowledged"), build_command(status: "confirmed") ]
        )
      end

      expect(html).to include("виконується")
      expect(html).to include("завершено")
    end

    # ⚠️ Вхід досяжний ЛИШЕ стабом РИДЕРА: `status` — справжній enum
    # (issued/sent/acknowledged/failed/confirmed), тож
    # `ActuatorCommand.new(status: "unknown_status")` кидає `ArgumentError` просто
    # в конструкторі. Доти цю гілку «перевіряло» значення, якого прод не дає.
    it "falls back to the raw value for a status with no label" do
      command = build_command
      allow(command).to receive(:status).and_return("unknown_status")

      html = render_component(actuator: build_actuator, commands: [ command ])
      expect(html).to include("unknown_status")
      expect(html).to include("bg-zinc-800")
    end
  end

  describe "executed_at formatting" do
    # 🔴 [TEST.12] `Time.new` (без зони) дає ЛОКАЛЬНИЙ час машини; `executed_at` —
    # реальна `timestamp(6) without time zone`, і Rails кастує значення в
    # `Time.zone` (UTC тут). Виміряно `bin/rails runner`: та сама секунда, подана
    # `Time.new(2024, 3, 15, 14, 30, 45)` на машині з UTC+2, доїжджає до колонки як
    # `12:30:45`, тобто пін на «14:30:45» упав би на реальній моделі. `OpenStruct`
    # цього не показував — зберігав об'єкт як є, без каста. `Time.zone.local`
    # фіксує стінний час У ЗОНІ ЗАСТОСУНКУ, тож рядок детермінований незалежно від
    # TZ машини, що прогнала тест.
    it "formats execution timestamp" do
      time = Time.zone.local(2024, 3, 15, 14, 30, 45)
      html = render_component(actuator: build_actuator, commands: [ build_command(executed_at: time) ])
      expect(html).to include("15.03.24 // 14:30:45")
    end

    it "displays --- when executed_at is nil" do
      html = render_component(actuator: build_actuator, commands: [ build_command(executed_at: nil) ])
      expect(html).to include("---")
    end
  end

  # [I18N.1] Кінець дії — окрема колонка: `executed_at` ставиться в `acknowledge`
  # (старт), тож без `completed_at` «триває» і «завершилось» були нерозрізненні.
  describe "completed_at column" do
    it "shows both start and finish for a completed command" do
      html = render_component(
        actuator: build_actuator,
        commands: [ build_command(executed_at: Time.zone.local(2024, 3, 15, 14, 30, 45),
                                  completed_at: Time.zone.local(2024, 3, 15, 14, 32, 10)) ]
      )
      expect(html).to include("15.03.24 // 14:30:45")
      expect(html).to include("15.03.24 // 14:32:10")
    end

    # Свідок мітки — у НЕ-базовій локалі: в англійській заголовок легко сплутати
    # з сусіднім, а укр. пара «Початок ⊥ Завершення» доводить, що колонки ДВІ.
    it "labels start and finish as two distinct column headers (uk)" do
      html = I18n.with_locale(:uk) do
        render_component(actuator: build_actuator, commands: [ build_command ])
      end
      expect(html).to include("Початок")
      expect(html).to include("Завершення")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(actuator: build_actuator, commands: [ build_command ]) }

    it "uses text-tiny and text-micro for typography" do
      expect(html).to include("text-tiny")
      expect(html).to include("text-micro")
    end

    it "uses uppercase tracking for section headers" do
      expect(html).to include("tracking-widest")
    end
  end
end
