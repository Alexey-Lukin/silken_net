# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.3] 🔴 Один дім для класу «на рядок», бо детектор у нас уже є, а підмету — не було.
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
#   4. 🔴 **Детектор дискримінує РІЗНОМАНІТТЯ бінд-значень, а не сам повтор** —
#      виміряно 2026-08-19 на цьому ж файлі. Дві транзакції, що вказують на ОДИН
#      контракт, дають два ідентичних `SELECT … WHERE id = 7`, і Prosopite мовчить
#      (при `min_n_queries = 2`); щойно контракти різні — червоніє. Тобто фікстура
#      з двох рядків, чия асоціація резолвиться в СПІЛЬНИЙ запис, знезброює гейт
#      так само надійно, як фікстура з одного рядка. **Пишучи приклад, роби батьків
#      РІЗНИМИ.** ⚠️ І зворотний бік цієї межі — борг, не примха приладу: цикл, що
#      N разів тягне ТОЙ САМИЙ рядок, є чистішим марнотратством за класичний N+1,
#      і його тут не побачить ніхто.
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

  it "wallets#index — дерево й організація кожного гаманця" do
    trees = seeded { create_list(:tree, 2, cluster: cluster) }

    get "/wallets", headers: headers

    expect_rendered(*trees.map { |t| t.did.last(6) })
  end

  it "contracts#index — організація й кластер кожного контракту" do
    seeded do
      2.times { |i| create(:naas_contract, organization: organization, cluster: create(:cluster, organization: organization, name: "Grove-#{i}")) }
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

  it "alerts#index — кластер і дерево кожної тривоги" do
    trees = seeded do
      create_list(:tree, 2, cluster: cluster).each do |tree|
        create(:ews_alert, tree: tree, cluster: cluster, status: :active)
      end
    end

    get "/alerts", headers: headers

    expect_rendered(*trees.map { |t| t.did.last(6) })
  end

  it "blockchain_transactions#index — гаманець, дерево й кластер кожного рядка" do
    trees = seeded do
      create_list(:tree, 2, cluster: cluster).each do |tree|
        create(:blockchain_transaction, wallet: tree.wallet)
      end
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
