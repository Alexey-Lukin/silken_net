# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.25] Важіль відкликання Turbo-стрімів, окремий від `secret_key_base`.
#
# Пінить не «конфіг присвоєно» (це була б тавтологія — приклад повторив би той самий
# вираз, що й ініціалізатор), а ДВІ поведінки, заради яких важіль існує: що ротація
# секрета справді знецінює вже видані імена, і що за ВІДСУТНОСТІ секрета нічого не
# змінюється. Друге тут не менш важливе за перше: ініціалізатор свідомо без
# boot-guard'а, тож «ENV не заведено» мусить лишатись робочим станом, а не тихою
# поломкою. Канон — `04_04 §8.1`, ops-рецепт — `06_04 §5.9`.
RSpec.describe "turbo_stream_verifier initializer" do # rubocop:disable RSpec/DescribeClass
  # Ротація в проді — це новий процес із новим секретом. У межах одного процесу її
  # доводиться емулювати, і саме тут ховається пастка, заради якої цей коментар
  # написаний: `Turbo.signed_stream_verifier` МЕМОЇЗОВАНИЙ (`@signed_stream_verifier ||=`),
  # тож підміна самого ключа не робить нічого. Виміряно: без скиду мемо старе ім'я
  # лишається валідним, і приклад, який цього не знає, доводить протилежне тому, що
  # думає, ніби доводить.
  def rotate_to(key)
    Turbo.signed_stream_verifier_key = key
    Turbo.remove_instance_variable(:@signed_stream_verifier) if Turbo.instance_variable_defined?(:@signed_stream_verifier)
  end

  around do |example|
    original = Turbo.signed_stream_verifier_key
    example.run
  ensure
    rotate_to(original)
  end

  it "invalidates every already-issued stream name when the secret rotates" do
    rotate_to("generation-one")
    issued = Turbo::StreamsChannel.signed_stream_name("telemetry_stream_org_1_e1")

    expect(Turbo::StreamsChannel.verified_stream_name(issued)).to eq("telemetry_stream_org_1_e1")

    rotate_to("generation-two")

    expect(Turbo::StreamsChannel.verified_stream_name(issued)).to be_nil
  end

  # Дзеркальна половина: важіль не має бути ЄДИНИМ шляхом до робочого підпису,
  # інакше забутий ENV став би відмовою на рівному місці. Тестове середовище секрета
  # не має — отже ключ мусить лишитись деривованим із `secret_key_base`, як і до
  # цього ініціалізатора.
  it "falls back to the secret_key_base-derived key when no ENV secret is present" do
    expect(ENV.fetch("TURBO_SIGNED_STREAM_KEY", nil)).to be_blank
    expect(Turbo.signed_stream_verifier_key)
      .to eq(Rails.application.key_generator.generate_key("turbo/signed_stream_verifier_key"))
  end

  # Те, що робить важіль ЦІННИМ: він б'є лише стріми. Якби ключ лишався деривованим,
  # єдиною ротацією був би `secret_key_base` — а він вилогінює всіх і ламає CSRF,
  # `api_access` та підписані URL, тобто дорогий рівно там, де не допомагає.
  it "is a stream-only lever — rotating it leaves session and token signing untouched" do
    token = Rails.application.message_verifier(:test_surface).generate("payload")

    rotate_to("generation-three")

    expect(Rails.application.message_verifier(:test_surface).verified(token)).to eq("payload")
  end

  # 🔴 Стеля, названа чесно, бо без неї три приклади вище читаються сильніше, ніж є:
  # ЖОДЕН із них не почервонів би, якби ініціалізатор видалили. Причина структурна —
  # у тестовому середовищі `TURBO_SIGNED_STREAM_KEY` порожній, тож «конфіг заданий у
  # nil» і «конфіг не чіпали» дають той самий деривований ключ; фікс і дефект тут
  # виглядають ІДЕНТИЧНО, і жодна мутація цього не покаже. Тому єдине, що взагалі
  # можна тут пінити, — сам факт проводки й ім'я змінної, яке дублюється в `06_04 §5.9`
  # і в deploy-secrets. Це слабкий пін, і він свідомо названий слабким.
  it "keeps the wiring itself in place (the three examples above cannot see its absence)" do
    initializer = Rails.root.join("config/initializers/turbo_stream_verifier.rb")

    expect(initializer).to exist
    expect(initializer.read)
      .to include("config.turbo.signed_stream_verifier_key", 'ENV["TURBO_SIGNED_STREAM_KEY"]')
  end
end
