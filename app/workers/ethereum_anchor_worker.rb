# frozen_string_literal: true

class EthereumAnchorWorker
  include Sidekiq::Job

  # Web3 черга — повільні L1 Ethereum транзакції (1 раз на тиждень).
  # Retry: 3 спроби з автоматичним backoff (Ethereum gas estimation може бути нестабільним).
  sidekiq_options queue: "web3", retry: 3

  def perform
    Ethereum::StateAnchorService.new.anchor_to_l1!
  rescue StandardError => e
    Rails.logger.error "🛑 [EthereumAnchor] L1 anchoring failed: #{e.message}"
    raise e
  end
end
