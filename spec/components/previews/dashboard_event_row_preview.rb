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

  def mock_ews_alert
    cluster = OpenStruct.new(name: "Carpathian-9")
    OpenStruct.new(
      alert_type: "Thermal Anomaly",
      cluster: cluster,
      created_at: 12.seconds.ago
    ).tap { |o| o.define_singleton_method(:is_a?) { |klass| klass == EwsAlert || super(klass) } }
  end

  def mock_blockchain_tx
    tree = OpenStruct.new(did: "TREE::0xA7F3")
    wallet = OpenStruct.new(tree: tree)
    OpenStruct.new(
      amount: "0.0042",
      wallet: wallet,
      created_at: 45.seconds.ago
    ).tap { |o| o.define_singleton_method(:is_a?) { |klass| klass == BlockchainTransaction || super(klass) } }
  end

  def mock_maintenance_record
    user = OpenStruct.new(first_name: "Olek")
    OpenStruct.new(
      action_type: "repair",
      user: user,
      created_at: 2.minutes.ago
    ).tap { |o| o.define_singleton_method(:is_a?) { |klass| klass == MaintenanceRecord || super(klass) } }
  end
end
