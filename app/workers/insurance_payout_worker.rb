class InsurancePayoutWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 10 # Виплати мають найвищий пріоритет ретраїв

  def perform(insurance_id)
    insurance = ParametricInsurance.find(insurance_id)
    return unless insurance.status_triggered?

    # 1. Підготовка транзакції (через наш BlockchainTransaction)
    tx = insurance.create_blockchain_transaction!(
      wallet: insurance.cluster.organization.wallets.first,
      amount: insurance.payout_amount,
      token_type: :carbon_coin, # Або окремий enum :stable_coin
      status: :pending
    )

    # 2. Фізичний переказ коштів через Smart-Contract
    # BlockchainInsuranceService.call(tx.id)
    
    # 3. Оновлення статусу після успіху
    # tx.update!(status: :confirmed)
    insurance.status_paid!
  end
end
