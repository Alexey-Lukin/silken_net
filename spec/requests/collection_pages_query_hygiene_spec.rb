# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.3] 🔴 Спільний дім для класу «на рядок», бо детектор у нас уже є, а підмету — не було.
#
# ⚠️ **«ОДИН дім» було завищенням, і adversarial-прохід 2026-08-20 довів це прогоном:**
# два сайти, якими цей файл виправдовували (`Tree#under_threat?` на `trees#index` і
# `gateways#show`), у ньому були ВІДСУТНІ — повернення дефекту лишало його зеленим
# (11/0), а червоніли пер-контролерні піни. Тобто клас мав два доми, і той, що
# називав себе єдиним, не ловив нічого зі свого ж виправдання. Виправлено: обидві
# сторінки тепер тут, а пер-контролерні піни лишаються ДРУГИМ шаром свідомо —
# вони пінять ще й вміст сторінки, чого цей файл не робить.
#
# Prosopite сканує КОЖЕН request-приклад (`rails_helper`) і ловить N+1 за
# визначенням — повторений запит. Але щоб повторитись, запитові потрібні ≥2 рядки,
# а канонічні HTML-приклади сторінок-списків роками рендерились із нуля або одного
# запису. Тобто гейт стояв на кожній із них і не міг спрацювати ЗА ПОБУДОВОЮ, і його
# мовчання було невідрізнимим від справності. Виміряно 2026-08-19: із пʼятнадцяти
# колекційних компонентів дерева тринадцять мали саме такий приклад.
#
# 🧱 Чому ОДИН файл, а не тринадцять правок у чужих спеках: там фікстура вже несе
# власні твердження, і додавання другого запису ламає сусідні лічильники —
# тобто ціна розмазується, а клас усе одно лишається без дому. Тут навпаки:
# кожен приклад коштує вісім рядків, а питання «чи покрита сторінка X» має адресу.
#
# 🔒 Стелі — інакше зелений читається ширше, ніж він є:
#   1. Судиться лише те, що рендериться на ПЕРШІЙ сторінці за дефолтної пагінації.
#   2. Prosopite ловить ПОВТОРЕНИЙ запит; фіксовану надлишковість (`.count` + `.each`
#      на одній relation — різні запити) він не бачить, її ловить лише вимір.
#   3. Це гейт РЕГРЕСІЇ, не інвентар: сторінка, якої тут немає, не перевіряється
#      ніде, тож новий колекційний екран додає сюди приклад.
#   4. 🔴 **Фікстура, чия асоціація резолвиться в СПІЛЬНИЙ запис, знезброює гейт
#      так само надійно, як фікстура з одного рядка — тож роби батьків РІЗНИМИ.**
#      ⚠️ **ПІДСТАВА під цим приписом була ХИБНА, і adversarial-прохід 2026-08-20
#      її замінив.** Тут стояло «детектор дискримінує різноманіття бінд-значень, а
#      не сам повтор» — неправда: Prosopite групує по `PgQuery.fingerprint`, який
#      СТИРАЄ літерали, тож однакові бінди падають в ту саму групу й повтору
#      самого достатньо. Мовчав не детектор, а **AR query cache**: підписка
#      відкидає події з `data[:cached]`, і N однакових читань у запиті не доїжджають
#      до БД узагалі. Практичні наслідки різні — ті читання не «чистіше марнотратство
#      за N+1», а хеш-хіт; і в контексті без кешу (`rails runner`, консоль) детектор
#      на них СПРАЦЮЄ. Припис вистояв, механізм під ним інший.
RSpec.describe "[UI.3] Колекційні сторінки: гігієна запитів", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, role: :admin) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}", "Accept" => "text/html" } }
  let(:cluster) { create(:cluster, organization: organization) }

  # Фікстурна підготовка — не поведінка під тестом: `Tree` має
  # `build_default_wallet`/`ensure_calibration` в `after_create`, тож саме
  # створення кількох записів виглядає для детектора як N+1. Пауза охоплює
  # РІВНО блок підготовки; `get` за її межами, інакше гейт знезброєно.
  def seeded
    Prosopite.pause if defined?(Prosopite)
    result = yield
    Prosopite.resume if defined?(Prosopite)
    result
  end

  # Ліхтар на РОЗМІР: без нього приклад зелений на порожній сторінці, тобто
  # атестує рівно те, що мав виміряти. Пін іде по тому, що сторінка ДРУКУЄ.
  def expect_rendered(*markers)
    expect(response).to have_http_status(:ok)
    markers.each { |m| expect(response.body).to include(m) }
  end

  it "trees#show — історія обслуговування (автор кожного запису)" do
    tree = seeded { create(:tree, cluster: cluster) }
    authors = seeded do
      Array.new(2) do |i|
        author = create(:user, organization: organization, first_name: "Ranger#{i}")
        create(:maintenance_record, user: author, maintainable: tree)
        author
      end
    end

    get "/trees/#{tree.id}", headers: headers

    expect_rendered(*authors.map(&:first_name))
  end

  it "gateways#index — кластер кожного шлюзу" do
    seeded do
      2.times { |i| create(:gateway, cluster: create(:cluster, organization: organization, name: "Sector-#{i}")) }
    end

    get "/gateways", headers: headers

    expect_rendered("Sector-0", "Sector-1")
  end

  it "actuators#index — шлюз кожного актуатора" do
    seeded do
      2.times do |i|
        gw = create(:gateway, cluster: cluster, uid: "SNET-Q-AAB0000#{i}")
        create(:actuator, cluster: cluster, gateway: gw)
      end
    end

    get "/clusters/#{cluster.id}/actuators", headers: headers

    expect_rendered("SNET-Q-AAB00000", "SNET-Q-AAB00001")
  end

  it "actuators#show — автор кожної команди" do
    actuator = seeded { create(:actuator, cluster: cluster, gateway: create(:gateway, cluster: cluster)) }
    authors = seeded do
      Array.new(2) do |i|
        author = create(:user, organization: organization, first_name: "Operator#{i}")
        create(:actuator_command, actuator: actuator, user: author)
        author
      end
    end

    get "/actuators/#{actuator.id}", headers: headers

    expect_rendered(*authors.map(&:first_name))
  end

  # 🔴 Імʼя ЗВУЖЕНО, як і в `contracts#index`, і з тієї ж виміряної причини:
  # `policy_scope(Wallet)` тенант-скоуплений, тож у наборі завжди РІВНО одна
  # організація — гаманець чужої просто не доїжджає, і фікстура з двома орг.
  # доводила б скоуп, а не прелоад. Вимірна половина — ДЕРЕВО.
  it "wallets#index — дерево кожного гаманця (орг. тенант-скоуплена)" do
    trees = seeded { create_list(:tree, 2, cluster: cluster) }

    get "/wallets", headers: headers

    expect_rendered(*trees.map { |t| t.did.last(6) })
  end

  # 🔴 Імʼя ЗВУЖЕНО свідомо, і це вимір, не лінь: вісь «організація кожного
  # контракту» на цій сторінці **невимірна за побудовою** — `policy_scope`
  # тенант-скоуплений, тож у наборі завжди РІВНО одна організація, і другий
  # контракт іншої орг. просто не доїжджає до сторінки (перевірено прогоном).
  # Ставити його у фікстуру означало б доводити тенант-скоуп, а не прелоад
  # (`04_06 §B.2` п.21: «чужий відсіює скоуп, ним фільтр не доведеш»).
  # Вимірна половина — КЛАСТЕР, і вона тут різна.
  it "contracts#index — кластер кожного контракту (орг. тенант-скоуплена)" do
    seeded do
      2.times { |i| create(:naas_contract, organization: organization,
                                           cluster: create(:cluster, organization: organization, name: "Grove-#{i}")) }
    end

    get "/contracts", headers: headers

    expect_rendered("Grove-0", "Grove-1")
  end

  it "audit_logs#index — автор кожного запису журналу" do
    authors = seeded do
      Array.new(2) do |i|
        author = create(:user, organization: organization, first_name: "Auditor#{i}")
        create(:audit_log, user: author, organization: organization)
        author
      end
    end

    get "/audit_logs", headers: headers

    expect_rendered(*authors.map(&:first_name))
  end

  # Кластери РІЗНІ: спільний `cluster:` робив половину «кластер кожної тривоги»
  # невимірною — прелоад можна було зняти й лишитись зеленим.
  it "alerts#index — кластер і дерево кожної тривоги" do
    trees = seeded do
      [ cluster, create(:cluster, organization: organization, name: "Sector-B") ].map do |cl|
        tree = create(:tree, cluster: cl)
        create(:ews_alert, tree: tree, cluster: cl, status: :active)
        tree
      end
    end

    get "/alerts", headers: headers

    expect_rendered(*trees.map { |t| t.did.last(6) })
  end

  # 🔴 Третій рядок БЕЗ гаманця — і він тут несучий, не повнота. Компонент пише
  # `tx.wallet&.tree&.did || tx.cluster&.name`, тобто `||` КОРОТКОЗАМКНЕНИЙ: за
  # наявного гаманця `tx.cluster` не кличеться ЖОДНОГО разу, і прелоад `:cluster`
  # лишався невимірним (adversarial 2026-08-20 — зняття його не червонило).
  # Cluster-sourced рядок гаманця не має ЗА ПОБУДОВОЮ (ARCH.98), і саме він
  # вправляє другу половину пари.
  it "blockchain_transactions#index — дерево гаманця ⊥ кластер cluster-sourced рядка" do
    trees = seeded do
      list = create_list(:tree, 2, cluster: cluster)
      list.each { |tree| create(:blockchain_transaction, wallet: tree.wallet) }
      [ create(:cluster, organization: organization, name: "Sector-C"),
        create(:cluster, organization: organization, name: "Sector-D") ].each do |cl|
        create(:blockchain_transaction, wallet: nil, cluster: cl)
      end
      list
    end

    get "/blockchain_transactions", headers: headers

    expect_rendered(*trees.map { |t| t.did.last(6) })
  end

  it "maintenance_records#index — автор і обʼєкт кожного запису" do
    authors = seeded do
      Array.new(2) do |i|
        author = create(:user, organization: organization, first_name: "Keeper#{i}")
        create(:maintenance_record, user: author, maintainable: create(:tree, cluster: cluster))
        author
      end
    end

    get "/maintenance_records", headers: headers

    expect_rendered(*authors.map(&:first_name))
  end

  it "trees#index — LED загрози на кожному рядку сітки" do
    trees = seeded do
      create_list(:tree, 2, cluster: cluster, status: :active).each do |tree|
        create(:ews_alert, tree: tree, cluster: cluster, status: :active)
      end
    end

    get "/clusters/#{cluster.id}/trees", headers: headers

    expect_rendered(*trees.map { |t| t.did.last(6) })
  end

  it "gateways#show — сітка флоту, LED на кожному вузлі" do
    gateway = seeded { create(:gateway, cluster: cluster) }
    trees = seeded do
      create_list(:tree, 2, cluster: cluster, status: :active).each do |tree|
        create(:ews_alert, tree: tree, cluster: cluster, status: :active)
      end
    end

    get "/gateways/#{gateway.id}", headers: headers

    expect_rendered(*trees.map(&:did))
  end

  it "dashboard#index — стрічка подій трьох різних типів" do
    # 🔴 `sourceable:` тут НЕСУЧИЙ, і перша редакція його не мала — через що
    # мутація «зняти `:sourceable` з прелоаду» лишала цей приклад ЗЕЛЕНИМ.
    # Причина рівно та, яку описує [`04_06 §B.2`](04_06_Testing_Guide_and_Coverage)
    # п.21: `sourceable_type IS NULL` не робить запиту ВЗАГАЛІ, тож фікстура без
    # джерела оголошує світ, у якому дефекту не існує. Спалення (`NaasContract`)
    # — той рядок, на якому прелоад починає щось означати.
    trees = seeded do
      create_list(:tree, 2, cluster: cluster).each do |tree|
        create(:ews_alert, tree: tree, cluster: cluster, status: :active)
        create(:blockchain_transaction, wallet: tree.wallet,
                                        sourceable: create(:naas_contract, organization: organization, cluster: cluster))
        create(:maintenance_record, user: user, maintainable: tree)
      end
    end

    get "/dashboard", headers: headers

    # ⚠️ Тут ліхтар мусив бути особливо явним: перша редакція пінила `trees.size`,
    # тобто ВЛАСНУ фікстуру, а не сторінку — приклад був би зелений і з порожньою
    # стрічкою. Стрічка друкує DID цілим (`event_target`), тож пін іде по ньому.
    expect_rendered(*trees.map(&:did))
  end
end
