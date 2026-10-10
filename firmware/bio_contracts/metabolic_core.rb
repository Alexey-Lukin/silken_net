# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =========================================================================
# МЕТАБОЛІЧНА ВИНАГОРОДА — ОДИН дім формули для ОБОХ контрактів пристрою
# =========================================================================
# ⚖️ [FW.66 (Б) · S4] mrbc компілює цей файл ПЕРШИМ і в контракт ECB-ери
# (bio_contract.rb — `lorenz_bytecode.h`), і в контракт CCM-ери (ccm_contract.rb —
# `ccm_bytecode.h`), тож формула балів на пристрої одна, а не дві копії, що
# розійшлись би мовчки. Дзеркало на сервері — `SilkenNet::Attractor.expected_homeostasis_gp`
# (app/services/silken_net/attractor.rb); у CCM-ері заява пристрою — тест відповідності
# серверному перерахунку («утримання» GP, 03_04 §7.3), тож розбіжність коштує балів.
# SHA цих констант пінить `metabolic_gp_core` (lib/canonical_block_pins.yml).
# =========================================================================
module SilkenNet
  module Metabolic
    # [E.63] Метаболічна винагорода: швидкість перезаряду EBFC (delta_t) →
    # growth_points, МОНОТОННО і у польовому масштабі. У гомеостазі магнітуда балів =
    # метаболічна жвавість m(delta_t), а не |OPTIMAL−Z| (хаотичний шум).
    # Калібрувальні пороги — placeholder, чекають bench recharge-кривої
    # (firmware/scripts/bench/RUNBOOK.md §3.3 / 00_07 E.63); фінал —
    # per-deployment/species, не хардкод.
    DELTA_T_FAST_S = 600     # ≤ цього → пік жвавості (m = 1.0)
    DELTA_T_SLOW_S = 7200    # ≥ цього → мінімум (m = 0.0)
    GP_HOMEO_MIN   = 5       # 5-бітний wire-діапазон гомеостазу (FW.29-PACK)
    GP_HOMEO_MAX   = 31

    # [ARCH.102] «Метаболізм не виміряно» — окремий СТАН, не число. Нуль секунд
    # між пробудженнями не є інтервалом перезаряду в жодному прочитанні (ні як
    # вимір, ні як фізика), тож він вільний під сентинел і не забирає жодного
    # досяжного значення. Guard-и `wall_time.h` (cold-start · зсув годинника
    # назад · стрибок епохи · HAL-збій) і непрогріта EMA віддають САМЕ його.
    #
    # 🔴 Чому це несуче: доти ті ж гілки віддавали `BASELINE_DELTA_T_S = 60`,
    # поданий як «нейтральний», — а жвавість m(60) = 1.08 → clamp 1.0 →
    # `growth_points = GP_HOMEO_MAX`. Тобто відмова виміряти мінтила МАКСИМУМ,
    # і на кремнії це не крайній випадок: `Wall_Seconds_Now()` повертає 0 до
    # LSE/RTC bring-up (FW.49), отже cold-start-гілка спрацьовує щоцикла.
    DELTA_T_UNKNOWN_S = 0

    # Бали ВИМІРЯНОГО гомеостазу: GP_HOMEO_MIN..GP_HOMEO_MAX за монотонною жвавістю
    # m ∈ [0.0, 1.0] (швидший перезаряд → вище). «Не виміряно» — нуль (ARCH.102):
    # виміряний гомеостаз починається з GP_HOMEO_MIN, тож нуль у полі балів при
    # status = 0 ні з чим не плутається. ⚠️ Один метод, а не два (жвавість + бали):
    # кожен метод — символи й irep у байткоді, а CCM-контракт має вкластися в стелю
    # OTA Солдата (FW.67) — розмір друкує tools/firmware/gen_bytecode.sh, стереже пін диспетчера.
    def self.homeostasis_gp(delta_t_s)
      return 0 if delta_t_s == DELTA_T_UNKNOWN_S

      m = (DELTA_T_SLOW_S - delta_t_s).to_f / (DELTA_T_SLOW_S - DELTA_T_FAST_S)
      m = 0.0 if m < 0.0
      m = 1.0 if m > 1.0
      gp = (GP_HOMEO_MIN + (m * (GP_HOMEO_MAX - GP_HOMEO_MIN))).round
      gp = GP_HOMEO_MIN if gp < GP_HOMEO_MIN
      gp = GP_HOMEO_MAX if gp > GP_HOMEO_MAX
      gp
    end
  end
end
