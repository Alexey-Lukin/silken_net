# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Носій інваріанта ⚡ PARTITION PRUNING [S6.16] (`04_01`).
#
# 🔴 Чому гейт, а не ще один абзац у каноні: інваріант БУВ записаний — «воркери/сервіси/
# контролери делегують сюди, НЕ дублюють» — і саме за його спиною клас відтворився тричі
# (`MintingRollbackService`, три мінт-воркери 2026-08-07, і `.reload` ще у двох місцях).
# Правило без носія не спрацьовує: у момент дії дешевша дорога виграє завжди, а `.reload`
# і `where(id:)` — найдешевші рядки в Rails. Тому перевірка стоїть тут, а не в пам'яті автора.
#
# ⚠️ Найдорожче в цьому класі — те, що дефект НЕ МАЄ СИМПТОМУ на малій базі: план виконання
# інший, а відповідь та сама, тож тести зелені, ревʼю нічого не бачить, і рахунок приходить
# лише на масштабі. На мінт-шляху промах при цьому ще й ТИХИЙ (`return unless log` → джоба
# завершується «успіхом», не зробивши нічого).
#
# 🔒 Стеля — девʼять речей, яких цей гейт НЕ бачить. Мовчання тут означало б «перевірено».
# ⚠️ Пункти 6-9 дописані ПІСЛЯ adversarial-ревю: перша редакція називала пʼять і читалась як
# вичерпна — тобто сама була заявою про повноту, якої не мала права робити.
#   1. **Тип він не виводить.** Ловляться лише звертання, ЯВНО префіксовані іменем моделі
#      (`BlockchainTransaction.where(id: …)`). `scope.where(id: …)`, `wallet.blockchain_transactions
#      .find(…)`, `relation.find_by(id:)` — невидимі за побудовою.
#   2. **`.reload` перевіряється за файлом, не за типом** — гейт не знає, на чому саме його
#      кличуть, тому вимагає ДЕКЛАРАЦІЇ на кожен виклик. Це і є лік: автор мусить відповісти
#      «а ця модель партиційована?», а не згадати правило.
#   3. **`status`-скани він не судить, і НЕ ПОВИНЕН** — `where(status: :pending)` без
#      `created_at` КОРЕКТНИЙ за ратифікованим ARCH.52 (reset-to-pending тримає старий
#      `created_at`, тож межа осиротила б застряглі кошти; важіль там — partial index).
#      Гейт, що вимагав би межі всюди, зламав би money-recovery — тому він мовчить про них.
#   4. **Асоціації й preload** (`has_one … order(created_at: :desc)` + `includes`) — інша
#      поверхня: там матеріалізується вся історія, і статично це не відрізнити від здорового
#      `includes`. Живий приклад лишається відкритим (`00_07` PERF.1, кандидат «а»).
#   5. **Прозу він не читає.** Коментар, що ОБІЦЯЄ прунінг там, де його немає, гейт пропустить
#      (так прожили чотири носії заяви про `unsettled_within`); це ловиться лише виміром.
#   6. 🔴 **Детекція ОДНОРЯДКОВА, а виправдання — трирядкове, і ця асиметрія його ж і послаблює.**
#      `Model\n  .where(id: …)` (перенесений ланцюг — домінантний стиль дерева) не матчиться
#      взагалі; дзеркально, `created_at` у ЧУЖОМУ виразі двома рядками нижче виправдовує сусіда.
#      Виміряно: живих ухилень цієї форми в дереві НУЛЬ, тож дірка поки теоретична — але
#      mutation-verify її б не показав, бо мутують однорядкову форму.
#   7. **`bounded_txs` у списку токенів безумовний, а сам хелпер — умовний**: він повертає
#      незвужений scope, коли `txs_created_from/to` = NULL (обидві колонки nullable). Тобто гейт
#      приймає за доказ виклик, що для legacy-батчу прунінгу не дає. Те саме формально вірне й
#      для `where_ids_pruned`: його ВЛАСНА семантика — деградувати на порожньому span'і.
#   8. **Периметр сканування — лише `app/**` + `lib/**/*.rb`**: `lib/tasks/*.rake`, `config/`, `db/`
#      поза ним. І альтернація ловить `where(id:` · `find(` · `find_by(id:`, але не `find_by!(id:)`,
#      не `find_by_id`, не `where( id:` із пробілом.
#   9. **`.reload` бере ХИБНО-ПОЗИТИВ на трейлінг-коментарі й рядковому літералі** (`foo # .reload`,
#      `"call .reload"`) — фільтр знімає лише РЯДКОВІ коментарі. Живих таких немає; коли зʼявиться,
#      лікується декларацією, а не розширенням regex'а (той почне їсти літерали).
#
# 🧮 **Рецепт РУЧНОГО підрахунку цього класу — бо гейт свідомо пропускає коментарі, а `grep` ні.**
# Пропуск правильний (інакше гейт червонів би на власних поясненнях), але сліпота мігрує в людський
# інструмент: половина хітів `grep -c '\.reload'` у цьому дереві — саме проза ПРО `.reload`, і саме
# так розмір класу завищується при кожному ручному вимірі. Рахуй тим самим фільтром, що й гейт:
#   `grep -rn '\.reload\b' app lib | grep -v ':\s*#'`
# ⚠️ Знана дірка того ж роду В ІНШИЙ бік: фільтр знімає лише РЯДКОВІ коментарі, тож `foo # .reload`
# у хвості рядка коду гейт порахує як виклик. Живих таких у дереві немає; якщо з'явиться —
# лікується не розширенням regex'а (він тоді почне їсти рядкові літерали), а декларацією.
RSpec.describe "partition-key discipline [S6.16]" do # rubocop:disable RSpec/DescribeClass
  # ── Реальна множина ─────────────────────────────────────────────────────────
  # Джерело істини — сам воркер обслуговування, не рукописний перелік тут: інакше
  # пʼята партиційована таблиця з'явилась би, а гейт лишився б зеленим на чотирьох.
  let(:partitioned_tables) { PartitionMaintenanceWorker::PARTITIONED_TABLES }
  let(:partitioned_models) { partitioned_tables.map(&:classify) }

  let(:scanned_files) { Dir[Rails.root.join("app/**/*.rb"), Rails.root.join("lib/**/*.rb")].sort }

  # Реєстр звільнень для §id-звертань: `why` = підстава, `back` = подія, після якої
  # рядок ЗНИКАЄ (без неї реєстр стає цвинтарем — форма з browser_contour_registry).
  let(:id_lookup_declarations) do
    {
      "app/models/ai_insight.rb" => {
        hits: 1, model: "TelemetryLog",
        why: "`AiInsight#source_logs` — evidence-persistence читач без жодного продового викликача " \
             "(лише власна спека), тож звертання сьогодні недосяжне; додавати `created_at` нема звідки " \
             "(`source_log_ids` зберігає самі id).",
        back: "перший продовий викликач `#source_logs` — тоді або нести мітки часу поруч з id, або зняти метод"
      }
    }
  end
  # ── 3. Явне id-звертання на партиційовану модель ────────────────────────────
  # Легальне, якщо в тому ж виразі (рядок + два наступні — ланцюг переноситься)
  # стоїть партиційний ключ або делегування в One-Home. Інакше — реєстр.
  # `created_at` як доказ звуження — але НЕ у формі сортування: `order(created_at: :desc)`
  # нічого не прунить, а виглядало б виправданням (знайдено adversarial-ревю).
  let(:pruning_tokens) { /created_at(?!\s*:\s*:(?:asc|desc))|partition_pruned|where_ids_pruned|bounded_txs/ }
  # ── 2. `.reload` — кожен виклик оголошений ──────────────────────────────────
  # Голий `.reload` б'є по самому PK. На партиційованій моделі це Global Partition
  # Scan; на звичайній — правильна форма. Розрізнити статично не можна, тому
  # вимагається декларація: дешево (виклики одиничні) і форсує саме те питання.
  let(:reload_declarations) do
    {
      "app/workers/stuck_sent_anchor_sweeper_worker.rb" => {
        calls: 1, model: "EthereumAnchor",
        why: "ethereum_anchors НЕ партиційована (db/structure.sql) — plain .reload тут коректний",
        back: :none
      },
      "app/workers/telemetry_archive_batch_worker.rb" => {
        calls: 1, model: "TelemetryArchiveBatch",
        why: "telemetry_archive_batches НЕ партиційована — plain .reload коректний",
        back: :none
      }
    }
  end

  def code_lines(path)
    File.readlines(path).each_with_index.reject { |line, _| line.strip.start_with?("#") }
  end

  def rel(path) = Pathname(path).relative_path_from(Rails.root).to_s

  # ── 1. Множина, яку стережемо, мусить збігатися з дійсністю ─────────────────
  describe "the guarded set" do
    it "knows every partitioned model the maintenance worker creates partitions for" do
      expect(partitioned_models).to contain_exactly(
        "TelemetryLog", "GatewayTelemetryLog", "BlockchainTransaction"
      )
    end

    it "resolves every name to a real model whose table is the partitioned one" do
      partitioned_models.zip(partitioned_tables).each do |name, table|
        expect(name.constantize.table_name).to eq(table)
      end
    end

    # One-Home покриває не всю родину, і це свідомо: у `GatewayTelemetryLog`
    # немає жодного id-звертання, тож хелпер там був би важелем без пускача. Пін
    # тримає саме цей факт — щойно з'явиться перший викликач, він і буде приводом.
    it "records which models actually carry a One-Home helper" do
      expect(TelemetryLog).to respond_to(:partition_pruned)
      expect(BlockchainTransaction).to respond_to(:find_with_partition_pruning, :where_ids_pruned)
      expect(GatewayTelemetryLog).not_to respond_to(:partition_pruned)
    end
  end


  describe "bare .reload" do
    let(:found) do
      scanned_files.each_with_object({}) do |path, acc|
        n = code_lines(path).count { |line, _| line.match?(/\.reload\b/) }
        acc[rel(path)] = n if n.positive?
      end
    end

    it "scans a non-empty population (a gate over an empty set is green forever)" do
      expect(scanned_files.size).to be > 300
    end

    it "has a declaration for every file that calls .reload" do
      expect(found.keys).to match_array(reload_declarations.keys),
                            "Незадекларований `.reload`. Питання не «чи він працює», а «чи ця модель " \
                            "партиційована». Якщо так — делегуй в One-Home (прецедент: " \
                            "CeloRewardReconcileWorker). Якщо ні — додай запис у `reload_declarations`."
    end

    it "notices the count changing inside an already-declared file" do
      expect(found).to eq(reload_declarations.transform_values { |d| d[:calls] }),
                       "Кількість `.reload` у задекларованому файлі змінилась. Червоне В ОБИДВА боки — і це " \
                       "навмисно: додавання = новий виклик без відповіді на питання «чи модель партиційована»; " \
                       "ВИДАЛЕННЯ = запис пережив свою причину, і його треба зняти ТИМ САМИМ комітом, інакше " \
                       "реєстр стає цвинтарем. Онови `calls:` або прибери рядок."
    end

    it "requires each declaration to name its model and its retirement condition" do
      reload_declarations.each_value do |d|
        expect(d[:model]).to be_present
        expect(d[:why]).to be_present
        expect(d).to have_key(:back)
      end
    end
  end


  describe "explicit id lookups on a partitioned model" do
    let(:found) do
      pattern = /(?:#{partitioned_models.map { |m| Regexp.escape(m) }.join("|")})\.(?:where\(id:|find\(|find_by\(id:)/
      scanned_files.each_with_object({}) do |path, acc|
        lines = File.readlines(path)
        n = code_lines(path).count do |line, idx|
          line.match?(pattern) && !lines[idx, 3].join.match?(pruning_tokens)
        end
        acc[rel(path)] = n if n.positive?
      end
    end

    it "matches the population it claims to scan (the pattern must not be inert)" do
      any = /(?:#{partitioned_models.map { |m| Regexp.escape(m) }.join("|")})\./
      hits = scanned_files.count { |p| code_lines(p).any? { |line, _| line.match?(any) } }
      expect(hits).to be > 10
    end

    it "has a declaration for every unpruned id lookup" do
      expect(found.keys).to match_array(id_lookup_declarations.keys),
                            "id-звертання на партиційовану модель без `created_at`. Делегуй у One-Home " \
                            "(`where_ids_pruned` для набору, `find_with_partition_pruning` для рядка), " \
                            "або зареєструй з причиною. ⚠️ Якщо це `status`-скан — межа тут ШКІДЛИВА " \
                            "(ARCH.52), і сайт не має влучати в цей патерн узагалі."
    end

    it "notices the count changing inside an already-declared file" do
      expect(found).to eq(id_lookup_declarations.transform_values { |d| d[:hits] }),
                       "Кількість незапрунених id-звертань у задекларованому файлі змінилась. Червоне в обидва " \
                       "боки навмисно: зменшення означає, що `back:`-подія настала — зніми рядок ТИМ САМИМ комітом."
    end

    it "requires each declaration to name the event that retires it" do
      id_lookup_declarations.each_value do |d|
        expect(d[:why]).to be_present
        expect(d[:back]).to be_present,
                            "порожній `back:` перетворює реєстр на цвинтар — назви подію, після якої рядок зникає"
      end
    end
  end
end
