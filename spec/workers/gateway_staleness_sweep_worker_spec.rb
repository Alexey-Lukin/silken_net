# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.54 Шар 0] Dead-man switch Королеви: тиша → faulty + queen_offline,
# повернення в ефір → recover + resolve, attest-lapse — спостереження.
RSpec.describe GatewayStalenessSweepWorker, type: :worker do
  subject(:sweep) { described_class.new.perform }

  let(:cluster) { create(:cluster) }

  def silent_gateway(state: :active, silent_for: 10.minutes, sleep_s: 60)
    create(:gateway, cluster: cluster, state: state,
                     config_sleep_interval_s: sleep_s,
                     last_seen_at: silent_for.ago)
  end

  describe "мовчазний шлюз" do
    it "переводить у faulty і створює критичний EwsAlert(queen_offline)" do
      gateway = silent_gateway

      expect { sweep }.to change { gateway.reload.state }.from("active").to("faulty")
        .and change { EwsAlert.alert_type_queen_offline.count }.by(1)

      alert = EwsAlert.alert_type_queen_offline.last
      expect(alert.cluster_id).to eq(cluster.id)
      expect(alert.severity_critical?).to be(true)
      expect(alert.message).to include(gateway.uid)
    end

    it "не дублює активний алерт того ж кластера (анти-спам guard)" do
      silent_gateway
      sweep

      # Другий прохід: шлюз уже faulty (поза скоупом), алерт активний.
      expect { described_class.new.perform }
        .not_to change { EwsAlert.alert_type_queen_offline.count }
    end

    # 🔴 [ARCH.54] Доти цей приклад пінував ПРОТИЛЕЖНЕ під назвою «документована
    # стеля guard'а»: друга Королева не отримувала алерту взагалі. Дедуп-ключ був
    # вужчий за множину причин — два незалежні вердикти про два різні пристрої
    # зливались в один, і зникало саме СПОВІЩЕННЯ (у БД `faulty` ставився чесно).
    it "друга Королева ТОГО САМОГО кластера дістає ВЛАСНИЙ алерт (дедуп по uid, не по кластеру)" do
      first = silent_gateway
      sweep # перша впала → queen_offline активний

      second = silent_gateway # той самий cluster, ще active і вже прострочена

      expect { described_class.new.perform }
        .to change { EwsAlert.alert_type_queen_offline.count }.by(1)
      expect(second.reload.state).to eq("faulty")

      # Пін на СКЛАД, не на потужність: два алерти мусять називати РІЗНІ пристрої
      # — інакше «+1» задовольнив би й дубль про ту саму Королеву.
      uids = EwsAlert.alert_type_queen_offline.map { |a| a.message_params["uid"] }
      expect(uids).to contain_exactly(first.uid, second.uid)
    end

    # 🔴 Гард дедупу треба ПРОЙТИ, а не обійти. Попередник цього прикладу спершу
    # робив `sweep`, і шлюз ставав `faulty` — тобто вибував зі скоупу
    # `flag_silent_gateways`, і `create_offline_alert` не викликався ЖОДНОГО разу:
    # приклад був зелений при повністю знятому гарді. Тому алерт кладемо РУКАМИ,
    # а шлюз лишаємо в робочому стані — і ліхтар на `faulty` доводить, що прохід
    # його справді підхопив (без нього «нічого не змінилось» знову означало б
    # «нічого й не бігло»). Спіймано груповою підлогою покриття, не сюїтою.
    it "ту саму Королеву НЕ дублює — гард ПРОХОДИТЬСЯ, а не обходиться" do
      gateway = silent_gateway
      create(:ews_alert, cluster: cluster, severity: :critical,
                         alert_type: :queen_offline, status: :active,
                         message_params: { uid: gateway.uid })

      expect { sweep }.not_to change { EwsAlert.alert_type_queen_offline.count }
      expect(gateway.reload.state).to eq("faulty") # ліхтар: шлюз БУВ у скоупі
    end

    it "пропускає maintenance (людина вже знає)" do
      gateway = silent_gateway(state: :maintenance)
      expect { sweep }.not_to change { gateway.reload.state }
    end

    it "пропускає ніколи-не-бачених (last_seen_at nil — ще не народжений в ефірі)" do
      gateway = create(:gateway, cluster: cluster, state: :idle, last_seen_at: nil)
      expect { sweep }.not_to change { gateway.reload.state }
      expect(EwsAlert.alert_type_queen_offline.count).to eq(0)
    end

    it "не чіпає шлюз у межах sleep-інтервалу з люфтом" do
      gateway = create(:gateway, cluster: cluster, state: :active,
                                 config_sleep_interval_s: 3600,
                                 last_seen_at: 10.minutes.ago)
      expect { sweep }.not_to change { gateway.reload.state }
    end
  end

  describe "повернення в ефір" do
    it "recover'ить faulty-шлюз і резолвить queen_offline-алерт" do
      gateway = silent_gateway
      sweep
      alert = EwsAlert.alert_type_queen_offline.last

      gateway.reload.mark_seen! # свіжий last_seen_at → online
      expect { described_class.new.perform }
        .to change { gateway.reload.state }.from("faulty").to("idle")
      expect(alert.reload.status_resolved?).to be(true)
      expect(alert.resolution_log.last["key"]).to eq("gateway_returned")
      expect(alert.resolution_texts.join).to include(gateway.uid)
    end

    # [ARCH.34] Helium-SOS-алерт не мав резолвера ЖОДНОГО: HeliumSosWorker обіцяв
    # «sweeper-recovery після повернення батчів», але sweeper фільтрував лише
    # queen_offline → рядок лишався активним вічно й латчив comms_no_ack? назавжди.
    it "резолвить і queen_uplink_lost (Helium-SOS), не лише queen_offline" do
      gateway = silent_gateway
      # ⚠️ `uid` у фікстурі несучий: резолвер скоупиться парою cluster+uid
      # [ARCH.54], а живий писач (`HeliumSosWorker#create_sos_alert`) кладе його
      # від народження — фікстура без нього описувала б рядок, якого продюсер не
      # створює.
      sos = create(:ews_alert, cluster: cluster, severity: :critical,
                               alert_type: :queen_uplink_lost, status: :active,
                               message_params: { uid: gateway.uid })
      sweep

      gateway.reload.mark_seen! # свіжий last_seen_at → online
      described_class.new.perform

      expect(sos.reload.status_resolved?).to be(true)
    end

    # 🔴 [ARCH.54] Дзеркальна половина фіксу, і без неї він створив би НОВИЙ дефект,
    # гірший за початковий: сигнал не глушився б при народженні, а гасився б чужою
    # подією вже після того, як його побачила людина.
    it "повернення однієї Королеви НЕ резолвить алерт іншої, що досі faulty" do
      returning = silent_gateway
      staying   = silent_gateway
      sweep # обидві faulty, обидві мають власний queen_offline

      alert_of_staying = EwsAlert.alert_type_queen_offline
                                 .find { |a| a.message_params["uid"] == staying.uid }
      expect(alert_of_staying).to be_present # ліхтар: пін нижче не на порожнечі

      returning.reload.mark_seen! # у ефірі лише вона
      described_class.new.perform

      expect(alert_of_staying.reload.status_active?).to be(true)
      expect(EwsAlert.alert_type_queen_offline
                     .find { |a| a.message_params["uid"] == returning.uid }
                     .status_resolved?).to be(true)
    end

    # [SLASH-1 gap-E] Дискримінатор «машина vs людина» тримається на ДЕФОЛТНОМУ kwarg'у
    # resolve!(user: nil) — майбутній машинний resolve-сайт, що передасть system-user,
    # мовчки зламав би BlockchainBurningService#critical_unmaintained? (транзієнтна тиша
    # знову латчила б PF_NO_MAINTENANCE). Піна, щоб ламалось ГУЧНО, тут.
    it "лишає resolved_by NULL — машинний resolve мусить лишатись відрізнимим (gap-E)" do
      gateway = silent_gateway
      sweep
      alert = EwsAlert.alert_type_queen_offline.last

      gateway.reload.mark_seen!
      described_class.new.perform

      expect(alert.reload.resolved_by).to be_nil
    end
  end

  describe "метрики" do
    it "ставить gauge флоту та інкрементить лічильник переходів" do
      silent_gateway
      allow(SilkenNet::Metrics::GATEWAYS_OFFLINE_TOTAL).to receive(:increment)
      allow(SilkenNet::Metrics::GATEWAYS_FAULTY).to receive(:set).with(1)
      allow(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to receive(:set).with(0)

      sweep

      expect(SilkenNet::Metrics::GATEWAYS_OFFLINE_TOTAL).to have_received(:increment)
      expect(SilkenNet::Metrics::GATEWAYS_FAULTY).to have_received(:set).with(1)
      expect(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to have_received(:set).with(0)
    end
  end

  describe "attest-lapse (QATT-Королева без свіжого підпису)" do
    it "рахує online-шлюз з pubkey і простроченим last_attested_at" do
      gateway = create(:gateway, cluster: cluster, state: :active,
                                 config_sleep_interval_s: 3600,
                                 last_seen_at: 1.minute.ago,
                                 last_attested_at: 2.days.ago)
      create(:hardware_key, device_uid: gateway.uid,
                            ed25519_public_key_hex: "a" * 64)

      allow(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to receive(:set).with(1)
      allow(SilkenNet::Metrics::GATEWAYS_FAULTY).to receive(:set)

      sweep

      expect(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to have_received(:set).with(1)
    end

    it "рахує QATT-шлюз, що НІКОЛИ не атестувався (attested nil при pubkey)" do
      gateway = create(:gateway, cluster: cluster, state: :active,
                                 config_sleep_interval_s: 3600,
                                 last_seen_at: 1.minute.ago, last_attested_at: nil)
      create(:hardware_key, device_uid: gateway.uid,
                            ed25519_public_key_hex: "b" * 64)

      allow(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to receive(:set).with(1)
      allow(SilkenNet::Metrics::GATEWAYS_FAULTY).to receive(:set)

      sweep

      expect(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to have_received(:set).with(1)
    end

    it "не рахує L0-шлюз без pubkey" do
      create(:gateway, cluster: cluster, state: :active,
                       config_sleep_interval_s: 3600,
                       last_seen_at: 1.minute.ago, last_attested_at: nil)

      allow(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to receive(:set).with(0)
      allow(SilkenNet::Metrics::GATEWAYS_FAULTY).to receive(:set)

      sweep

      expect(SilkenNet::Metrics::GATEWAY_ATTEST_LAPSED).to have_received(:set).with(0)
    end
  end

  # [ARCH.59] Королева, що залипла в :updating. ⚠️ Шлюзи тут навмисно ONLINE
  # (`last_seen_at: 1.minute.ago`) — саме в цьому й дефект: `flag_silent_gateways`
  # вимагає `Gateway.offline`, тож stuck-OTA на живій Королеві був невидимий
  # НАЗАВЖДИ, і жоден інший прохід його не бачив.
  describe "залипла OTA-кампанія" do
    def updating_gateway(started_ago:, sleep_s: 3600, firmware_id: 77)
      create(:gateway, cluster: cluster, state: :updating,
                       config_sleep_interval_s: sleep_s,
                       last_seen_at: 1.minute.ago,
                       pending_firmware_id: firmware_id,
                       ota_started_at: started_ago&.ago)
    end

    it "звільняє шлюз, знімає кампанію і лишає версію прошивки незмінною" do
      gateway = updating_gateway(started_ago: 30.hours)
      version_before = gateway.firmware_version

      expect { sweep }.to change { gateway.reload.state }.from("updating").to("idle")

      expect(gateway.pending_firmware_id).to be_nil
      expect(gateway.ota_started_at).to be_nil
      # 🔴 Несуче: `idle` не сміє стверджувати УСПІХ оновлення.
      expect(gateway.firmware_version).to eq(version_before)
    end

    it "залишає слід алертом, який називає кампанію" do
      updating_gateway(started_ago: 30.hours, firmware_id: 42)

      expect { sweep }.to change { EwsAlert.where(message_key: "queen_ota_stuck").count }.by(1)

      alert = EwsAlert.find_by(message_key: "queen_ota_stuck")
      expect(alert.severity).to eq("medium")
      expect(alert.message_params["firmware_id"]).to eq(42)
    end

    # 🔴 Негативна половина, і без неї пін вище був би небезпечним: watchdog, що
    # не розрізняє живу кампанію, убивав би КОЖЕН OTA-деплой. Вікно виведене з
    # каденсу (4 чанки/флаш, флаш ≈ година), тож 2 години — нормальна кампанія.
    it "НЕ чіпає кампанію, що триває в межах вікна" do
      gateway = updating_gateway(started_ago: 2.hours)

      expect { sweep }.not_to(change { gateway.reload.state })
      expect(gateway.pending_firmware_id).to eq(77)
      expect(EwsAlert.where(message_key: "queen_ota_stuck")).to be_empty
    end

    # Backstop-предикат: стан без якоря. Живий код такого не створює
    # (`PendingQueueService` пише пару одним `update!`), але мертвий
    # `OtaTransmissionWorker` умів — і саме цей випадок sweep інакше не бачить.
    it "ловить :updating БЕЗ якоря ota_started_at" do
      gateway = updating_gateway(started_ago: nil)
      gateway.update_columns(updated_at: 30.hours.ago)

      expect { sweep }.to change { gateway.reload.state }.from("updating").to("idle")
    end

    it "не дублює алерт для тієї самої Королеви" do
      updating_gateway(started_ago: 30.hours)
      described_class.new.perform

      expect { described_class.new.perform }
        .not_to(change { EwsAlert.where(message_key: "queen_ota_stuck").count })
    end

    # [ARCH.59] Нога (3) — «затаргечений, але не анонсований»: кампанію записав
    # диспетчер, а hint не пішов ЖОДНОГО разу, тож `state` лишився робочим і
    # обидві ноги вище сліпі до нього ЗА ПОБУДОВОЮ (обидві вимагають
    # `:updating`). Сюди однаково сходяться шлюз без `hardware_key`, Королева,
    # що не поллить, і dangling `pending_firmware_id`.
    def targeted_gateway(dispatched_ago:, firmware_id: 91)
      create(:gateway, cluster: cluster, state: :idle,
                       last_seen_at: 1.minute.ago,
                       pending_firmware_id: firmware_id,
                       ota_started_at: dispatched_ago.ago)
    end

    it "ловить затаргечений шлюз, якому hint не пішов ЖОДНОГО разу" do
      gateway = targeted_gateway(dispatched_ago: 30.hours)

      expect { sweep }.to change { gateway.reload.pending_firmware_id }.from(91).to(nil)

      # 🔴 Стан НЕ чіпається: `finish_update!` тут кинув би InvalidTransition,
      # rescue проковтнув би його — і кампанія лишилась би висіти, а прохід
      # рахувався б виконаним.
      expect(gateway.state).to eq("idle")
      expect(gateway.ota_started_at).to be_nil
      expect(EwsAlert.where(message_key: "queen_ota_stuck").count).to eq(1)
    end

    # 🔴 Дзеркало, без якого нога (3) убивала б КОЖНУ щойно націлену кампанію:
    # між диспатчем і першим poll'ом шлюз штатно стоїть рівно в цьому стані.
    it "НЕ чіпає щойно націлену кампанію, яку ще не встигли анонсувати" do
      gateway = targeted_gateway(dispatched_ago: 2.hours)

      expect { sweep }.not_to(change { gateway.reload.pending_firmware_id })
      expect(EwsAlert.where(message_key: "queen_ota_stuck")).to be_empty
    end
  end

# 🔴 [ARCH.75] Пʼята нога: наказ, який уже НЕМОЖЛИВО доставити, мусить діставати
# термінальний стан — і поза poll-трактом.
#
# Механізм, чому без неї він лежить вічно. Термінатор у системі СПРОЄКТОВАНИЙ —
# `ActuatorCommandWorker` несе `sidekiq_retries_exhausted`, який ставить
# `failed`. Але FW.60 зняв push-тракт, і живих enqueuerʼів того воркера нуль
# (єдиний `perform_async` у дереві живе всередині коментаря), тож хук у проді
# не викликається ЖОДНОГО разу; сюїта тримає його зеленим, смикаючи руками.
# Лишається poll-тракт, а він матеріалізує кінець лише в момент видачі — тобто
# рівно тоді, коли шлюз ПРИХОДИТЬ. На шлюзі, що не прийде більше ніколи, наказ
# лишається `pending` назавжди.
#
# 🔴 Ціна не бухгалтерська: `live_pending` тримає 409 у контролері, а наказ від
# людини не має `expires_at` ВЗАГАЛІ (писачів TTL рівно два — протокольний
# `EmergencyResponseService` і STOP safety-свіпа), тож `scope :expired` його не
# матчить ніколи. Один клік по мертвому шлюзу назавжди відрізав форестера від
# цього актуатора.
#
# ⚖️ Дискримінатор — ПОДІЯ, не час (присуд founder 2026-08-17): наказ мертвий,
# коли його шлюз оголошено `faulty`. Сигнал уже ратифікований і рахується;
# часовий поріг завів би друге непідписане число поруч із відкритим ⚖️ про
# `relevance`. Свіп по стану (а не гачок на `report_fault!`) обраний тому, що
# шляхів у `faulty` ДВА — цей воркер і `HeliumSosWorker`, — тож гачок на один
# був би N−1 із N.
describe "недоставні накази на мертвому шлюзі [ARCH.75]" do
  # ⚠️ ФІКСТУРА тут несуча, і дві перші редакції були нереальні — система сама
  # це показала. (1) Наказ можна подати лише ЖИВІЙ Королеві: `dispatch_to_edge!`
  # (after_commit on create) валить його одразу, якщо актуатор не готовий, тож
  # «створити на вже-мертвому» не буває. (2) `faulty` зі СВІЖИМ `last_seen_at`
  # нога 2 повертає в `idle` ще до цієї ноги — і це правильно. Отже єдиний
  # чесний порядок: подати наказ живій, і лише потім замовкнути.
  def command_on(gateway, status: :issued)
    create(:actuator_command, status: status, actuator: create(:actuator, gateway: gateway))
  end

  def live_gateway
    create(:gateway, cluster: cluster, state: :active,
                     config_sleep_interval_s: 60, last_seen_at: Time.current)
  end

  # Замовкання ПІСЛЯ видачі наказу; `update_columns` — щоб не смикати колбеки.
  def go_silent!(gateway)
    gateway.update_columns(last_seen_at: 10.minutes.ago)
  end

  it "переводить у failed наказ, який уже неможливо доставити" do
    gateway = live_gateway
    command = command_on(gateway)
    go_silent!(gateway)
    gateway.report_fault! # уже мертва до початку проходу (напр. шлях HeliumSos)

    expect { sweep }.to change { command.reload.status }.from("issued").to("failed")
  end

  # 🔴 Половина, без якої гейт нічого не доводить: свіп, що валить УСЕ підряд,
  # проходить перший приклад так само.
  it "НЕ чіпає наказ на живому шлюзі" do
    command = command_on(live_gateway)

    expect { sweep }.not_to(change { command.reload.status })
  end

  # `pending` = issued+sent; наказ, що вже дійшов, термінувати нема за що.
  it "НЕ чіпає наказ, який Королева вже підтвердила" do
    gateway = live_gateway
    command = command_on(gateway, status: :acknowledged)
    go_silent!(gateway)
    gateway.report_fault!

    expect { sweep }.not_to(change { command.reload.status })
  end

  # 🔴 Порядок ніг несучий: Королева, що вмирає В ЦЬОМУ Ж проході, мусить лишити
  # по собі термінований наказ тим самим проходом — інакше він живе зайвий цикл
  # крону. Тут `report_fault!` НЕ кличеться: його робить нога 1.
  it "прибирає накази Королеви, яка замовкла саме в цьому проході" do
    gateway = live_gateway
    command = command_on(gateway)
    go_silent!(gateway)

    expect { sweep }.to change { command.reload.status }.from("issued").to("failed")
    expect(gateway.reload).to be_faulty
  end
end
end
