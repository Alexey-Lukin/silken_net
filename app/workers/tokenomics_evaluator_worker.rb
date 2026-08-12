# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class TokenomicsEvaluatorWorker
  include Sidekiq::Job

  # [UNIQUE_FOR]: Sidekiq Enterprise Unique Jobs — запобігає перетину
  # щогодинних циклів. Якщо попередній цикл ще виконується,
  # новий буде відхилено замість створення конкурентного батчу.
  sidekiq_options queue: "default", retry: 3, unique_for: 60.minutes

  # Дефолт конверсії: 1 SCC (Silken Carbon Coin) = 10,000 балів гомеостазу.
  # Живе значення DAO-керується → .emission_threshold (GOV.1 read-path).
  EMISSION_THRESHOLD = 10_000

  # [GOV.1] One-Home читання порогу емісії: SystemParameter ← ProtocolParameters.sol
  # (ParameterSyncWorker, bounds 1_000..100_000). Не-позитивне значення (мис-скейл
  # повз bounds) → дефолт: на цей поріг ділить EvaluateTreeBatchWorker.
  def self.emission_threshold
    value = SystemParameter.current(:emission_threshold, default: EMISSION_THRESHOLD).to_i
    value.positive? ? value : EMISSION_THRESHOLD
  end

  # [МАСШТАБ]: Кількість гаманців в одному EvaluateTreeBatchWorker.
  # При 10M дерев = 10,000 чанків, при 1B = 1,000,000 чанків.
  # Оптимальний розмір: достатньо великий для ефективності БД,
  # достатньо малий для паралелізму Sidekiq.
  BATCH_CHUNK_SIZE = 1_000

  # [SIDEKIQ PRO BATCH]: Замість синхронної обробки мільйонів гаманців
  # у одному процесі, створюємо оркестрований батч.
  # Sidekiq Pro відстежує прогрес кожного EvaluateTreeBatchWorker
  # і гарантує виклик TokenomicsBatchCallbacks#on_success тільки
  # після завершення ВСІХ чанків.
  def perform
    cycle_id = SecureRandom.uuid
    Rails.logger.info "⚖️ [NAM-ŠID] Початок циклу емісії #{cycle_id}..."

    batch = Sidekiq::Batch.new
    batch.description = "Tokenomics Cycle #{cycle_id}"
    batch.on(:success, TokenomicsBatchCallbacks, "cycle_id" => cycle_id)

    chunks_enqueued = 0

    batch.jobs do
      self.class.eligible_wallets.in_batches(of: BATCH_CHUNK_SIZE) do |relation|
        EvaluateTreeBatchWorker.perform_async(relation.pluck(:id), cycle_id)
        chunks_enqueued += 1
      end
    end

    Rails.logger.info "📦 [NAM-ŠID] Батч #{batch.bid}: #{chunks_enqueued} чанків " \
                      "по #{BATCH_CHUNK_SIZE} гаманців. Очікуємо завершення..."
  end

  # Scope для eligible гаманців: активні дерева з НЕсконвертованим залишком >= порогу.
  # [ARCH.94] Публічний і КЛАСОВИЙ свідомо: той самий предикат семплить
  # `TokenomicsBatchCallbacks` як детектор застрягання — після здорового циклу
  # множина порожня ЗА ПОБУДОВОЮ (мінт піднімає `locked_balance`, тож
  # `available_balance` падає нижче порога). Дублювати умову не можна: два доми
  # eligibility розійшлися б тихо, і детектор почав би міряти не те, що тракт.
  def self.eligible_wallets
    Wallet.joins(:tree)
          .where(trees: { status: :active })
          # [ARCH.94] NET, не gross: `balance` тримає й уже сконвертоване
          # (locked назавжди, 04_01 §6 E.66), тож фільтр по ньому вічно
          # переобирає гаманці, які нічого змінтувати вже не можуть.
          .where("balance - locked_balance >= ?", emission_threshold)
  end
end
