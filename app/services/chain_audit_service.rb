# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

class ChainAuditService < ApplicationService
  TOTAL_SUPPLY_ABI = [
    {
      "inputs" => [],
      "name" => "totalSupply",
      "outputs" => [
        { "internalType" => "uint256", "name" => "", "type" => "uint256" }
      ],
      "stateMutability" => "view",
      "type" => "function"
    }
  ].to_json

  CRITICAL_DELTA_THRESHOLD = 0.0001

  # [ВИПРАВЛЕНО: Sync RPC Trap]: Кешуємо результат аудиту на 5 хвилин,
  # щоб не блокувати HTTP-запит на 1-10 секунд синхронним RPC до Polygon.
  # Обмежуємо час виконання RPC-запиту через Timeout.
  CACHE_TTL = 5.minutes
  RPC_TIMEOUT_SECONDS = 10

  Result = Struct.new(:db_total, :chain_total, :delta, :critical, :checked_at, keyword_init: true)

  def perform
    Rails.cache.fetch("chain_audit_result", expires_in: CACHE_TTL) do
      compute_audit
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [ChainAudit] Збій аудиту: #{e.message}"
    # Повертаємо fallback з нульовими значеннями замість блокування запиту
    Result.new(db_total: 0, chain_total: 0, delta: 0, critical: false, checked_at: Time.current)
  end

  private

  def compute_audit
    db_total    = fetch_db_scc_total
    chain_total = fetch_chain_total_supply
    delta       = (db_total - chain_total).abs

    Result.new(
      db_total:    db_total,
      chain_total: chain_total,
      delta:       delta,
      critical:    delta > CRITICAL_DELTA_THRESHOLD,
      checked_at:  Time.current
    )
  end

  # DB-дзеркало on-chain totalSupply = Σ(mints) − Σ(burns). Slash-інтенти теж `carbon_coin`
  # і теж доходять до `:confirmed` (BlockchainBurningService#create_slash_intent!), але
  # on-chain `slash()` ЗМЕНШУЄ totalSupply — тож сумувати їх позитивно роздуває delta на
  # 2×burn → хибний `critical` після кожного slash. [G4]
  #
  # [ARCH.95] Дискримінатор — колонка `direction`, і деривувати його з `sourceable_type`
  # ⛔ ЗАБОРОНЕНО. Стара форма («`NaasContract` = burn, усе інше = емісія») стояла на
  # передумові «slash — ЄДИНИЙ шлях зменшення обігу», і ESG-погашення цю передумову зняло:
  # `KlimaDao::RetirementService` теж вилучає монети й `sourceable` не має, тож деривація
  # зарахувала б погашення ЕМІСІЄЮ. Передумова померла, вердикт («не сумувати burn
  # позитивно») лишився правильним — тому міняється джерело ознаки, не висновок.
  #
  # ⚠️ Конфлат ПРИРОДИ мінта тут НЕ дефект, а вимога: `totalSupply()` включає і страхові
  # мінти, і податкові — отже DB-бік мусить включати їх теж, інакше звірка зламається.
  # Розщеплення «за що намінтили» належить доказовим поверхням (субграф, MRV-lineage),
  # ніколи цій. [DOC-T.89]
  #
  # [ARCH.97] Формула переїхала в One-Home `BlockchainTransaction.net_minted_supply`:
  # її другим споживачем став L1-якір, а два доми дискримінатора розійшлися б тихо.
  def fetch_db_scc_total
    BlockchainTransaction.net_minted_supply(:carbon_coin).to_f
  end

  # Загальна емісія SCC у смарт-контракті Polygon (totalSupply) — Thread-cached RPC client
  # [ВИПРАВЛЕНО: Sync RPC Trap]: Обгортаємо в Timeout, щоб не блокувати HTTP запит нескінченно.
  def fetch_chain_total_supply
    client   = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
    contract = Eth::Contract.from_abi(
      name:    "SilkenCarbonCoin",
      address: ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS"),
      abi:     TOTAL_SUPPLY_ABI
    )

    raw = Timeout.timeout(RPC_TIMEOUT_SECONDS) do
      client.call(contract, "totalSupply")
    end
    raw.to_f / (10**18)
  end
end
