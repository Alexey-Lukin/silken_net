# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ClusterHealthCheckWorker
  include Sidekiq::Job
  # Використовуємо чергу за замовчуванням. 3 ретраї — достатньо для логічних перевірок.
  sidekiq_options queue: "default", retry: 3

  def perform(date_string = nil)
    # 1. СИНХРОНІЗАЦІЯ ДАТИ (The Audit Anchor)
    # [ARCH.100] Доба аудиту = доба, якою інсайти ЗАПИСАНІ (`AiInsight.reporting_date`),
    # а не «вчора» в поясі кожного кластера. Доти тут стояв per-tenant якір під обіцянкою
    # «система масштабується від Бразилії до Індонезії» — і вимір показав протилежне:
    # Індонезія (UTC+7) збігалась, Бразилія (UTC−3) промахувалась ЩОНОЧІ, бо о 02:00 UTC
    # її локальне «вчора» на добу старше за те, яким агрегатор штампував інсайти.
    target_date = date_string.present? ? Date.parse(date_string) : AiInsight.reporting_date

    Rails.logger.info "🕵️ [D-MRV Audit] Початок перевірки активних NaaS контрактів за #{target_date}"

    # 1.5. ОНОВЛЕННЯ КЕШУ ЗДОРОВ'Я (Cached Health Index)
    # Перераховуємо health_index для всіх кластерів і зберігаємо в БД — ОДНІЄЮ добою,
    # тією ж, якою нижче судиться контракт.
    Cluster.find_each { |c| c.recalculate_health_index!(target_date) }

    summary = { checked: 0, flagged: 0, errors: 0 }

    # 2. ПЕРЕВІРКА ПОРУШЕНЬ (The Slashing Protocol)
    # find_each захищає пам'ять сервера при великій кількості контрактів
    NaasContract.status_active.find_each do |contract|
      summary[:checked] += 1

      begin
        # [SLASH-1] Гілкуємо за VERDICT сервісу, а не за status_breached? — breach тепер
        # асинхронний (ставиться лише на реальному positive-A слешингу в чокпоінті).
        # Celo-винагорода йде ЛИШЕ здоровому кластеру: деградований/blackout (на адъюдикації
        # cause-gate) винагороди не отримує — закриває reward-leak деградованому кластеру.
        verdict = contract.check_cluster_health!(target_date)

        case verdict
        # `:insufficient_sample` [SLASH-1] іде сюди свідомо: кластер ФЛАГОВАНО (Field Audit
        # створено), просто адъюдикація людська, а не автоматична. Якби він падав у
        # default-гілку, малий кластер із критичним деревом зник би зі зведення — і виглядав
        # би як «нічого не сталось». Celo-винагороди він при цьому не дістає (не `:healthy`).
        when :degraded, :blackout, :insufficient_sample
          summary[:flagged] += 1
          Rails.logger.warn "🚨 [D-MRV] Контракт ##{contract.id} (Кластер: #{contract.cluster.name}) ФЛАГОВАНО (#{verdict}) за станом на #{target_date} — на адъюдикацію слешингу."
        when :healthy
          # [Celo ReFi]: Позитивний зворотний зв'язок — здоровому кластеру cUSD через Celo.
          CeloRewardWorker.perform_async(contract.cluster_id, target_date.to_s)
        end
        # :skipped (неактивний / без активних дерев) — без дії

      rescue StandardError => e
        summary[:errors] += 1
        Rails.logger.error "🛑 [D-MRV Error] Помилка аудиту контракту ##{contract.id}: #{e.message}"
        # Продовжуємо аудит наступних лісів
        next
      end
    end

    Rails.logger.info "✅ [D-MRV Audit] Завершено. Оброблено: #{summary[:checked]}, Флаговано: #{summary[:flagged]}, Помилок: #{summary[:errors]}"

    # 3. [INS.1] Страховий оракул (Trigger-1, arm-кандидат) — per-cluster fan-out.
    enqueue_insurance_oracle(target_date)
  end

  private

  # [INS.1 / ARCH.59] Fan-out страхового оракула по кластерах з активними страховками.
  #
  # 🔴 **Чому дім саме ТУТ, а не в `InsightBatchCallbacks`, звідки він переїхав.** Той
  # колбек вішається на `Sidekiq::Batch#on(:success)`, а `sidekiq-pro` у `Gemfile`
  # немає — активний шим лише складає колбеки в масив, тож у проді вони не
  # виконуються ЖОДНОГО разу (DOC-R.10). Fan-out був ЄДИНИМ enqueue-сайтом
  # `InsuranceOracleWorker` у всьому дереві, тобто фліп kill-switch нікого б не
  # озброїв — і це саме той момент, коли всі вважатимуть, що озброїв.
  #
  # Цей воркер має ВЛАСНИЙ cron (`0 2 * * *`, `config/sidekiq.yml` — там він і
  # названий «defensive fallback»), тож перенесення сюди не додає ані розкладу, ані
  # воркера: ланка успадковує вже ратифікованого пускача. Доба береться та сама
  # (`target_date` вище, якір `AiInsight.reporting_date` [ARCH.100]), тому подвійний
  # enqueue при живому Pro ідемпотентний рівно з тієї ж підстави, що й health-recalc.
  def enqueue_insurance_oracle(target_date)
    return unless ActiveModel::Type::Boolean.new.cast(
      SystemParameter.current(:parametric_insurance_oracle_enabled, default: false)
    )

    Cluster.joins(:parametric_insurances).merge(ParametricInsurance.status_active)
           .distinct.find_each do |cluster|
      InsuranceOracleWorker.perform_async(cluster.id, target_date.to_s)
    end
  end
end
