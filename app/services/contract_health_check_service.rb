# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🏥 CONTRACT HEALTH CHECK SERVICE (D-MRV Арбітраж)
# = ===================================================================
# Перевіряє здоров'я лісового кластера за NaasContract і активує
# Slashing Protocol у разі порушення порогу 20% критичних аномалій.
#
# Вилучено з NaasContract#check_cluster_health! для дотримання
# принципу "тонка модель" (Thin Model) та Single Responsibility.
#
# Використання:
#   ContractHealthCheckService.call(naas_contract)
#   ContractHealthCheckService.call(naas_contract, target_date)
class ContractHealthCheckService < ApplicationService
  def initialize(naas_contract, target_date = nil)
    @contract = naas_contract
    @cluster = naas_contract.cluster
    # [ARCH.100] Дефолт — доба ЗАПИСУ інсайтів, не локальне вчора кластера: `DailyHealthRouter`
    # шукає точною рівністю, тож розходження якорів давало `:blackout` на здоровому лісі.
    @target_date = target_date || AiInsight.reporting_date
  end

  # Повертає verdict-символ для крона (`ClusterHealthCheckWorker` гілкує Celo-винагороду
  # за verdict, а НЕ за `status_breached?` — breach тепер асинхронний, лише на реальному
  # слешингу у `BlockchainBurningService`): `:skipped` · `:blackout` · `:degraded`
  # (>20% → чокпоінт слешингу, cause-gate вирішить slash/freeze) · `:healthy`.
  def perform
    return :skipped unless @contract.status_active?

    # [SLASH-1] Спільне денне читання (DRY з insurance-шляхом B) + blackout-рішення в ОДНОМУ домі.
    router = DailyHealthRouter.new(@cluster, @target_date)
    return :skipped if router.skipped?

    # [SLASH-1 / 05_05 §6] Cluster-wide data blackout (нуль інсайтів на ВЕСЬ кластер) — сигнатура
    # gateway-fault / force-majeure (вкрадений/знищений шлюз, Starlink-блекаут, шторм), НЕ per-tree
    # недбалість. НІКОЛИ авто-burn на відсутність даних → Field Audit / peer-review (Категорія C);
    # людина класифікує A (недбалість → slash) vs B (форс-мажор → insurance).
    return flag_data_blackout! if router.blackout?

    # Математична межа порушення — частка активної біомаси (default 20%).
    # [ARCH.46] Спільний slash-поріг (= damage-сайзинг у BlockchainBurningService) — одне
    # читання AiInsight.slash_stress_threshold, щоб тригер і розмір не розходились.
    # [GOV.1] Обидва пороги DAO-live (SystemParameter ← ProtocolParameters.sol); Rational
    # із to_s — точна десяткова частка без IEEE-похибки на межі (спадок Rational(1,5)).
    # [SLASH-1] Поріг читається РІВНО РАЗ і далі подорожує з вироком: те саме число
    # сайзить damage у `BlockchainBurningService`. Доти кожна половина читала DAO-live
    # у свій момент, тож голос між диспатчем і виконанням розводив тригер і розмір.
    stress_threshold = AiInsight.slash_stress_threshold
    critical_insights_count = router.critical_count(stress_threshold)

    slash_fraction = Rational(SystemParameter.current(:slash_threshold, default: 0.2).to_s)

    # [SLASH-1] Поріг ВИРОДЖУЄТЬСЯ на малих кластерах, і межа тут не смакова, а
    # арифметична: при `N < 1/slash_fraction` добуток `N * f` менший за одиницю, тобто
    # БУДЬ-ЯКЕ одне критичне дерево перетинає поріг, і «понад 20%» перестає бути
    # статистичним твердженням. Для дефолтних 0.2 це N ∈ {1..4}; від N=5 потрібні вже
    # щонайменше два дерева, тож одиничний шум не спрацьовує. Межа деривується з самого
    # порога, а не хардкодиться — DAO-зміна `slash_threshold` рухає її автоматично.
    #
    # Наслідок для B2C (⚖️ 2026-07-30: одиноке дерево = власний кластер із одного): там
    # N=1 завжди, тож приватний власник ніколи не дістає АВТОМАТИЧНОГО спалення за одну
    # аномальну добу на одному сенсорі — але й без нагляду не лишається.
    #
    # Дорога та сама, що для blackout: Field Audit, ніколи авто-burn — дзеркалить
    # доктрину «незворотний slash лише за прямого доказу» (§3.2). Гілка живе ПІСЛЯ
    # підрахунку критичних: здоровий малий кластер не має щодоби плодити алерт.
    #
    # ⚠️ МЕЖА ЗАСТОСОВНОСТІ, щоб її не «полагодили» помилково: це стосується ЛИШЕ
    # статистичного шляху (частка стресованих дерев). Шлях `Tree#trigger_slashing_protocol`
    # (deceased/removed) розміру кластера НЕ питає — і не повинен: смерть дерева це прямий
    # факт, а не висновок із вибірки, тож вироджуватись там нічому. Причину там однаково
    # зважує чокпоінт `BlockchainBurningService` (cause-gate slash-vs-freeze).
    # 🔴 [SLASH-1, ⚖️ 2026-08-26] І ГАРД, і ТРИГЕР міряють тепер тих, хто СВІДЧИВ,
    # а не всіх `active`. Переносити треба ОБИДВА разом: лишити гард на старій
    # шкалі означало б відтворити [ARCH.95] — кластер зі 100 дерев і 99 мовчазними
    # пройшов би поріг виродження (100 ≥ 5) і рахував би частку по ОДНОМУ дереву.
    # ⊕ Побічно це й ліпший захист від масової тиші: зникнення свідків саме́ по
    # собі опускає вибірку під поріг → `:insufficient_sample` → Field Audit, тобто
    # людина, а не автоматичний вирок.
    if critical_insights_count.positive? && router.witnessing_trees < (1 / slash_fraction)
      return flag_insufficient_sample!(critical_insights_count, router.witnessing_trees)
    end

    if critical_insights_count > router.witnessing_trees * slash_fraction
      flag_degradation!(stress_threshold)
    else
      :healthy
    end
  end

  private

  # [SLASH-1] >20% критичних аномалій → на чокпоінт слешингу. БЕЗ pre-breach: breach
  # тепер ставить ЛИШЕ BlockchainBurningService на РЕАЛЬНОМУ (positive-A) слешингу, а
  # cause-gate чокпоінта вирішує slash-vs-freeze (§3.2). Це й полагодило латентний баг:
  # раніше pre-breach коротко-замикав воркер (`return if status_breached?`) → daily-шлях
  # ніколи реально не палив. Тепер не пре-маркуємо → daily нарешті доходить до burn/freeze.
  def flag_degradation!(stress_threshold)
    Rails.logger.warn "🚨 [D-MRV] NaasContract ##{@contract.id}: >20% критичних аномалій — на чокпоінт слешингу (cause-gate вирішить slash/freeze)."
    # [ARCH.46] Прокидаємо @target_date у burn (5-й позиц. арг), щоб damage-ratio рахувався за ТУ Ж
    # добу, що тут — інакше burn перевираховує добу у свій момент → інша дата → 100%.
    # [SLASH-1] Разом із датою їде ПОРІГ (6-й) — друга координата того самого інваріанта
    # «тригер ≡ розмір»: дату ARCH.46 звів, а поріг кожна половина читала у свій момент.
    BurnCarbonTokensWorker.perform_async(
      @contract.organization_id, @contract.id, nil, false, @target_date.to_s,
      BlockchainBurningService.frozen_verdict_law(stress_threshold: stress_threshold)
    )
    :degraded
  end

  # [SLASH-1] Малий кластер із критичним деревом — семпл, статистично недостатній для
  # АВТОМАТИЧНОГО присуду (розбір межі — у `perform`). Гроші однаково зупиняються через
  # Field Audit, слід у журналі лишається, рішення бере людина.
  def flag_insufficient_sample!(critical_count, total_trees)
    Rails.logger.warn "🔬 [D-MRV] NaasContract ##{@contract.id}: #{critical_count}/#{total_trees} критичних " \
                      "на кластері, меншому за поріг виродження — Field Audit, NO auto-slash (05_05 §5)."

    EwsAlert.escalate_field_audit!(
      cluster: @cluster,
      message_key: "cluster_small_sample_degradation",
      message_params: { critical_count: critical_count, total_trees: total_trees, target_date: @target_date }
    )

    :insufficient_sample
  end

  # [SLASH-1] Absence-of-data → freeze for Field Audit, NEVER slash. A
  # cluster-wide blackout (stolen/destroyed gateway, Starlink outage, storm) is
  # force-majeure, not the forester's negligence — burning subscriber tokens on it
  # would be a false slash (05_05 §1/§5). Raise a :field_audit escalation (NOT
  # :system_fault — see gap-D); the contract stays :active pending human
  # classification (Category C). «Тиша замовклого дерева — теж його голос».
  def flag_data_blackout!
    Rails.logger.warn "🌐 [D-MRV] NaasContract ##{@contract.id}: cluster-wide data blackout (#{@target_date}) — gateway-fault signature → Field Audit, NO slash (05_05 §5)."

    # [SLASH-1] :field_audit (не :system_fault): дерево замовкло — це НАШ виклик «слухай», окремий
    # від comms-fault, щоб не накручувати penalty_factor (gap-D) і не маскувати сигнали при дедупі.
    # Хелпер дедуплікує: багатоденний блекаут не плодить дубль щодоби.
    EwsAlert.escalate_field_audit!(
      cluster: @cluster,
      message_key: "cluster_data_blackout",
      message_params: { target_date: @target_date }
    )

    :blackout
  end
end
