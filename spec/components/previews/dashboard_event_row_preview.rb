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
    render Dashboard::EventRow.new(event: mock_blockchain_tx)
  end

  # @label Blockchain Burn Event (slashing)
  # @notes Direction is the `direction` COLUMN [ARCH.95], never the sign of
  #   `amount` — a slash intent is written POSITIVE. Until 2026-08-13 this state
  #   rendered as «Minted», i.e. the feed reported an emission on a burn.
  def blockchain_burn
    render Dashboard::EventRow.new(event: mock_blockchain_tx(amount: "3.0", direction: "burn"))
  end

  # @label Cluster-sourced Celo Reward
  # @notes [ARCH.98] Cluster-sourced money carries no wallet by construction, so
  #   both the ticker and the source come from the row itself — not from «SCC»
  #   and «System» baked into the sentence.
  def cluster_sourced_reward
    render Dashboard::EventRow.new(
      event: mock_blockchain_tx(token_type: :cusd, amount: "5.0", cluster: Cluster.new(name: "Carpathian-9"))
    )
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

  # Грошовий рядок будується РЕАЛЬНИМ `new`, а не `.allocate`: тікер і НАПРЯМОК
  # виводяться з колонок (`token_type`, `direction`), тож запис без атрибутів
  # їх віддати не може взагалі. Класову ідентичність для `case/when` незбережений
  # `new` тримає так само — саме вона й була єдиною причиною брати `.allocate`.
  def mock_blockchain_tx(token_type: :carbon_coin, amount: "0.0042", cluster: nil, direction: "mint")
    BlockchainTransaction.new(
      token_type: token_type, amount: amount, direction: direction,
      wallet: cluster ? nil : Wallet.new(tree: Tree.new(did: "SNET-0A7F3B21")),
      cluster: cluster, created_at: 45.seconds.ago
    )
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
