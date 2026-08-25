# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsightGeneratorService, type: :service do
  let(:date) { Time.current.utc.to_date - 1 }
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, status: :active) }

  before do
    silence_broadcasts!(:wallet_balance, :tree_map)

    # create_fraud_alert! — ПУБЛІЧНИЙ class method (AlertDispatchService); стаб
    # верифікується штатно й служить обом полюсам: «не шле» (інертний гард) ⊥
    # «шле» (застаблений детектор). Стара обгортка without_partial_double_verification
    # стояла на протухлому «метод приватний» і ламала have_received зсередини.
    allow(AlertDispatchService).to receive(:create_fraud_alert!)
  end

  # 🔴 [ARCH.84] Симетрія з `Cluster#recalculate_health_index!`: денормалізований
  # стрес — це твердження про ДОБУ, тож дерево без телеметрії за цю добу дістає
  # явний `nil`, а не лишається з попереднім значенням. Доти тут стояв
  # `next unless stats`, і колонка тримала понеділковий показник на вівторковій
  # темряві — підміна виміру, лише постаріла, і тим небезпечніша, що правдоподібна.
  describe "денормалізований стрес мовчазного дерева" do
    # 🔴 ЯДРО ноги: дерево замовкло всередині кластера, який ДАНІ МАЄ. Саме тут
    # жив «понеділковий 0.42 на вівторковій темряві» — сусіди цокочуть, кластер
    # обробляється, а це дерево тримає позавчорашній показник. Два інші приклади
    # нижче ходять іншим механізмом (`reset_stress_outside`), тож без цього
    # найважливіша гілка лишалась без жодного проходу.
    it "занулює мовчазне дерево ВСЕРЕДИНІ кластера, що має дані" do
      silent = create(:tree, cluster: cluster, status: :active)
      silent.update_column(:latest_stress_index, 0.42)

      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(silent.reload.latest_stress_index).to be_nil
      # ⊥ Ліхтар: галасливий сусід у тому ж кластері дістав ВИМІР, не nil —
      # інакше приклад проходив би на поведінці, що просто занулює все підряд.
      expect(tree.reload.latest_stress_index).not_to be_nil
    end

    it "занулює в nil дерево, чий кластер за добу мовчав цілком" do
      tree.update_column(:latest_stress_index, 0.42)

      described_class.call(date)

      expect(tree.reload.latest_stress_index).to be_nil
    end

    # 🔴 Третій шар, знайдений прогоном: обидва шляхи писача обходять лише
    # кластери З ДАНИМИ, тож повністю мовчазний кластер не відвідується взагалі —
    # і його дерева тримали б учорашній стрес попри те, що ліс замовк цілком.
    it "занулює дерево в кластері, який замовк ПОВНІСТЮ" do
      dark_cluster = create(:cluster)
      dark_tree = create(:tree, cluster: dark_cluster, status: :active)
      dark_tree.update_column(:latest_stress_index, 0.7)

      # Живий кластер поруч — щоб прохід не був порожнім і мав що обробляти.
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(dark_tree.reload.latest_stress_index).to be_nil
    end

    # ⊥ Гілка «вже порожнє»: мовчазне дерево, чий стрес уже `nil`, ПОВТОРНОГО
    # запису не отримує. Гард не косметичний — без нього кожне мовчазне дерево
    # діставало б `UPDATE` щоночі назавжди, а знаменник тут 10¹² (`00_01 §1.1`).
    it "не переписує дерево, чий стрес уже порожній" do
      silent = create(:tree, cluster: cluster, status: :active)
      # Сусід із телеметрією тримає кластер «із даними», щоб прохід дійшов до циклу.
      loud = create(:tree, cluster: cluster, status: :active)
      create(:telemetry_log, tree: loud,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      expect { described_class.call(date) }.not_to change { silent.reload.latest_stress_index }
      expect(silent.reload.latest_stress_index).to be_nil
    end

    # ⊥ Крайній випадок тієї ж ноги: даних НЕМАЄ ЗОВСІМ, тож оброблених кластерів
    # нуль. Тоді вердикт «не виміряно» належить усьому флоту — і саме на цій гілці
    # `reset_stress_outside` працює без обмеження за кластером.
    it "занулює ВЕСЬ флот, коли за добу не було жодного кластера з даними" do
      tree.update_column(:latest_stress_index, 0.33)

      described_class.call(date)

      expect(tree.reload.latest_stress_index).to be_nil
    end

    # ⊥ Ліхтар: дерево З телеметрією дістає ВИМІРЯНЕ число, а не nil — інакше
    # приклад вище проходив би на будь-якій поведінці, що просто все занулює.
    it "лишає виміряне значення дереву, яке слало телеметрію" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(tree.reload.latest_stress_index).not_to be_nil
    end
  end

  # 🔴 [ARCH.84] ДРУГА причина мертвого маркера, незалежна від множини тригерів:
  # усі три писачі стресу йдуть `update_column`/`update_all`, а ті колбеків не
  # пускають ЗОВСІМ — тож навіть із правильним `map_relevant_change?` броадкаст не
  # стріляв би жодного разу. Дві причини множаться: фікс однієї з них наодинці не
  # міняє нічого видимого, і саме тому дефект прожив стільки — кожна половина
  # окремо виглядає як «зробили, а колір усе одно старий».
  describe "маркер перемальовується на КОЖНОМУ писачі стресу [ARCH.84]" do
    # Шпигун несе ще й ЗНАЧЕННЯ, а не лише факт виклику: маркер фарбується
    # стресом, тож броадкаст із застарілим числом у памʼяті — це той самий
    # мертвий колір, лише з живим сокетом. Масова гілка синхронізує колонку
    # вручну (замість N `reload`-ів), і без цього піна така синхронізація
    # зникає мовчки.
    let(:redrawn) { {} }

    before do
      allow_any_instance_of(Tree).to receive(:broadcast_map_update) { |t| redrawn[t.did] = t.latest_stress_index }
    end

    def loud_neighbour(in_cluster)
      create(:tree, cluster: in_cluster, status: :active).tap do |t|
        create(:telemetry_log, tree: t,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end
    end

    it "перемальовує дерево, що дістало ВИМІРЯНИЙ стрес" do
      loud = loud_neighbour(cluster)

      described_class.call(date)

      expect(redrawn).to have_key(loud.did)
      expect(redrawn[loud.did]).not_to be_nil
    end

    it "перемальовує мовчазне дерево, чий стрес занулено всередині кластера з даними" do
      silent = create(:tree, cluster: cluster, status: :active)
      silent.update_column(:latest_stress_index, 0.42)
      loud_neighbour(cluster)

      described_class.call(date)

      expect(redrawn).to have_key(silent.did)
      expect(redrawn[silent.did]).to be_nil
    end

    it "перемальовує дерево, занулене масовим `reset_stress_outside`" do
      dark = create(:tree, cluster: create(:cluster), status: :active)
      dark.update_column(:latest_stress_index, 0.7)
      loud_neighbour(cluster)

      described_class.call(date)

      expect(redrawn).to have_key(dark.did)
      # ⊥ Саме тут жив би `reload`: без синхронізації в памʼяті сюди приїхало б 0.7.
      expect(redrawn[dark.did]).to be_nil
    end

    # ⊥ Дзеркало, без якого приклади вище проходили б на «броадкасти все підряд»:
    # незмінене значення руху не дає. Знаменник ~10¹² дерев (`00_01 §1.1`), тож
    # безумовний броадкаст на кожному нічному проході — не марнотратство, а DoS.
    it "НЕ перемальовує дерево, чий стрес лишився тим самим порожнім" do
      quiet = create(:tree, cluster: cluster, status: :active)
      loud_neighbour(cluster)

      described_class.call(date)

      expect(redrawn).not_to have_key(quiet.did)
    end
  end

  describe "#perform" do
    it "creates daily health summary insights for each tree" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight).to be_present
      expect(insight.average_temperature).to eq(25.0)
      expect(insight.total_growth_points).to eq(10)
      expect(insight.fraud_detected).to be false
      expect(insight.summary).to include("ГОМЕОСТАЗ")
    end

    # 🔴 Пін на ОГОЛОШЕНУ інертність fraud-гарда (`#detect_fraud?` → false):
    # дизайн вимагає ДВОХ незалежних осей відхилення, а виміряна лишилась одна —
    # температура. Одна вісь — легітимна біологія (тепліший край насадження),
    # тож гард мовчить навіть на екстремальному відхиленні; звинувачення тут було б
    # гірше за мовчання. Тригер повернення названо в самому `#detect_fraud?`;
    # задротують детектор без другої осі — ці приклади червоніють першими.
    context "when temperature alone deviates >30% from the cluster baseline" do
      let(:normal_tree1) { create(:tree, cluster: cluster, status: :active) }
      let(:normal_tree2) { create(:tree, cluster: cluster, status: :active) }
      let(:warm_edge_tree) { create(:tree, cluster: cluster, status: :active) }

      before do
        # Два сусіди тримають центр базлайну; третє дерево тепліше за нього на ~50%.
        [ normal_tree1, normal_tree2 ].each do |t|
          create(:telemetry_log, tree: t,
            temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
            acoustic_events: 2, growth_points: 10,
            bio_status: :homeostasis, metabolism_s: 1000,
            created_at: date.beginning_of_day + 12.hours)
        end

        create(:telemetry_log, tree: warm_edge_tree,
          temperature_c: 50.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      it "не піднімає фрод-прапор і не шле фрод-алерт" do
        described_class.call(date)

        insight = AiInsight.find_by(
          analyzable: warm_edge_tree,
          insight_type: :daily_health_summary,
          target_date: date
        )
        expect(insight).to be_present
        expect(insight.fraud_detected).to be false
        expect(AlertDispatchService).not_to have_received(:create_fraud_alert!)
      end

      it "лишає growth points і чесний стрес (грошовий хвіст фроду не смикається)" do
        described_class.call(date)

        insight = AiInsight.find_by(
          analyzable: warm_edge_tree,
          insight_type: :daily_health_summary,
          target_date: date
        )
        expect(insight.total_growth_points).to eq(10)
        # [E.64] температура — не стрес-терм; homeostasis → чесний 0.0, не фродовий 1.0
        expect(insight.stress_index).to be_zero
      end
    end

    it "calculates correct stress_index for healthy trees (status 0)" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      # homeostasis (0) → base 0.0, z=0.5 (≤2.0) → no penalty, temp=25 (normal) → no penalty
      expect(insight.stress_index).to be_zero
    end

    it "is idempotent - reruns delete and recreate insights" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)
      initial_count = AiInsight.where(insight_type: :daily_health_summary, target_date: date).count
      expect(initial_count).to be > 0

      described_class.call(date)
      final_count = AiInsight.where(insight_type: :daily_health_summary, target_date: date).count

      expect(final_count).to eq(initial_count)
    end

    it "creates cluster-level aggregation insights" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      cluster_insight = AiInsight.find_by(
        analyzable: cluster,
        insight_type: :daily_health_summary,
        target_date: date
      )
      expect(cluster_insight).to be_present
      expect(cluster_insight.summary).to include(cluster.name)
    end

    # 🔴 [ARCH.84] Кластерне середнє німе про дерева, що мовчали, тож поруч мусить
    # їхати підстава — і саме ДАНИМИ, а не прозою. Доти дискримінатор існував лише
    # в `summary` («Оброблено N вузлів»), тобто жоден машинний читач (health_index →
    # комерційний `backing_asset.cluster_health`, Celo-виплата, IPFS-доказ) не
    # відрізняв кластер, виміряний на пʼяту частину, від виміряного повністю.
    it "records HOW MANY of the sector's living trees the cluster average actually speaks for" do
      loud = tree
      4.times { create(:tree, cluster: cluster, tree_family: tree.tree_family) }
      create(:telemetry_log, tree: loud,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      cluster_insight = AiInsight.find_by(analyzable: cluster, insight_type: :daily_health_summary,
                                          target_date: date)
      # Ліхтар на передумову: без нього приклад був би зелений і на кластері з одного дерева.
      expect(cluster.trees.active.count).to eq(5)
      expect(cluster_insight.measured_trees).to eq(1)
      expect(cluster_insight.total_trees).to eq(5)
    end

    # ✅ [SLASH-1] Свідок на пре-агрегацію ТЕПЕР Є — і заходить він НИЖЧЕ ідемпотентного
    # зрізу, бо саме той зріз доти робив пін неможливим: `perform` починається з
    # `AiInsight…delete_all` по всій добі, тож другий `model_source` не доживає до
    # агрегації в жодному сценарії, що йде через публічний вхід.
    #
    # 🔴 Тому приклад кличе `aggregate_cluster!` напряму (прецедент прямого виклику
    # приватного в цьому файлі — `calculate_stress_index` та сусіди; стаба на агрегацію
    # у файлі немає, перевірено). Це не обхід правила, а єдиний спосіб поставити
    # фікстуру у стан, який unique-індекс легалізує через nullable `model_source`, —
    # тобто у світ ПІСЛЯ першого писача денного інсайту поза цим сервісом.
    #
    # ⚠️ Обидві числові осі пінимо окремо, бо агрегати РІЗНІ за семантикою:
    # стрес — середнє (оцінка), бали — MAX на дерево (лічильник, не оцінка).
    describe "per-tree pre-aggregation [SLASH-1]" do
      it "weighs a tree ONCE even when two oracle sources reported it that day" do
        service = described_class.new(date)
        other = create(:tree, cluster: cluster, tree_family: tree.tree_family)

        # Дерево з ДВОМА джерелами (легально: `model_source` у unique-індексі)…
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
                            target_date: date, stress_index: 0.9, total_growth_points: 100,
                            model_source: "oracle_a")
        create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
                            target_date: date, stress_index: 0.9, total_growth_points: 100,
                            model_source: "oracle_b")
        # …і сусід з одним.
        create(:ai_insight, analyzable: other, insight_type: :daily_health_summary,
                            target_date: date, stress_index: 0.1, total_growth_points: 10,
                            model_source: "oracle_a")

        service.send(:aggregate_cluster!, cluster)

        insight = AiInsight.find_by(analyzable: cluster, insight_type: :daily_health_summary,
                                    target_date: date)

        # Рядково-зважене дало б (0.9+0.9+0.1)/3 = 0.633; по деревах — (0.9+0.1)/2 = 0.5.
        expect(insight.stress_index.to_f).to eq(0.5)
        # Сума по рядках дала б 210; MAX-на-дерево — 110.
        expect(insight.total_growth_points).to eq(110)
        expect(insight.measured_trees).to eq(2)
      end
    end

    # 🔴 [ARCH.84] Популяція середнього = ЖИВИЙ ліс, як у всіх трьох денних читачів
    # (`DailyHealthRouter`, `BlockchainBurningService#calculate_damage_ratio`). Доти
    # писач брав `cluster.trees` цілком, тож інсайт мертвого дерева входив у середнє —
    # те саме «кладовище розбавляло», що ⚖️ 2026-07-30 зняв на слешинг-шляху.
    # ⚠️ Пристрій про смерть дерева не знає, тож телеметрія від нього легітимно є.
    it "leaves the sector's dead out of the living forest's average" do
      dead = create(:tree, cluster: cluster, tree_family: tree.tree_family)
      [ tree, dead ].each do |t|
        create(:telemetry_log, tree: t,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end
      dead.update_column(:status, Tree.statuses[:deceased])

      described_class.call(date)

      cluster_insight = AiInsight.find_by(analyzable: cluster, insight_type: :daily_health_summary,
                                          target_date: date)
      # Обидва дерева МАЮТЬ добовий інсайт — відрізняється саме множина агрегату.
      expect(AiInsight.where(analyzable_type: "Tree", analyzable_id: [ tree.id, dead.id ],
                             target_date: date).count).to eq(2)
      expect(cluster_insight.measured_trees).to eq(1)
      expect(cluster_insight.total_trees).to eq(1)
    end

    it "returns processed count and date" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      result = described_class.call(date)

      expect(result).to eq({ processed_count: 1, date: date })
    end

    it "skips trees without telemetry logs" do
      tree_with_logs = create(:tree, cluster: cluster, status: :active)
      tree_without_logs = create(:tree, cluster: cluster, status: :active)

      create(:telemetry_log, tree: tree_with_logs,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(AiInsight.find_by(analyzable: tree_without_logs, insight_type: :daily_health_summary)).to be_nil
      expect(AiInsight.find_by(analyzable: tree_with_logs, insight_type: :daily_health_summary)).to be_present
    end

    it "skips trees with nil stats (no avg_temp)" do
      # A tree with active status but no telemetry_logs for the target date
      # should be skipped by generate_for_tree because stats&.avg_temp returns nil
      another_tree = create(:tree, cluster: cluster, status: :active)
      # Create a telemetry log on a different date so the tree has data but not for target date
      create(:telemetry_log, tree: another_tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: (date - 5.days).beginning_of_day + 12.hours)

      described_class.call(date)

      expect(AiInsight.find_by(analyzable: another_tree, insight_type: :daily_health_summary, target_date: date)).to be_nil
    end

    it "generates stress summary for status 1" do
      create(:telemetry_log, tree: tree,
        temperature_c: 40.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 5,
        bio_status: :stress, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      # Рядок називає СТАН сигналу (положення Z), не діагноз про світ за ним
      expect(insight.summary).to include("СТРЕС: Z нижче критичного мінімуму")
    end

    it "generates anomaly summary for status 2" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 5,
        bio_status: :anomaly, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      # Рядок називає СТАН сигналу (Z поза обвідною), не «хворобу чи шкідників»
      expect(insight.summary).to include("АНОМАЛІЯ: Z вийшов за обвідну гомеостазу")
    end

    it "generates firmware-fault summary for status 3 (vm_error)" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 5,
        bio_status: :vm_error, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight.summary).to include("ЗБІЙ ПРОШИВКИ")
    end

    it "handles errors gracefully and returns false for problematic trees" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      allow(AiInsight).to receive(:create!).and_call_original
      allow(AiInsight).to receive(:create!).with(hash_including(analyzable: tree)).and_raise(StandardError, "test error")

      allow(Rails.logger).to receive(:error).with(/Insight.*Помилка/)
      described_class.call(date)
      expect(Rails.logger).to have_received(:error).with(/Insight.*Помилка/)
    end

    context "with stress_index calculations" do
      it "[E.64] no longer penalizes raw avg_z (degenerate always-on term removed)" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # [E.64] homeostasis(0); z=3.0 no longer adds +0.2 (z_eq≥9 → was always-on); sap/acoustic inert → 0
        expect(insight.stress_index).to be_zero
      end

      it "[E.64] no longer adds an ambient-temperature weather penalty (high or low)" do
        create(:telemetry_log, tree: tree,
          temperature_c: 40.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # [E.64] homeostasis(0); temp=40 no longer adds +0.1 (weather discounts via VPD gate, never adds) → 0
        expect(insight.stress_index).to be_zero
      end

      it "[E.64] anomaly (status 2) → bounded 0.6, NOT 1.0 (05_05 §7 Z alone never slashes; < 0.83)" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 5,
          bio_status: :anomaly, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # [E.64] anomaly(2) → 0.6 base (no auto-1.0); below 0.83 tree slash threshold → cannot slash alone
        expect(insight.stress_index).to eq(0.6)
      end

      # [SLASH-1 P0] Інвертовано: старий пін `>= 3 → 1.0` цементував конфляцію
      # софт-збою з tamper — кластерний OTA-баг читався max-стресом на кожному
      # дереві (тригер слешу + damage-sizing разом). vm_error = статус НЕВІДОМИЙ
      # (пристрій не порахував) → 0.0, говорять лише прямі сигнали.
      it "[SLASH-1] vm_error (status 3) → 0.0 (firmware fault, NOT bio-stress)" do
        service = described_class.new
        expect(service.send(:calculate_stress_index_heuristic, 3, 25.0, 0, 0.5)).to eq(0.0)
      end

      it "[E.64] status 1 (stress) → bounded 0.6 (z/temp terms removed)" do
        create(:telemetry_log, tree: tree,
          temperature_c: 40.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 5,
          bio_status: :stress, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # [E.64] stress(1) → 0.6; z=3.0/temp=40 no longer contribute; sap/acoustic inert
        expect(insight.stress_index).to eq(0.6)
      end

      it "[E.64] calculate_stress_index status 1 → 0.6 (heuristic ignores z/temp)" do
        service = described_class.new
        # [E.64] status=1 → 0.6 base; avg_temp=40 / avg_z=3.0 no longer add
        result = service.send(:calculate_stress_index, 1, 40.0, 0, 3.0)
        expect(result).to eq(0.6)
      end
    end

    context "with cluster aggregation під інертним fraud-гардом" do
      let(:normal_tree) { create(:tree, cluster: cluster, status: :active) }
      let(:warm_edge_tree) { create(:tree, cluster: cluster, status: :active) }

      # ⊥ Дзеркало інертності на агрегаті: різке одноосьове відхилення не сміє
      # долетіти до кластерного summary словом «фрод». Позитивна половина гілки
      # `fraud_count > 0` живе в describe «фрод-хвіст лишається задротованим».
      it "каже «Стан стабільний», а не «фрод», навіть при різкому відхиленні" do
        create(:telemetry_log, tree: normal_tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        create(:telemetry_log, tree: warm_edge_tree,
          temperature_c: 50.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        cluster_insight = AiInsight.find_by(
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: date
        )
        expect(cluster_insight).to be_present
        expect(cluster_insight.summary).to include("Стан стабільний")
        expect(cluster_insight.summary).not_to include("фрод")
      end
    end
  end

  describe "nil stats branch" do
    it "returns false when stats.avg_temp is nil" do
      service = described_class.new
      # ⚠️ Verifying double тут НЕМОЖЛИВИЙ: `stats` — рядок GROUP BY-агрегату
      # (`prefetch_tree_stats`), де `avg_temp` живе лише як SQL-псевдонім SELECT.
      # `TelemetryLog` не оголошує його статично, тож `instance_double(TelemetryLog)`
      # падає «does not implement the instance method: avg_temp» (виміряно).
      stats = double("stats", avg_temp: nil) # rubocop:disable RSpec/VerifiedDoubles
      result = service.send(:generate_for_tree, tree, { temp: 25.0, z: 0.5 }, stats)
      expect(result).to be false
    end

    it "returns false when stats itself is nil (safe-navigation guard)" do
      service = described_class.new
      result = service.send(:generate_for_tree, tree, { temp: 25.0, z: 0.5 }, nil)
      expect(result).to be false
    end
  end

  # Гард нульового базлайну відносного відхилення (ділення на нуль → 0.0).
  # ⚠️ Викликачів у `app/` зараз НУЛЬ: fraud-гард оголошено інертним, а
  # `signed_deviation` знято — метод чекає app-сторонньої розв'язки долі разом
  # із fraud-хвостом. Пін тримає обидві гілки живими, доки метод у дереві.
  describe "#calculate_deviation" do
    let(:service) { described_class.new }

    it "returns 0.0 when the baseline is zero (no division by zero)" do
      expect(service.send(:calculate_deviation, 42.0, 0.0)).to eq(0.0)
    end

    it "returns the absolute relative deviation for a non-zero baseline" do
      expect(service.send(:calculate_deviation, 30.0, 40.0)).to eq(0.25)
    end
  end

  # 🔴 Пін на ОГОЛОШЕНУ інертність VPD-гейта: його передумова — ДВА входи
  # (погода І метаболічне відхилення), а другого виміру немає (`sap_flow` знято),
  # тож дисконтувати стрес самим вологим днем означало б вибачати посуху погодою.
  # Тригер повернення названо в самому методі (E.63 `delta_t`); задротують
  # дисконт без метаболічного входу — ці приклади червоніють першими.
  describe "#apply_weather_confounder" do
    let(:service) { described_class.new }

    it "returns stress unchanged even at saturated air (low VPD — the case the discount existed for)" do
      expect(service.send(:apply_weather_confounder, 0.9, 0.2)).to eq(0.9)
    end

    it "returns stress unchanged when avg_vpd is nil (firmware not yet emitting VPD — HW.32)" do
      expect(service.send(:apply_weather_confounder, 0.9, nil)).to eq(0.9)
    end
  end

  describe "VPD gate end-to-end (inert by declaration)" do
    it "plumbs avg_vpd into reasoning yet leaves stress_index unchanged (gate inert)" do
      create(:telemetry_log, tree: tree,
        temperature_c: 40.0, voltage_mv: 3500, z_value: 3.0, vpd: 0.1,
        acoustic_events: 2, growth_points: 5,
        bio_status: :stress, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      # [E.64] stress(1) → 0.6 (z/temp terms removed); VPD present but gate inert → unchanged 0.6
      expect(insight.stress_index).to eq(0.6)
      expect(insight.reasoning["avg_vpd"]).to eq(0.1)
    end
  end

  # 🔴 [ARCH.102] СТЕЛЯ евристики — несуча властивість, не побічний ефект:
  # прямих сигналів у ній НЕМАЄ (sap_flow без писача; acoustic_events — змішаний
  # канал кавітація/пилка, посуха з нього не деривується), тож евристичний шлях
  # сягає щонайбільше 0.6 і слешинг дерева (поріг 0.83) ним НЕДОСЯЖНИЙ.
  # Хтось поверне доданок без роздільного лічильника на дроті — пін червоніє.
  describe "евристична стеля нижча за поріг слешингу [ARCH.102]" do
    let(:service) { described_class.new }

    it "навіть найгірший вхід (anomaly + сатурована акустика + спека) лишається строго під slash_stress_threshold" do
      anomaly = TelemetryLog.bio_statuses.fetch("anomaly")
      worst = service.send(:calculate_stress_index_heuristic, anomaly, 55.0, 255, 9.9)
      expect(worst).to be < AiInsight.slash_stress_threshold
    end
  end

  describe "ML model integration" do
    context "when model file is missing" do
      it "falls back to heuristic stress_index calculation" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # Heuristic: homeostasis (0) → base 0.0, z=0.5 (≤2.0) → no penalty, temp=25 (normal) → 0.0
        expect(insight.stress_index).to be_zero
      end
    end

    context "when model file is present" do
      let(:mock_model) { instance_double(Rumale::Ensemble::RandomForestClassifier) }
      let(:model_data) { Marshal.dump(mock_model) }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return(model_data)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(OpenSSL::Digest::SHA256.hexdigest(model_data))
        allow(Marshal).to receive(:load).and_return(mock_model)

        proba_result = Numo::DFloat.cast([ [ 0.3, 0.7 ] ])
        classes = Numo::Int32.cast([ 0, 1 ])
        allow(mock_model).to receive_messages(predict_proba: proba_result, classes: classes)
      end

      it "uses ML model predict_proba for stress_index" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        expect(insight.stress_index).to eq(0.7)
      end
    end

    context "when model classes are in reversed order [1, 0]" do
      let(:mock_model) { instance_double(Rumale::Ensemble::RandomForestClassifier) }
      let(:model_data) { Marshal.dump(mock_model) }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return(model_data)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(OpenSSL::Digest::SHA256.hexdigest(model_data))
        allow(Marshal).to receive(:load).and_return(mock_model)

        # Reversed class order: stress (1) is at index 0
        proba_result = Numo::DFloat.cast([ [ 0.85, 0.15 ] ])
        classes = Numo::Int32.cast([ 1, 0 ])
        allow(mock_model).to receive_messages(predict_proba: proba_result, classes: classes)
      end

      it "correctly indexes the stress class probability" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # Class 1 is at index 0 → proba[0, 0] = 0.85
        expect(insight.stress_index).to eq(0.85)
      end
    end

    context "when model lacks stress class (1)" do
      let(:mock_model) { instance_double(Rumale::Ensemble::RandomForestClassifier) }
      let(:model_data) { Marshal.dump(mock_model) }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return(model_data)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(OpenSSL::Digest::SHA256.hexdigest(model_data))
        allow(Marshal).to receive(:load).and_return(mock_model)

        proba_result = Numo::DFloat.cast([ [ 1.0 ] ])
        classes = Numo::Int32.cast([ 0 ])
        allow(mock_model).to receive_messages(predict_proba: proba_result, classes: classes)
      end

      it "falls back to heuristic and logs error" do
        allow(Rails.logger).to receive(:error).with(/ML-модель не містить клас 1/)

        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        expect(Rails.logger).to have_received(:error).with(/ML-модель не містить клас 1/)
        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # [E.64] Heuristic fallback: homeostasis(0), z=3.0 no longer penalized → 0.0
        expect(insight.stress_index).to be_zero
      end
    end

    context "when model loading raises an error" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_raise(StandardError, "corrupt model")
      end

      it "falls back to heuristic and logs warning" do
        allow(Rails.logger).to receive(:warn).with(/Не вдалося завантажити ML-модель/)

        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        expect(Rails.logger).to have_received(:warn).with(/Не вдалося завантажити ML-модель/)
        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # [E.64] Heuristic fallback: homeostasis(0), z=3.0 no longer penalized → 0.0
        expect(insight.stress_index).to be_zero
      end
    end

    context "when model digest does not match (tampered file)" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return("tampered data")
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return("0000000000000000000000000000000000000000000000000000000000000000")
      end

      it "falls back to heuristic and logs warning about integrity" do
        allow(Rails.logger).to receive(:warn).with(/Не вдалося завантажити ML-модель/)

        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        expect(Rails.logger).to have_received(:warn).with(/Не вдалося завантажити ML-модель/)
        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # [E.64] Heuristic fallback: homeostasis(0), z=3.0 no longer penalized → 0.0
        expect(insight.stress_index).to be_zero
      end
    end

    context "when model digest file is missing" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(false)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return("some data")
      end

      it "falls back to heuristic and logs warning about missing digest" do
        allow(Rails.logger).to receive(:warn).with(/Не вдалося завантажити ML-модель/)

        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        expect(Rails.logger).to have_received(:warn).with(/Не вдалося завантажити ML-модель/)
        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        expect(insight.stress_index).to be_zero
      end
    end
  end

  # 🔴 Друга половина інертності: детектор оголошено мертвим, але його ХВІСТ
  # (грошовий шлях — нуль росту, max-стрес, алерт, фрод-агрегат) лишається
  # задротованим до тригера повернення. Живого шляху сюди немає, тож єдиний
  # чесний пуск — стаб самого `#detect_fraud?`; зникне хвіст — червоніє тут.
  describe "фрод-хвіст лишається задротованим (детектор застаблено)" do
    it "обнуляє ріст, ставить стрес 1.0, шле алерт і рахує фрод в агрегаті" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      service = described_class.new(date)
      allow(service).to receive(:detect_fraud?).and_return(true)
      service.perform

      fraud_insight = AiInsight.find_by(
        analyzable: tree,
        insight_type: :daily_health_summary,
        target_date: date
      )
      expect(fraud_insight.fraud_detected).to be true
      expect(fraud_insight.stress_index).to eq(1.0)
      expect(fraud_insight.total_growth_points).to eq(0)
      expect(fraud_insight.summary).to include("КРИТИЧНО")
      expect(AlertDispatchService).to have_received(:create_fraud_alert!).with(tree, date)

      cluster_insight = AiInsight.find_by(
        analyzable: cluster,
        insight_type: :daily_health_summary,
        target_date: date
      )
      expect(cluster_insight.summary).to include("фрод")
    end
  end

  # GenerateClusterInsightWorker path. Distinct from #perform because batch mode
  # is invoked with pre-computed cluster_ids and re-fetches baselines.
  describe "#process_cluster_batch" do
    let(:service) { described_class.new(date) }

    it "skips clusters whose baseline is missing" do
      empty_cluster = create(:cluster) # no telemetry → no baseline row
      expect {
        service.process_cluster_batch([ empty_cluster.id ])
      }.not_to(change(AiInsight, :count))
    end

    it "skips trees whose stats_map entry is nil and counts only generated trees" do
      tree_with_logs    = create(:tree, cluster: cluster, status: :active)
      tree_without_logs = create(:tree, cluster: cluster, status: :active)

      # Two telemetry rows establish a non-degenerate cluster baseline.
      [ tree_with_logs, tree ].each do |t|
        create(:telemetry_log, tree: t,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 1, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      processed = service.process_cluster_batch([ cluster.id ])

      expect(processed).to eq(2)
      expect(AiInsight.where(analyzable: tree_without_logs, target_date: date)).to be_empty
      expect(AiInsight.where(analyzable: tree_with_logs, target_date: date)).to exist
    end

    it "does not count trees whose generate_for_tree returns false (avg_temp nil)" do
      # AVG(temperature_c) is NULL when every row's temperature_c is NULL.
      # That yields stats present but stats.avg_temp == nil → generate_for_tree
      # returns false → @processed_count stays put.
      tree_no_temp = create(:tree, cluster: cluster, status: :active)
      [ tree, tree_no_temp ].each do |t|
        create(:telemetry_log, tree: t,
          temperature_c: nil, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 1, growth_points: 0,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      processed = service.process_cluster_batch([ cluster.id ])
      expect(processed).to eq(0)
    end
  end
end
