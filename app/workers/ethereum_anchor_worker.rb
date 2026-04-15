# frozen_string_literal: true

class EthereumAnchorWorker
  include ApplicationWeb3Worker

  # Web3 Low черга — повільні L1 Ethereum транзакції (1 раз на тиждень).
  # Retry: 5 спроб з автоматичним backoff (вирівняно з іншими Web3 воркерами: IoTeX, peaq, Filecoin).
  # [UNIQUE_FOR]: Запобігає перетину тижневих anchoring циклів.
  # Якщо попередній анкорінг ще виконується — новий не запуститься.
  sidekiq_options queue: "web3_low", retry: 5, unique_for: 7.days

  def perform
    with_web3_error_handling("Ethereum", "L1 State Anchor") do
      Ethereum::StateAnchorService.new.anchor_to_l1!
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [EthereumAnchor] L1 anchoring failed: #{e.message}"
    raise
  end
end
