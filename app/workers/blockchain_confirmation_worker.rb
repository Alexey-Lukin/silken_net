class BlockchainConfirmationWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 10

  def perform(tx_hash)
    client = Eth::Client.create(ENV.fetch("ALCHEMY_POLYGON_RPC_URL"))
    receipt = client.eth_get_transaction_receipt(tx_hash)

    if receipt && receipt["result"]
      status = receipt["result"]["status"]
      txs = BlockchainTransaction.where(tx_hash: tx_hash)

      if status == "0x1" # Успіх
        txs.each(&:confirmed!)
        Rails.logger.info "💎 [Web3] Блокчейн підтвердив емісію: #{tx_hash}"
      else # Провал транзакції на рівні EVM
        txs.each { |tx| tx.fail!("EVM Revert: Транзакція відхилена мережею.") }
      end
    else
      # Якщо квитанції ще немає — повторюємо через хвилину
      raise "Waiting for confirmation: #{tx_hash}"
    end
  end
end
