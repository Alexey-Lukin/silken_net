# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Insurance
  # =========================================================================
  # 🛡️ INSURANCE RESERVE GATE (INS.2 — Internal-mode payout stop-loss)
  # =========================================================================
  # Internal-mode параметрична виплата (`InsurancePayoutWorker` → `BlockchainMintingService`)
  # МІНТИТЬ новий SCC/SFC як payout — це інфляційна емісія, НЕ забезпечена DAO_TREASURY-пулом
  # (той пул `insurance_pool_requires_funding?` читає лише для 2%-Dynamic-Tax-рішення; payout
  # його ніколи не дебетує). 🔴 Per-claim cap — це САМ `payout_amount`, статична колонка
  # полісу, і НЕ формула: `damage_ratio × insured_value` тут не рахується ніде, а
  # `insured_value` не існує як колонка, метод чи змінна (переміряно 2026-08-26; доти цей
  # коментар називав її наявним гардом, і те саме дзеркалилось у 05_05 §4). Отже виплата
  # НЕ масштабується шкодою — all-or-nothing на тригері, що є виконанням параметричної
  # моделі, а не наближенням. АГРЕГАТНОГО cap немає — регіональна катастрофа мінтить
  # повну суму по всіх спрацьованих полісах без systemic stop-loss окрім `MAX_SUPPLY`.
  #
  # Цей gate додає два ковзно-віконні пороги ПЕРЕД mint. Обидва **inert за замовчуванням**
  # (SystemParameter 0 → вимкнено): реальні числа = 👤 economic-політика (дзеркало INS.1
  # kill-switch — механізм у коді, активація/калібрування = founder/DAO).
  #
  # Оцінюється ЛИШЕ Internal-mint (`etherisc_policy_id IS NULL`) — Etherisc-mode платить
  # зовнішнім USDC з пулу Etherisc (не інфляція, не наша емісія), тож не входить у stop-loss.
  #
  # Fail-CLOSED: якщо reserve неможливо оцінити (RPC-збій), HOLD (не мінтимо незабезпечене) —
  # виплата не втрачається, recovery-шлях (`unsettled_within` включає `:manual_review`)
  # підхопить після відновлення. Дім політики — 00_04 §7; money-механіка — 04_02.
  # =========================================================================
  class ReserveGate < ApplicationService
    WEI_MULTIPLIER = 10**18

    # Correlated-event вікно (регіональна катастрофа за добу) + reserve-adequacy вікно
    # (місячний claim-обсяг vs пул). created_at-bound = partition-prune.
    AGGREGATE_WINDOW = 24.hours
    RESERVE_WINDOW = 30.days

    # Статуси, що рахуються "виданими/у процесі" (усе крім failed) — конкурентні виплати
    # НЕ мають прослизнути повз cap через незавершений стан.
    OUTSTANDING_STATUSES = %i[pending processing sent confirmed manual_review].freeze

    # `params` — скаляри поруч із готовим `detail`. `detail` лишається для ЛОГУ
    # оператора (англійська там доречна), а `params` іде в locale-рендер алерта:
    # без них у повідомлення сідала готова фраза з ЧУЖОГО сервісу, і локалізована
    # рамка отримувала англійську середину назавжди.
    Result = Struct.new(:ok, :reason, :detail, :params, keyword_init: true) do
      def ok? = ok
      def params = self[:params] || {}
    end

    def initialize(insurance, current_tx_id: nil)
      @insurance = insurance
      # Виплата цього claim'у вже створена як :pending (sourceable=insurance) ДО виклику gate,
      # тож internal_mint_sum її вже рахує — виключаємо, щоб `+ payout` не подвоїв її.
      @current_tx_id = current_tx_id
    end

    def perform
      payout = @insurance.payout_amount.to_f
      token_type = @insurance.token_type

      # (1) Aggregate correlated-event stop-loss.
      cap = SystemParameter.current(:insurance_aggregate_payout_cap_scc, default: 0).to_f
      if cap.positive?
        window_sum = internal_mint_sum(token_type, AGGREGATE_WINDOW) + payout
        if window_sum > cap
          return breach(:aggregate_cap,
                        "24h Internal insurance-mint #{window_sum.round(2)} > cap #{cap.round(2)} #{token_type}",
                        { window_sum: window_sum.round(2), cap: cap.round(2), token_type: token_type })
        end
      end

      # (2) Reserve-adequacy — капимо сумарну інфляційну емісію пропорційно реальному пулу.
      ratio = SystemParameter.current(:insurance_reserve_adequacy_ratio, default: 0).to_f
      if ratio.positive?
        reserve = dao_treasury_balance_scc
        outstanding = internal_mint_sum(token_type, RESERVE_WINDOW) + payout
        if outstanding > reserve * ratio
          return breach(:reserve_inadequate,
                        "30d Internal insurance-mint #{outstanding.round(2)} > reserve #{reserve.round(2)} × #{ratio}",
                        { outstanding: outstanding.round(2), reserve: reserve.round(2), ratio: ratio })
        end
      end

      Result.new(ok: true, reason: :ok)
    rescue StandardError => e
      Rails.logger.error "🛑 [INS.2] ReserveGate eval failed (fail-closed → hold): #{e.message}"
      breach(:eval_error, e.message.truncate(200), { error: e.message.truncate(200) })
    end

    private

    def breach(reason, detail, params = {})
      Result.new(ok: false, reason: reason, detail: detail, params: params)
    end

    # Σ amount Internal-mint виплат (sourceable=ParametricInsurance, etherisc_policy_id NULL)
    # того ж token_type за вікно, БЕЗ поточної виплати (`+ payout` додається окремо). Etherisc
    # (зовнішній USDC) виключено — не наша емісія.
    def internal_mint_sum(token_type, window)
      internal_ids = ParametricInsurance.where(etherisc_policy_id: nil).select(:id)
      scope = BlockchainTransaction
              .where(sourceable_type: "ParametricInsurance", sourceable_id: internal_ids)
              .where(token_type: token_type, status: OUTSTANDING_STATUSES)
              .where("created_at >= ?", window.ago)
      scope = scope.where.not(id: @current_tx_id) if @current_tx_id
      scope.sum(:amount).to_f
    end

    # DAO Treasury on-chain SCC-баланс (той самий пул, що Dynamic-Tax наповнює). [One-Home] через
    # Web3::Erc20Reader зі спільним cache-ключем BlockchainMintingService → один RPC на 15-хв вікно
    # на обидві фічі. Помилку RPC піднімаємо (fail-closed у perform-rescue).
    def dao_treasury_balance_scc
      Web3::Erc20Reader.balance_of_wei(
        contract_env_key: "CARBON_COIN_CONTRACT_ADDRESS",
        holder: ENV.fetch("DAO_TREASURY_ADDRESS"),
        cache_key: BlockchainMintingService::TREASURY_BALANCE_CACHE_KEY,
        ttl: BlockchainMintingService::TREASURY_CACHE_TTL
      ).to_f / WEI_MULTIPLIER
    end
  end
end
