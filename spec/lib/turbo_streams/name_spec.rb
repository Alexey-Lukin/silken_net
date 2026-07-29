# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Дім імен стрімів. Піни тут навмисно на ЛІТЕРАЛИ, а не на переспів логіки
# модуля: очікування мусить бути НЕЗАЛЕЖНИМ твердженням про бажаний результат,
# інакше приклад — тавтологія, що не може впасти (`04_06` BP; та сама вада, що
# колись зробила mailer-спеку зеленою на `.humanize`-дефекті).
#
# 🔴 І головне, що ці літерали справді пінять: вони мусять бути БАЙТ-У-БАЙТ
# тими самими рядками, які пінять спеки продюсерів (`tree_spec:346`,
# `ews_alert_spec:714,754`, `unpack_telemetry_worker_spec:63`,
# `ota_transmission_worker_spec:66`, `pending_queue_service_spec`) і підписників
# (`telemetry_controller_spec:41`, `alerts_controller_spec:157`,
# `dashboard_controller_spec:105`, `firmwares_controller_spec:176`,
# `gateways_controller_spec`). Розбіжність тут = тихо мертвий тракт.
RSpec.describe TurboStreams::Name do
  # Обʼєкт, що несе рівно те, чого дім вимагає: id + епоху. Саме ця пара, а не
  # голий id, і є контрактом [SEC.25 Ф3].
  let(:org) { instance_double(Organization, id: 42, stream_epoch: 3) }

  describe ".org" do
    it "builds the telemetry stream name" do
      expect(described_class.org(:telemetry, org)).to eq("telemetry_stream_org_42_e3")
    end

    it "builds the alerts stream name" do
      expect(described_class.org(:alerts, org)).to eq("ews_alerts_org_42_e3")
    end

    it "builds the map stream name" do
      expect(described_class.org(:map, org)).to eq("geospatial_matrix_org_42_e3")
    end

    # 🔴 ЦЕ і є вся Ф3 в одному рядку: та сама організація, інша епоха — інша
    # адреса. Без цього піна ротація могла б відвантажитись як no-op (напр. якби
    # епоха загубилась у форматі), і жоден інший приклад цього не показав би.
    it "moves the organization to a NEW address when the epoch advances" do
      rotated = instance_double(Organization, id: 42, stream_epoch: 4)

      expect(described_class.org(:telemetry, rotated))
        .not_to eq(described_class.org(:telemetry, org))
    end

    # Описка в ключі не повинна народжувати тихий новий стрім.
    it "raises on an unknown kind instead of inventing a stream" do
      expect { described_class.org(:teIemetry, org) }.to raise_error(KeyError)
    end

    # Гард fail-closed — і він ДОСЯЖНИЙ, тому тут пін, а не мертва гілка:
    # `..._org_` без id було б імʼям, спільним для всіх організацій.
    it "raises rather than mint an org-less name shared by every tenant" do
      expect { described_class.org(:telemetry, nil) }.to raise_error(ArgumentError, /спільним для всіх/)
      expect { described_class.org(:telemetry, instance_double(Organization, id: nil, stream_epoch: 3)) }
        .to raise_error(ArgumentError)
    end

    # Дзеркальний гард: `_e` без числа було б ОДНИМ імʼям на всі покоління, тобто
    # адресою, яку ротація не змогла б покинути. Досяжно не лише через nil-колонку
    # — обʼєкт із `select(:id)` приходить сюди так само.
    it "raises rather than mint an epoch-less name shared by every generation" do
      expect { described_class.org(:telemetry, instance_double(Organization, id: 42, stream_epoch: nil)) }
        .to raise_error(ArgumentError, /поколінь/)
    end

    # 🔴 Інваріант ІНВЕРТОВАНО [SEC.25 Ф3], і тому пін лишається: тут доти
    # стверджувалось, що голий `organization_id` і запис взаємозамінні. Тепер
    # голий id — помилка, бо епоху він не несе, а резолвити її всередині дому
    # означало б завести другу гілку, яка читає епоху в ІНШИЙ момент, ніж перша.
    it "rejects a bare organization id — the epoch has nowhere to come from" do
      expect { described_class.org(:telemetry, 42) }.to raise_error(ArgumentError, /спільним для всіх/)
    end
  end

  describe ".org_at" do
    # Вхід для tombstone'а: погасити треба ПОПЕРЕДНЮ адресу, а `org` за побудовою
    # знає лише поточну.
    it "builds the name of a specific past epoch" do
      expect(described_class.org_at(:alerts, 42, 2)).to eq("ews_alerts_org_42_e2")
    end

    # Байт-у-байт та сама адреса, яку `org` дав би за тієї епохи — інакше
    # tombstone летів би в імʼя, на яке ніхто ніколи не був підписаний.
    it "agrees with .org for the epoch the organization currently carries" do
      expect(described_class.org_at(:telemetry, 42, 3)).to eq(described_class.org(:telemetry, org))
    end
  end

  describe ".gateway_ota" do
    it "builds the OTA channel name from the gateway uid" do
      expect(described_class.gateway_ota("SNET-Q-ABCD1234")).to eq("ota_channel_SNET-Q-ABCD1234")
    end

    it "accepts a gateway record and its bare uid interchangeably" do
      gateway = instance_double(Gateway, uid: "SNET-Q-ABCD1234")

      expect(described_class.gateway_ota(gateway)).to eq(described_class.gateway_ota("SNET-Q-ABCD1234"))
    end

    it "raises on a blank uid" do
      expect { described_class.gateway_ota(nil) }.to raise_error(ArgumentError, /uid/)
    end
  end
end
