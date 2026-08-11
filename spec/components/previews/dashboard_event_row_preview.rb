# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# @label Dashboard Event Row
# @display bg_color "#000"
class DashboardEventRowPreview < Lookbook::Preview
  # @label EWS Alert Event
  # @notes Renders a critical threat detection event in the live feed.
  def ews_alert
    alert = mock_ews_alert
    render Dashboard::EventRow.new(event: alert)
  end

  # @label Blockchain Mint Event
  # @notes Renders a SCC minting transaction in the live feed.
  def blockchain_transaction
    tx = mock_blockchain_tx
    render Dashboard::EventRow.new(event: tx)
  end

  # @label Maintenance Record Event
  # @notes Renders a maintenance intervention in the live feed.
  def maintenance_record
    record = mock_maintenance_record
    render Dashboard::EventRow.new(event: record)
  end

  # @label Unknown Event Type
  # @notes Fallback rendering for an unrecognized event.
  def unknown_event
    event = OpenStruct.new(created_at: 3.seconds.ago)
    render Dashboard::EventRow.new(event: event)
  end

  private

  # 🔴 [TEST.12] `.allocate`, а НЕ `OpenStruct` з перевизначеним `is_a?`.
  # `EventRow` диспетчеризує типи через `case/when`, тобто через `Module#===`, який
  # Ruby-рівневого `is_a?` не бачить узагалі — перевірено рантаймом: override віддає
  # `true`, а `case` усе одно йде в `else`. Наслідок був не теоретичний: усі три
  # «типізовані» сценарії рендерили нейтральний `system_pulse`, тобто превʼю брехало
  # рівно тому глядачеві, заради якого існує. `.allocate` обходить ініціалізацію
  # ActiveRecord, зберігаючи класову ідентичність (той самий хід, що в `event_row_spec`).
  def mock_ews_alert
    cluster = OpenStruct.new(name: "Carpathian-9")
    alert = EwsAlert.allocate
    # Реальне значення enum'а, не display-рядок: із «Thermal Anomaly» компонент
    # їхав fail-open гілкою `humanize` — дефект, замаскований дефектом вище.
    alert.define_singleton_method(:alert_type) { "fire_detected" }
    alert.define_singleton_method(:cluster) { cluster }
    alert.define_singleton_method(:created_at) { 12.seconds.ago }
    alert
  end

  def mock_blockchain_tx
    tree = OpenStruct.new(did: "TREE::0xA7F3")
    wallet = OpenStruct.new(tree: tree)
    tx = BlockchainTransaction.allocate
    tx.define_singleton_method(:amount) { BigDecimal("0.0042") }
    tx.define_singleton_method(:wallet) { wallet }
    tx.define_singleton_method(:created_at) { 45.seconds.ago }
    # `.allocate` не ініціалізує `@attributes`, тож КОЖНЕ поле, яке компонент читає,
    # мусить бути застабленим — інакше рендер падає на `fetch_value for nil`.
    # `sourceable` веде у гілку Etherisc-виплати; `nil` лишає звичайний мінт.
    tx.define_singleton_method(:sourceable) { nil }
    tx
  end

  def mock_maintenance_record
    user = OpenStruct.new(first_name: "Olek")
    record = MaintenanceRecord.allocate
    record.define_singleton_method(:action_type) { "repair" }
    record.define_singleton_method(:user) { user }
    record.define_singleton_method(:created_at) { 2.minutes.ago }
    record
  end
end
