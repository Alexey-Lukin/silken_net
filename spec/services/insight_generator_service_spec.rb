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
    # ⚖️ [E.64 (Б)] Без прямого сигналу шов стресу дає `nil` на КОЖНІЙ добі, тож «виміряне ⊥
    # мовчазне» розрізняє лише день, коли сигнал Є. Стаб — саме такий день: механізм чекає
    # його, а без стаба ліхтарі нижче гасли б (обидві гілки давали б `nil`).
    before { allow_any_instance_of(described_class).to receive(:calculate_stress_index).and_return(0.37) }

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
        acoustic_events: 0, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(silent.reload.latest_stress_index).to be_nil
      # ⊥ Ліхтар: галасливий сусід у тому ж кластері дістав ВИМІР, не nil —
      # інакше приклад проходив би на поведінці, що просто занулює все підряд.
      expect(tree.reload.latest_stress_index).not_to be_nil
    end

    # 🔴 [ARCH.102] Доба, де в дерева лежать лише panic-рядки, ВИМІРУ не має: сенсори
    # там NULL, тож рядок групи є, а AVG = NULL. Без цього дерево під пилкою тримало б
    # учорашній стрес — ту саму «понеділкову 0.42», лише через іншу дірку.
    it "занулює дерево, чия доба несе лише panic-рядки без виміру" do
      under_saw = create(:tree, cluster: cluster, status: :active)
      under_saw.update_column(:latest_stress_index, 0.42)

      create(:telemetry_log, tree: under_saw, panic: true,
        temperature_c: nil, voltage_mv: nil, z_value: nil, acoustic_events: nil,
        growth_points: 0, bio_status: :homeostasis, metabolism_s: nil,
        created_at: date.beginning_of_day + 11.hours)
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 0, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(under_saw.reload.latest_stress_index).to be_nil
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
        acoustic_events: 0, growth_points: 10,
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
        acoustic_events: 0, growth_points: 10,
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
        acoustic_events: 0, growth_points: 10,
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
      # ⚖️ [E.64 (Б)] Без прямого сигналу шов стресу дає `nil` на КОЖНІЙ добі, тож «виміряне ⊥
      # мовчазне» розрізняє лише день, коли сигнал Є. Стаб — саме такий день: механізм чекає
      # його, а без стаба ліхтарі нижче гасли б (обидві гілки давали б `nil`).
      allow_any_instance_of(described_class).to receive(:calculate_stress_index).and_return(0.37)
    end

    def loud_neighbour(in_cluster)
      create(:tree, cluster: in_cluster, status: :active).tap do |t|
        create(:telemetry_log, tree: t,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 0, growth_points: 10,
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
        acoustic_events: 0, growth_points: 10,
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
            acoustic_events: 0, growth_points: 10,
            bio_status: :homeostasis, metabolism_s: 1000,
            created_at: date.beginning_of_day + 12.hours)
        end

        create(:telemetry_log, tree: warm_edge_tree,
          temperature_c: 50.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 0, growth_points: 10,
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
        # [E.64 (Б)] не фродовий 1.0 — і не вигаданий 0.0: прямого сигналу нема, вердикту нема
        expect(insight.stress_index).to be_nil
      end
    end

    # ⚖️ [E.64 (Б)] Гомеостаз — категорія z нашого `K_seed`, не вимір здоровʼя: 0.0 тут був би
    # виміряним нулем, з якого кластер дістав би «здоровʼя 100 %», а хроніка — «гомеостаз».
    it "[E.64 (Б)] gives a homeostasis day no stress verdict — nil, not a measured 0.0" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 0, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight).to be_present
      expect(insight.stress_index).to be_nil
    end

    it "is idempotent - reruns delete and recreate insights" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 0, growth_points: 10,
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
        acoustic_events: 0, growth_points: 10,
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
        acoustic_events: 0, growth_points: 10,
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

    # ⚖️ [E.64 (Б)] Середнє стверджує про ВСІХ `measured_trees` (пара покриття пінується в
    # IPFS поруч), тож свідок без стресу робить середнє `nil`, а не нулем у сумі: доти
    # `avg.to_f` давав тут (0.2 + 0) / 2 = 0.1 — число про двох, виміряне в одного.
    it "writes a nil cluster stress when any witnessing tree has no stress verdict" do
      service = described_class.new(date)
      other = create(:tree, cluster: cluster, tree_family: tree.tree_family)
      create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
                          target_date: date, stress_index: 0.2, total_growth_points: 10)
      create(:ai_insight, analyzable: other, insight_type: :daily_health_summary,
                          target_date: date, stress_index: nil, total_growth_points: 10)

      service.send(:aggregate_cluster!, cluster)

      insight = AiInsight.find_by(analyzable: cluster, insight_type: :daily_health_summary,
                                  target_date: date)
      expect(insight.stress_index).to be_nil
      expect(insight.measured_trees).to eq(2)
      expect(insight.total_growth_points).to eq(20)
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
          acoustic_events: 0, growth_points: 10,
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
        acoustic_events: 0, growth_points: 10,
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
        acoustic_events: 0, growth_points: 10,
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
        acoustic_events: 0, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: (date - 5.days).beginning_of_day + 12.hours)

      described_class.call(date)

      expect(AiInsight.find_by(analyzable: another_tree, insight_type: :daily_health_summary, target_date: date)).to be_nil
    end

    it "generates stress summary for status 1" do
      create(:telemetry_log, tree: tree,
        temperature_c: 40.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 0, growth_points: 5,
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
        acoustic_events: 0, growth_points: 5,
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
        acoustic_events: 0, growth_points: 5,
        bio_status: :vm_error, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight.summary).to include("ЗБІЙ ПРОШИВКИ")
    end

    it "handles errors gracefully and returns false for problematic trees" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 0, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      allow(AiInsight).to receive(:create!).and_call_original
      allow(AiInsight).to receive(:create!).with(hash_including(analyzable: tree)).and_raise(StandardError, "test error")

      allow(Rails.logger).to receive(:error).with(/Insight.*Помилка/)
      described_class.call(date)
      expect(Rails.logger).to have_received(:error).with(/Insight.*Помилка/)
    end

    # ⚖️ [E.64 (Б), founder 2026-10-10] Стрес = лише ПРЯМІ сигнали, а жодного не задротовано —
    # тож на БУДЬ-ЯКОМУ статусі й за будь-яких z/temp вердикту немає: `nil`. Не 0.0 (виміряний
    # нуль), не 0.6 (член статусу — лотерея `K_seed`), не 1.0 на vm_error (SLASH-1). Історія
    # знятих членів — коментар шва `calculate_stress_index`.
    context "with stress_index calculations [E.64 (Б)]" do
      TelemetryLog.bio_statuses.each_key do |status|
        it "#{status} day with z=3.0 and 40 °C → stress nil in the insight and on the tree" do
          # Учорашнє 0.6 колишнього члена статусу мусить зійти в `nil`, а не дожити.
          tree.update_column(:latest_stress_index, 0.6)
          create(:telemetry_log, tree: tree,
            temperature_c: 40.0, voltage_mv: 3500, z_value: 3.0,
            acoustic_events: 0, growth_points: 0,
            bio_status: status, metabolism_s: 1000,
            created_at: date.beginning_of_day + 12.hours)

          described_class.call(date)

          insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
          expect(insight).to be_present
          expect(insight.stress_index).to be_nil
          expect(tree.reload.latest_stress_index).to be_nil
        end
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
          acoustic_events: 0, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        create(:telemetry_log, tree: warm_edge_tree,
          temperature_c: 50.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 0, growth_points: 10,
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
    it "returns false when the day holds no measured (non-panic) row" do
      service = described_class.new
      # ⚠️ Verifying double тут НЕМОЖЛИВИЙ: `stats` — рядок GROUP BY-агрегату
      # (`prefetch_tree_stats`), де `measured_rows` живе лише як SQL-псевдонім SELECT.
      # `TelemetryLog` не оголошує його статично, тож `instance_double(TelemetryLog)`
      # падає «does not implement the instance method» (виміряно).
      stats = double("stats", measured_rows: 0) # rubocop:disable RSpec/VerifiedDoubles
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
        acoustic_events: 0, growth_points: 5,
        bio_status: :stress, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      # [E.64 (Б)] no verdict without a direct signal; the inert gate passes `nil` through unchanged
      expect(insight.stress_index).to be_nil
      expect(insight.reasoning["avg_vpd"]).to eq(0.1)
    end
  end

  # [FW.50] Сентинел температури пише `temperature_c` NULL при живих решті полях кадру. Така
  # доба ВИМІРЯНА: прочитана тишею, вона випала б зі знаменника свідків слешингу, хоча бали
  # за ті самі кадри нараховано. І температура в інсайті — NULL, не вигаданий нуль.
  describe "a day of live frames without temperature (FW.50 sentinel)" do
    it "still writes the insight, with average_temperature NULL and no fabricated temperature in the summary" do
      create(:telemetry_log, tree: tree,
        temperature_c: nil, voltage_mv: 3300, z_value: nil,
        acoustic_events: 0, growth_points: 10,
        bio_status: :stress, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight).to be_present
      expect(insight.average_temperature).to be_nil
      expect(insight.summary).to include("температуру не виміряно")
    end
  end

  # [FW.66 (Б)] CCM-рядок z не має, тож доба лише з таких рядків дає `AVG(z_value)` = NULL —
  # і хроніка мусить сказати «немає даних», а не надрукувати виміряний нуль (backend #64).
  describe "a day of rows without z (CCM era)" do
    it "keeps reasoning avg_z nil instead of a fabricated 0.0" do
      create(:telemetry_log, tree: tree,
        temperature_c: 20.0, voltage_mv: 3300, z_value: nil,
        acoustic_events: 0, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight.reasoning.fetch("avg_z")).to be_nil
    end
  end

  # 🔴 [ARCH.102 · E.64 (Б)] Стеля евристики — несуча властивість, не побічний ефект:
  # прямих сигналів у ній НЕМАЄ (sap_flow без писача; acoustic_events з HW.30 теж без
  # писача — пʼєзо зрізано, байт завжди 0), а член статусу знято 2026-10-10, тож шов
  # вердикту не дає зовсім, і слешинг дерева (поріг 0.83) ним НЕДОСЯЖНИЙ. Хтось поверне
  # доданок без ПРЯМОГО виміру — пін червоніє.
  describe "шов стресу без прямого сигналу вердикту не дає [ARCH.102 · E.64 (Б)]" do
    let(:service) { described_class.new }

    it "навіть найгірший вхід (anomaly + сатурована акустика + спека) дає nil" do
      worst = Struct.new(:max_status, :avg_temp, :max_acoustic, :avg_z)
                    .new(TelemetryLog.bio_statuses.fetch("anomaly"), 55.0, 255, 9.9)
      expect(service.send(:calculate_stress_index, worst)).to be_nil
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
        acoustic_events: 0, growth_points: 10,
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
          acoustic_events: 0, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      processed = service.process_cluster_batch([ cluster.id ])

      expect(processed).to eq(2)
      expect(AiInsight.where(analyzable: tree_without_logs, target_date: date)).to be_empty
      expect(AiInsight.where(analyzable: tree_with_logs, target_date: date)).to exist
    end

    it "does not count trees whose day holds only panic rows (no measurement)" do
      # Panic rows carry no sensors (ARCH.102), so the day has stats but zero measured
      # rows → generate_for_tree returns false → @processed_count stays put. ⚠️ [FW.50]
      # A NULL temperature alone no longer means «not measured» — see the sentinel example.
      tree_panic_only = create(:tree, cluster: cluster, status: :active)
      [ tree, tree_panic_only ].each do |t|
        create(:telemetry_log, tree: t, panic: true,
          temperature_c: nil, voltage_mv: nil, z_value: nil,
          acoustic_events: nil, growth_points: 0,
          bio_status: :homeostasis, metabolism_s: nil,
          created_at: date.beginning_of_day + 12.hours)
      end

      processed = service.process_cluster_batch([ cluster.id ])
      expect(processed).to eq(0)
    end
  end
end
