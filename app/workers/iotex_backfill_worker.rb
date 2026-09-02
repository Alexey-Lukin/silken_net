# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# 🔁 IOTEX BACKFILL — пускач для оголошеного recovery [INF.22]
# =============================================================================
# `IotexVerificationWorker` має `retry: 5` і `sidekiq_retries_exhausted`-слід, тобто
# вичерпана джоба лишає в логах ОБИДВІ координати партиційованого рядка. Але сам
# спосіб відновлення був **ручний re-enqueue**, і це робило його недосяжним рівно
# тоді, коли він потрібен: sustained-outage IoTeX-API кладе в Dead Set сотні джоб,
# і жодна людина не переносить їх звідти по одній.
#
# 🔴 Клас — «механізм ⟷ його пускач»: механізм (верифікація) справний, слід
# справний, бракувало ПУСКАЧА. Доти `06_08 §2.2` крок 5 чесно писав «🟡 target:
# `IotexBackfillWorker`-cron НЕ реалізований», тобто канон роками називав ім'я
# класу, якого не існувало.
#
# ⚖️ **НЕ money-блокер, і це вирішує чергу й гучність.** PATH 2-мінт IoTeX не
# гейтить (ARCH.53 §🗄️ — замикання PATH 1 відмовлено founder 2026-07-19), тож
# незверифікований лог не блокує емісію; він лишає діру в ДОКАЗІ походження.
# Отже прилад спостережності: черга `low`, ніколи не тісниться з uplink/money.
#
# ⚠️ Вікно й ліміт — НЕ оптимізація, а визначення предмета: питання звучить
# «які логи лишились неверифікованими за оглядний період», а не «за весь час».
# Безмежний скан партиційованої таблиці не дав би іншої ВІДПОВІДІ дешевше — він
# дав би іншу відповідь (прецедент PERF.1).
class IotexBackfillWorker
  include Sidekiq::Job

  # `low` + `retry: 1`: пропущений прохід не втрачає даних (наступний за годину),
  # наполегливий ретрай купував би лише шум на тлі того самого зовнішнього збою.
  sidekiq_options queue: "low", retry: 1

  # Скільки назад дивимось. Ширше вікно = інша відповідь, не дорожча та сама:
  # лог, незверифікований місяць, є предметом ретеншену, а не recovery.
  LOOKBACK_WINDOW = 48.hours

  # Стеля одного проходу. Кожен ре-армований лог — це джоба у `web3_critical`,
  # тож прохід мусить не змогти залити money-чергу після довгого простою.
  BATCH_LIMIT = 200

  def perform
    # [OPS.37 / ARCH.118] Activation gate with a VOICE: re-arming into an unconfigured leg is
    # not recovery, it is 200 × 6 failing executions an hour forever. The hourly line names the
    # window's unverified count so the state is visible in logs, not merely absent from them.
    unless Iotex::W3bstreamVerificationService.configured?
      pending = TelemetryLog.where(verified_by_iotex: false).where(created_at: LOOKBACK_WINDOW.ago..).count
      Rails.logger.warn "⏸️ [IoTeX Backfill] W3bstream не сконфігуровано — #{pending} логів за " \
                        "#{LOOKBACK_WINDOW.inspect} лишаються неверифікованими; ре-арм відкладено до активації (06_04 §2.2)."
      return
    end

    stale = TelemetryLog
              .where(verified_by_iotex: false)
              .where(created_at: LOOKBACK_WINDOW.ago..)
              .order(:created_at)
              .limit(BATCH_LIMIT)
              .to_a

    # [PERF.1] Три стани, не два: порожня вибірка мовчить, а «розглянуто N, зроблено 0»
    # мусить мати голос — інакше свіпер німий саме тоді, коли підозрілих рядків
    # найбільше. Тут третій стан недосяжний (кожен відібраний рядок ре-армується),
    # тож голос дістає сам факт непорожньої роботи.
    return if stale.empty?

    re_armed = 0
    stale.each do |log|
      # ⚠️ ОБИДВІ координати обов'язкові: `telemetry_logs` партиційований по
      # `created_at`, і без нього `find_telemetry_log_with_pruning` рядок не резолвить.
      IotexVerificationWorker.perform_async(log.id_value, log.created_at.iso8601(6))
      re_armed += 1
    rescue StandardError => e
      # Ізолюємо збій одного рядка — решта вікна доходить до черги.
      Rails.logger.error "🛑 [IoTeX Backfill] Лог ##{log.id_value} не ре-армовано: #{e.message}"
      next
    end

    SilkenNet::Metrics::IOTEX_BACKFILL_REARMED_TOTAL.increment(by: re_armed) if re_armed.positive?

    Rails.logger.warn "🔁 [IoTeX Backfill] Ре-армовано #{re_armed} незверифікованих логів " \
                      "за останні #{LOOKBACK_WINDOW.inspect} (стеля проходу #{BATCH_LIMIT})."
  end
end
