# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [TEST.16 · OPS.33] Один дім для глушіння побічних ефектів у специ, ПРЕДМЕТОМ
# яких той ефект не є.
#
# 🔴 Що саме тут не так без цього файлу, і чого тут НЕ вирішується.
# `allow_any_instance_of` жив сотнями сайтів, і більшість `allow`-форми — це
# кілька одних і тих самих глушінь, переписаних від руки. Копи, що їх ловлять,
# були вимкнені «на час поступової міграції», якої ніхто не ніс ([`OPS.33`]).
# Тобто це не гігієна: доки популяція така, присуд про `RSpec/AnyInstance`
# неможливо ухвалити — він дав би сотні червоних.
#
# ⚠️ І дуже важливе, що вимір СПРОСТУВАВ: вісь броадкасту НЕ є непінабельною.
# Вона має власний дім — `tree_spec` пінить, що `broadcast_map_update` стріляє
# на потрібних тригерах і НЕ стріляє на `latest_voltage_mv`; `wallet_spec`
# захоплює аргументи `broadcast_replace_to`; `maintenance_record_spec` тримає
# `have_received` разом із негативною половиною. Тож ці глушіння законні:
# вони мовчать про побічний ефект у файлах, що про інше. Цей модуль не лікує
# дефект — він робить глушіння **оголошеним** замість випадкового.
#
# ⛔ НЕ конвертувати сюди стаб із ХВОСТОМ (`.and_return`, `.and_raise`, блок,
# `.and_wrap_original`) — такий стаб не глушить, а ЗАДАЄ поведінку, і сховати
# його за іменем «silence» означало б збрехати про те, що робить рядок.
#
# 🔑 ЧОМУ ДВА МЕТОДИ, а не один [OPS.33, 2026-08-24]. Реєстр виріс за межі
# броадкастів: `dispatch_to_edge!` — це LoRa-відправка, `check_cluster_health!`
# — каскад по моделі. Скласти їх під імʼя `silence_broadcasts!` означало б дати
# рядкам назву, яка про них бреше. Перейменувати ж єдиний метод коштувало б
# ~сотні call-site'ів і лишило б протухлий опис в архівному рядку. Тож
# перейменовано МОДУЛЬ (кілька посилань), а методи розведено за предметом —
# кожна назва тепер точна, і жоден наявний виклик не зачеплено.
module SideEffectSilencer
  # Пара (клас, метод) на кожен ключ. Гранулярність ПОМЕТОДНА свідомо:
  # `EwsAlert` має кілька різних ефектів, і файли глушать різні їх підмножини —
  # групування «весь EwsAlert» тихо додало б глушіння там, де сусідній приклад
  # може той самий ефект пінити.
  BROADCASTS = {
    tree_map: [ "Tree", :broadcast_map_update ],
    wallet_balance: [ "Wallet", :broadcast_balance_update ],
    alert_notify: [ "EwsAlert", :dispatch_notifications! ],
    alert_new: [ "EwsAlert", :broadcast_new_alert ],
    alert_update: [ "EwsAlert", :broadcast_alert_update ],
    tx_status: [ "BlockchainTransaction", :broadcast_status_change ]
  }.freeze

  # Не-броадкастові побічні ефекти: вихідна відправка, планування зовнішньої
  # роботи, каскад по моделі. Той самий механізм, інший предмет.
  SIDE_EFFECTS = {
    actuator_dispatch: [ "ActuatorCommand", :dispatch_to_edge! ],
    satellite_verification: [ "EwsAlert", :schedule_satellite_verification! ],
    maintenance_cascade: [ "EwsAlert", :close_associated_maintenance! ],
    cluster_health_recalc: [ "Cluster", :recalculate_health_index! ],
    naas_health_check: [ "NaasContract", :check_cluster_health! ]
  }.freeze

  # `silence_broadcasts!(:tree_map, :wallet_balance)` — рівно 1:1 із тим, що
  # стояло рядками раніше; жодного ключа «за замовчуванням» немає навмисно.
  def silence_broadcasts!(*keys)
    silence_from!(BROADCASTS, keys, "silence_broadcasts!", SIDE_EFFECTS, "silence_side_effects!")
  end

  # `silence_side_effects!(:actuator_dispatch)` — сіблінг для не-броадкастів.
  def silence_side_effects!(*keys)
    silence_from!(SIDE_EFFECTS, keys, "silence_side_effects!", BROADCASTS, "silence_broadcasts!")
  end

  private

  # ⚠️ Помилка НАЗИВАЄ сусідній реєстр, а не лише «невідомий ключ»: два методи
  # мають ціну лише тоді, коли викликач мусить угадувати, який із них його.
  # Тут не мусить — промах відповідає адресою.
  def silence_from!(registry, keys, own_name, sibling, sibling_name)
    raise ArgumentError, "#{own_name} потребує щонайменше один ключ" if keys.empty?

    keys.each do |key|
      klass_name, method = registry.fetch(key) do
        if sibling.key?(key)
          raise ArgumentError, "ключ #{key.inspect} належить реєстру #{sibling_name} — клич його"
        end
        raise ArgumentError, "невідомий ключ #{key.inspect}; відомі #{own_name}: #{registry.keys.join(', ')}"
      end
      # 🔑 ЄДИНИЙ санкціонований `allow_any_instance_of` у дереві: екземпляри
      # створює код під тестом, тож дістати їх до `allow(instance)` ніде. Стабити
      # натомість `Turbo::StreamsChannel` не можна — тіло методу рендерить
      # Phlex-компонент, і той рендер лишився б у КОЖНОМУ прикладі.
      # ⚠️ Директиви `rubocop:disable RSpec/AnyInstance` тут НЕМАЄ навмисно: коп
      # вимкнений глобально ратифікованим присудом, тож директива була б зайвою —
      # і це не здогад, її зловив `Lint/RedundantCopDisableDirective`.
      # Якщо присуд колись перевернуть — директиву повернути рівно сюди.
      allow_any_instance_of(klass_name.constantize).to receive(method)
    end
  end
end

RSpec.configure do |config|
  config.include SideEffectSilencer
end
