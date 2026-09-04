# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SLASH-1 2026-09-04] Гейт ДРУГОГО ДОМУ для родини `EwsAlert::GATEWAY_FAULT_TYPES`.
#
# Народився з правила БЕЗ НОСІЯ. Розкол кошика `system_fault` за атрибуцією
# (05_05 §6) тихо звузив ops-предикат `Gateway#system_fault?` — «чи їхати
# патрульному» є віссю ВИДИМОСТІ, ортогональною до осі «хто породив подію», і
# кожен наступний розкол ламав би її знову. Лік — One-Home-родина; але сама
# родина трималась ЛИШЕ коментарем «додавай сюди тим самим комітом», тобто
# рівно тим, що корпус уже назвав недостатнім.
#
# 🔒 Стеля, названа чесно:
#   · Гейт судить ПОКРИТТЯ, не правильність класифікації: він каже «жоден тип,
#     що його виробляє шлюзовий тракт, не випав із ops-осі», і не має думки про
#     те, чи тип узагалі мав бути заведений.
#   · Периметр — писачі, ЯКІ ДЕРИВУЮТЬ ТИП З КЛЮЧА. Писач, що хардкодить тип
#     повз мапу, сюди не потрапляє за побудовою; це свідомо — інакше гейт
#     вимагав би статичного розбору кожного `EwsAlert.create!` у дереві.
RSpec.describe "alert-type family parity: gateway writers ⟷ ops-visibility axis" do # rubocop:disable RSpec/DescribeClass
  # Liveness: без цього «0 порушень» означало б «0 перевірок», щойно константу
  # перейменують або мапа спорожніє.
  it "має непорожню мапу ключ→тип і непорожню ops-родину" do
    expect(GatewayTelemetryWorker::ALERT_TYPE_BY_MESSAGE_KEY).not_to be_empty
    expect(EwsAlert::GATEWAY_FAULT_TYPES).not_to be_empty
  end

  it "кожен тип, який виробляє шлюзовий писач, лишається на ops-осі" do
    produced = GatewayTelemetryWorker::ALERT_TYPE_BY_MESSAGE_KEY.values.map(&:to_sym).uniq
    missing  = produced - EwsAlert::GATEWAY_FAULT_TYPES

    expect(missing).to be_empty,
                       "тип(и) #{missing.join(', ')} виробляє `GatewayTelemetryWorker`, але їх немає в " \
                       "`EwsAlert::GATEWAY_FAULT_TYPES` — розкол кошика звузив `Gateway#system_fault?` мовчки"
  end

  it "родина не містить типу, якого немає в enum'і" do
    unknown = EwsAlert::GATEWAY_FAULT_TYPES.map(&:to_s) - EwsAlert.alert_types.keys

    expect(unknown).to be_empty,
                       "у родині стоїть неіснуючий тип: #{unknown.join(', ')}"
  end
end
