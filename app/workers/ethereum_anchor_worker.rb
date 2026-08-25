# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class EthereumAnchorWorker
  include ApplicationWeb3Worker

  # Web3 Low черга — повільні L1 Ethereum транзакції (1 раз на тиждень).
  # Retry: 5 спроб з автоматичним backoff (вирівняно з іншими Web3 воркерами: IoTeX, peaq, Filecoin).
  # [UNIQUE_FOR]: Запобігає перетину тижневих anchoring циклів.
  # Якщо попередній анкорінг ще виконується — новий не запуститься.
  sidekiq_options queue: "web3_low", retry: 5, unique_for: 7.days

  # [S6.6] Maximum gap between anchors before alerting (8 days = 1 week + 1 day buffer).
  MISSED_ANCHOR_THRESHOLD = 8.days

  def perform
    detect_missed_anchor_weeks!

    with_web3_error_handling("Ethereum", "L1 State Anchor") do
      Ethereum::StateAnchorService.new.anchor_to_l1!
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [EthereumAnchor] L1 anchoring failed: #{e.message}"
    raise
  end

  private

  # [S6.6] Detects gaps in the weekly anchoring schedule.
  # [ARCH.66] Counts only :confirmed (not :sent) as "success": with a live confirmation
  # poller a :sent anchor is transient (resolves in hours), so a stuck :sent must NOT
  # reset the gap — else a lost receipt would let a fresh weekly :sent mask a genuinely
  # unconfirmed run forever. If the last CONFIRMED anchor is older than the threshold,
  # logs a warning and increments the Prometheus metric. Grafana alerts on the rate > 0.
  def detect_missed_anchor_weeks!
    last_anchor = EthereumAnchor
      .status_confirmed
      .order(created_at: :desc)
      .first

    # First ever anchor — no gap to detect
    return unless last_anchor

    gap = Time.current - last_anchor.created_at
    return unless gap > MISSED_ANCHOR_THRESHOLD

    # Calculate missed weeks: gap/1.week gives total weeks elapsed, subtract 1 for the
    # current (expected) week. Minimum 1 because we already know gap > MISSED_ANCHOR_THRESHOLD.
    missed_weeks = [ (gap / 1.week).floor - 1, 1 ].max

    Rails.logger.warn(
      "⚠️ [EthereumAnchor] Missed anchor week detected! Last successful anchor: " \
      "#{last_anchor.created_at.iso8601} (#{(gap / 1.day).round(1)} days ago). " \
      "Estimated missed weeks: #{missed_weeks}. State roots for missed weeks " \
      "cannot be retroactively computed — current state will be anchored as catch-up."
    )

    # 🔴 [INF.26] `by: missed_weeks`, не голий інкремент: докстрінг обіцяє «Total missed
    # **weeks**», а величина обчислена рядком вище й до лічильника не доїжджала — тож
    # пʼятитижнева прогалина рахувалась як ОДНА. І недолік незворотний: наступного тижня
    # `last_anchor` уже свіжий, детекція не спрацює, і ті тижні не долічить ніхто.
    # ⚠️ Вердикт алерту від цього НЕ змінюється (`sn-alert-anchor-stalled` гейтить на
    # `> 0`) — змінюється придатність числа до питання «наскільки довго», яке саме й
    # ставить людина, побачивши алерт. Саме тому фікс дешевий і безпечний.
    SilkenNet::Metrics::ANCHOR_MISSED_WEEKS_TOTAL.increment(by: missed_weeks)
  rescue StandardError => e
    # Detection failure should not block anchoring
    Rails.logger.warn "⚠️ [EthereumAnchor] Missed anchor detection failed: #{e.message}"
  end
end
