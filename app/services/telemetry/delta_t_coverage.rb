# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Telemetry
  # [SEC.42 (б)] Правдоподібність Σ delta_t: сирі delta_t кадрів дерева, що приїхали
  # одним конвертом, проти часу від його попереднього прийому. СПОСТЕРЕЖЕННЯ, не
  # вердикт (⚖️ делеговано, 03_05 §2.4): чесна втрата кадру й морозне відкладення TX
  # тягнуть частку вниз так само, як фальсифікатор із KEYL, що вкорочує delta_t, тож ні
  # алерту, ні грошової дії; гістограма збирає польовий розподіл для присуду, що ввімкне
  # строгість. Безключового шляху тут уже немає: крок годинника за маяком зсуває й базу
  # delta_t (Silken_Beacon_Apply, wall_time.h).
  #
  # ⚠️ Стеля: «попередній прийом» — `Tree#last_seen_at`, тобто час ОБРОБКИ, і кадр чекає
  # флашу Королеви в її кеші, тож на каденсі, довшому за флаш, один відлік шумить на
  # фазі флашу в рази: тонкої підробки частка не бачить, у рази коротший delta_t — бачить.
  module DeltaTCoverage
    # Сатурований дріт (≥ 18.2 год) недолічує проміжок.
    WIRE_SATURATED_S = 0xFFFF
    # Коротший проміжок тоне в затримці черги `uplink`.
    MIN_ELAPSED_S = 60

    module_function

    # Частка або nil, коли судити нема чим: перший прийом, надто короткий проміжок, або
    # хоч один кадр без виміру (сентинел чи сатурація) — його проміжок невідомий, і
    # частка без нього брехала б униз.
    def ratio(delta_ts, since:, now:)
      return nil if since.nil?

      elapsed = now - since
      return nil if elapsed < MIN_ELAPSED_S

      measured = delta_ts.compact
      return nil if measured.empty?
      return nil if measured.any? { |dt| dt == SilkenNet::Attractor::DELTA_T_UNKNOWN_S || dt >= WIRE_SATURATED_S }

      measured.sum / elapsed.to_f
    end
  end
end
