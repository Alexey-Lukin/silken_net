# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [TEST.16] Один дім для глушіння побічних ефектів броадкасту в специ,
# ПРЕДМЕТОМ яких броадкаст не є.
#
# 🔴 Що саме тут не так без цього файлу, і чого тут НЕ вирішується.
# `allow_any_instance_of` жив у 317 сайтах / 101 файлі, і **57% allow-форми
# (170) — це п'ять одних і тих самих глушінь**, переписаних від руки. Копи, що
# їх ловлять, вимкнено з 2026-03-08 «на час поступової міграції», якої ніхто
# не ніс ([`OPS.33`]). Тобто це не гігієна: доки популяція така, присуд про
# `RSpec/AnyInstance` неможливо ухвалити — він дав би 317 червоних.
#
# ⚠️ І дуже важливе, що вимір СПРОСТУВАВ: вісь броадкасту НЕ є непінабельною.
# Вона має власний дім — `tree_spec` пінить, що `broadcast_map_update` стріляє
# на потрібних тригерах і НЕ стріляє на `latest_voltage_mv`; `wallet_spec`
# захоплює аргументи `broadcast_replace_to`; `maintenance_record_spec` тримає
# `have_received` разом із негативною половиною. Тож ці 170 глушінь — законні:
# вони мовчать про побічний ефект у файлах, що про інше. Цей модуль не лікує
# дефект — він робить глушіння **оголошеним** замість випадкового.
#
# ⛔ НЕ конвертувати сюди стаб із ХВОСТОМ (`.and_return`, `.and_raise`, блок,
# `.and_wrap_original`) — такий стаб не глушить, а ЗАДАЄ поведінку, і сховати
# його за іменем «silence» означало б збрехати про те, що робить рядок.
module BroadcastSilencer
  # Пара (клас, метод) на кожен ключ. Гранулярність ПОМЕТОДНА свідомо:
  # `EwsAlert` має три різні броадкасти, і файли глушать різні їх підмножини —
  # групування «весь EwsAlert» тихо додало б глушіння там, де сусідній приклад
  # може той самий броадкаст пінити.
  BROADCASTS = {
    tree_map: [ "Tree", :broadcast_map_update ],
    wallet_balance: [ "Wallet", :broadcast_balance_update ],
    alert_notify: [ "EwsAlert", :dispatch_notifications! ],
    alert_new: [ "EwsAlert", :broadcast_new_alert ],
    alert_update: [ "EwsAlert", :broadcast_alert_update ]
  }.freeze

  # `silence_broadcasts!(:tree_map, :wallet_balance)` — рівно 1:1 із тим, що
  # стояло рядками раніше; жодного ключа «за замовчуванням» немає навмисно.
  def silence_broadcasts!(*keys)
    raise ArgumentError, "silence_broadcasts! потребує щонайменше один ключ" if keys.empty?

    keys.each do |key|
      klass_name, method = BROADCASTS.fetch(key) do
        raise ArgumentError, "невідомий ключ броадкасту #{key.inspect}; відомі: #{BROADCASTS.keys.join(", ")}"
      end
      # 🔑 ЄДИНИЙ санкціонований `allow_any_instance_of` у дереві: екземпляри
      # створює код під тестом, тож дістати їх до `allow(instance)` ніде. Стабити
      # натомість `Turbo::StreamsChannel` не можна — тіло методу рендерить
      # Phlex-компонент, і той рендер лишився б у КОЖНОМУ прикладі.
      # ⚠️ Директиви `rubocop:disable RSpec/AnyInstance` тут НЕМАЄ навмисно: коп
      # поки вимкнений глобально, тож директива була б зайвою — і це не здогад,
      # її зловив `Lint/RedundantCopDisableDirective` при першій же спробі.
      # У день, коли ⚖️ увімкне `RSpec/AnyInstance`, директиву треба ПОВЕРНУТИ
      # рівно сюди: цей рядок є її єдиним законним домом.
      allow_any_instance_of(klass_name.constantize).to receive(method)
    end
  end
end

RSpec.configure do |config|
  config.include BroadcastSilencer
end
