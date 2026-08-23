# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.34] Domain separation усіх HKDF-деривацій від ОДНОГО майстер-ключа.
#
# 🔴 Чому це не покривається нічим іншим. Усі ключі флоту деривуються з єдиного
# IKM (`PROVISIONING_MASTER_KEY`), тож єдине, що тримає два ключі різними, —
# унікальність пари `(salt, info)`. Колізія НЕ КИДАЄ: `OpenSSL::KDF.hkdf` віддає
# 32 бездоганні байти, provisioning проходить, і прошивка ПОГОДЖУЄТЬСЯ, бо
# деривує те саме хибне значення. Тобто зелено на кожному ярусі, а обіцянка
# «компрометація одного К-вектора не валить інші» тиха й порожня — і для KEYB
# після RDP-lock ротації не існує взагалі.
#
# ⚠️ ОГОЛОШЕНА СТЕЛЯ (читай перед тим, як діагностувати зелене):
#   1. Гейт судить КОНСТАНТИ, а не місця виклику. Деривація, що передасть
#      info-рядок літералом повз константу, тут невидима.
#   2. Salt НЕ порівнюється: він рантаймовий (`device_uid` · `"cluster:N"`), і
#      два різні сервіси законно ділять `"cluster:N"` (KEYB ⊥ K_ota). Саме тому
#      вся вага domain separation лежить на info — і саме тому його
#      унікальність мусить бути ГЕЙТОМ, а не домовленістю.
#   3. Конвенція «де живе ідентичність» НАВМИСНО різна між сервісами
#      (`HardwareKeyService` кладе її в salt, `SeedDerivation` — в info), і
#      вирівнювати її НЕ МОЖНА: `firmware/soldier/main.c` дзеркалить обидві
#      форми побайтово, тож зміна пере-ключила б увесь флот. Гейт цього не
#      судить свідомо.
RSpec.describe "HKDF domain separation [SEC.34]" do # rubocop:disable RSpec/DescribeClass
  # Кожен запис — «хто деривує» → info-рядок, яким він відділяє свій домен.
  # Новий ключ від того самого IKM ЗОБОВʼЯЗАНИЙ дописати сюди рядок.
  let(:info_strings) do
    {
      "HardwareKeyService::COAP_HKDF_INFO" => HardwareKeyService::COAP_HKDF_INFO,
      "HardwareKeyService::LORA_HKDF_INFO" => HardwareKeyService::LORA_HKDF_INFO,
      "HardwareKeyService::BROADCAST_HKDF_INFO" => HardwareKeyService::BROADCAST_HKDF_INFO,
      "HardwareKeyService::IOTEX_HKDF_INFO" => HardwareKeyService::IOTEX_HKDF_INFO,
      "OtaHmacKeyService::HKDF_INFO" => OtaHmacKeyService::HKDF_INFO,
      "SilkenNet::SeedDerivation::HKDF_INFO_PREFIX" => SilkenNet::SeedDerivation::HKDF_INFO_PREFIX
    }
  end

  it "derives every key family under a DISTINCT info-string" do
    duplicates = info_strings.group_by { |_name, info| info }
                             .select { |_info, pairs| pairs.size > 1 }

    detail = duplicates.map { |info, pairs| "  #{info.inspect} ← #{pairs.map(&:first).join(', ')}" }.join("\n")

    expect(duplicates).to be_empty,
                          "HKDF info-колізія — ці деривації дали б БАЙТ-У-БАЙТ однакові ключі " \
                          "на однаковій солі, і жоден рівень не почервонів би:\n#{detail}"
  end

  # Ліхтар популяції: без нього приклад вище зелений і на порожньому наборі —
  # рівно той клас, який корпус зве «пін на порожній множині».
  it "actually inspects the whole family (population lantern)" do
    expect(info_strings.size).to be >= 6
    expect(info_strings.values).to all(be_present)
  end

  # Вісь 2: голе імʼя `HKDF_INFO` жило у ДВОХ класах із різними значеннями, тож
  # `info: HKDF_INFO` у новому коді підхопило б те, що в лексичному скоупі.
  # Аліас у `HardwareKeyService` знято [SEC.34]; гейт тримає лінію.
  it "keeps the bare name HKDF_INFO in exactly ONE class" do
    owners = [ HardwareKeyService, OtaHmacKeyService, SilkenNet::SeedDerivation ].select do |klass|
      klass.const_defined?(:HKDF_INFO, false)
    end

    expect(owners.map(&:name)).to eq([ "OtaHmacKeyService" ]),
                                  "голе `HKDF_INFO` мусить мати ОДНОГО власника — інакше " \
                                  "`info: HKDF_INFO` у новій деривації означає різне залежно від файлу"
  end
end
