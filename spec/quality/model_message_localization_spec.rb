# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [I18N.4] Гейт ЛОКАЛІЗАЦІЇ повідомлень валідації: текст, який може побачити
# людина, живе в `config/locales/errors/**`, а модель несе КЛЮЧ.
#
# 🔴 Чому гейт, а не разовий прохід: `i18n-tasks` звіряє локаль ІЗ ЛОКАЛЛЮ
# (`missing`/`unused`/`eq-base`/інтерполяції), тож проза, що НІКОЛИ не стала
# ключем, невидима для нього ЗА ПОБУДОВОЮ — ключа не бракує, його немає. Саме
# тому клас пережив усю кампанію I18N.1.
#
# ✅ **Ключ реєстру — ПАРА «файл + сам текст» (2026-08-16), і це не косметика.**
# Доти ключем був `файл:РЯДОК`, тобто якір, volatile за побудовою: будь-яка правка
# ВИЩЕ по файлу зсувала номер, і гейт віддавав ДВА падіння одразу —
# «незадеклароване зашите повідомлення» + «декларація пережила свій предмет», —
# які читаються як два різні дефекти, хоч це один зсунутий якір. Виміряно ДВІЧІ за
# одну сесію (на `blockchain_transaction.rb` і `ai_insight.rb`), тобто це базова
# ставка на файлі, який редагують, а не курйоз. Текст уже є в руках екстрактора,
# тож стійкий ключ коштував нуль — і читається краще: видно, ЩО саме відкладено.
# ⚠️ Пара, а не склеєний рядок: повідомлення може містити будь-який роздільник,
# і склейка створила б власний клас невидимих колізій.
#
# 🔴 Периметр — ТРИ форми, і це не педантизм: дефект, що єдиний доводимо
# доходив до людини (`EIP55_MESSAGE`, сторінка Settings), жив у третій із них
# і був невидимий ОБОМ наявним інвентарям — і грепу по `message:`, і
# рантайм-обходу `validators` (константа не є `options[:message]` валідатора).
#
# ⚠️ СТЕЛІ, названі тут, бо без них зелений колір читатиметься ширше, ніж є:
#   · гейт ключується на НЕ-ASCII, тож **27 англійських зашитих літералів** у
#     тих самих формах він НЕ бачить. Вони так само не локалізовані — просто
#     їхня мова збігається з базовою локаллю. Сильніша форма («другий аргумент
#     `errors.add` і значення `message:` мусять бути СИМВОЛОМ») закриє й їх,
#     але вимагає рішення по кожному з 27 → `00_07` I18N.4;
#   · повідомлення, зібране інтерполяцією поза цими трьома формами, невидиме;
#   · повідомлення, що приходить із ГЕМА (`active_storage_validations` везе
#     власні ключі у 17 локалях), сюди не належить узагалі — і саме тому
#     `MaintenanceRecord#photos` свідомо не має `message:`.
#
# ⚠️ Якір `message:` несе межу слова НАВМИСНО: без неї він ловить
# `error_message:` — а то КОЛОНКА БД (`actuator_commands.error_message`), не
# повідомлення валідації. Спіймано читанням влучань, не наміром.
module ModelMessageLocalization
  NON_ASCII = /[^\x00-\x7F]/

  # ⛔ Кожен запис — ВІДКЛАДЕНЕ рішення, не «дозволено назавжди». `why` = чому
  # відкладено, `back` = подія, після якої рядок зникає, а гілка стає must-fix.
  # Спільна підстава всіх семи: ці моделі НЕ рендеряться через
  # `Views::Shared::UI::ErrorSummary` (його кличуть рівно шість форм —
  # firmwares · notifications · settings · maintenance · provisioning ·
  # tree_families), тож текст доходить лише до JSON-контуру або лога.
  DECLARED = {
    [ "app/models/actuator_command.rb",
      "дозволені лише команди формату ACTION або ACTION:value (напр. OPEN:60)" ] => {
      why: "формат команди; `actuators#execute` створює наказ усередині контролера, але " \
           "`RecordInvalid` там свідомо не має `rescue_from` і летить у generic 500 — " \
           "людина бачить `errors.api.internal`, кирилиця йде в `Rails.logger.fatal`",
      back: "як тільки помилка створення наказу почне рендеритись у формі"
    },
    [ "app/models/ai_insight.rb",
      "вже зафіксовано для цього об\x27єкта" ] => {
      why: "унікальність добового звіту; `AiInsight` створює лише InsightGenerator і воркери — " \
           "жодного контролера з create/update у дереві немає",
      back: "поява людського шляху створення інсайту"
    },
    [ "app/models/blockchain_transaction.rb",
      "має бути валідною Solana Base58 адресою" ] => {
      why: "формат Solana-адреси; рядки пише лише money-path із Sidekiq, контролер має " \
           "тільки index/show",
      back: "поява форми, що приймає адресу від людини"
    },
    [ "app/models/blockchain_transaction.rb",
      "slash-інтент мусить нести напрямок :burn [ARCH.95]" ] => {
      why: "інваріант напрямку [ARCH.95]; адресат — РОЗРОБНИК, що додає писача burn-рядка, " \
           "а не користувач: `blockchain_transactions` створюють лише money-path сервіси " \
           "(burning/klima/celo/insurance), контролер має тільки index/show. Спрацювання " \
           "означає баг у коді, не помилку вводу",
      back: "поява людського шляху створення транзакції — тоді рядок стає повідомленням форми"
    },
    [ "app/models/ews_alert.rb",
      "вже є активним для цього вузла" ] => {
      why: "унікальність активної тривоги; алерти народжуються виключно у воркерах/сервісах, " \
           "`alerts_controller` має лише index/show/resolve",
      back: "поява create-шляху тривоги з UI"
    },
    [ "app/models/tiny_ml_model.rb",
      "має відповідати формату семантичного версіонування (напр. v2.1.0)" ] => {
      why: "семантична версія; єдине місце створення в дереві — `db/seeds.rb`, поза продовим трафіком",
      back: "поява UI чи API для завантаження TinyML-моделі"
    },
    [ "app/models/wallet.rb",
      "Wallet має settled/in-flight/архів-стемпнуті blockchain-транзакції (MRV-докази) — деактивуй, не видаляй" ] => {
      why: "MRV-guard у `before_destroy`; `.destroy` на `Wallet` не кличе НІХТО в `app/`, " \
           "а `wallets_controller` не має дії `destroy` взагалі — гілка недосяжна",
      back: "поява будь-якого шляху знищення гаманця"
    }
  }.freeze

  # 🔴 [I18N.4, присуд founder 2026-08-14] Правило СИЛЬНІШЕ, але ВУЖЧЕ — і
  # обидві половини куплені одним аргументом.
  #
  # Сильніше: на моделях, чиї помилки доходять до ЛЮДИНИ, зашитий літерал
  # заборонено незалежно від мови. Доти гейт ключувався на не-ASCII, тобто
  # ловив лише кирилицю — а англійський зашитий рядок так само не локалізований,
  # просто збігається з базовою локаллю, і на людській формі це той самий дефект.
  #
  # Вужче: на решті моделей лишається старе правило (не-ASCII). Підстава —
  # ратифікований закон масштабування: **вартість іде за ПОПИТОМ, не за
  # каталогом** (`04_04 §8.1а`). Двадцять сім повідомлень на моделях, чиї
  # помилки бачить лише JSON, коштували б 108 записів у локалях для поверхні,
  # якої людина не читає, — і росли б із кожною новою мовою. Це рівно той
  # анти-патерн, що й per-locale стріми.
  #
  # ⚠️ Перелік людських поверхонь — ДЕКЛАРАЦІЯ, а не деривація, і це свідомо:
  # «чи побачить це людина» не має машинної форми (компонент бере запис
  # кwargʼом від контролера). Але декларація має ЖИВІСТЬ — приклад нижче звіряє
  # її з реальною множиною файлів, що рендерять `ErrorSummary`, В ОБИДВА боки,
  # тож нова форма червонить гейт, доки її модель не оголошено.
  HUMAN_SURFACES = {
    "app/views/components/firmwares/form.rb"        => "app/models/bio_contract_firmware.rb",
    "app/views/components/notifications/settings.rb" => "app/models/user.rb",
    "app/views/components/settings/show.rb"         => "app/models/organization.rb",
    "app/views/components/maintenance/form.rb"      => "app/models/maintenance_record.rb",
    "app/views/components/provisioning/new.rb"      => "app/models/tree.rb",
    "app/views/components/tree_families/form.rb"    => "app/models/tree_family.rb"
  }.freeze

  def self.human_reachable_models = HUMAN_SURFACES.values.to_set

  def self.error_summary_renderers
    Dir[Rails.root.join("app/views/components/**/*.rb")].filter_map do |path|
      rel = Pathname.new(path).relative_path_from(Rails.root).to_s
      rel if File.read(path).include?("Views::Shared::UI::ErrorSummary")
    end.to_set
  end

  def self.hits
    Dir[Rails.root.join("app/models/**/*.rb")].sort.flat_map do |path|
      rel = Pathname.new(path).relative_path_from(Rails.root).to_s
      human = human_reachable_models.include?(rel)

      File.readlines(path).each_with_index.filter_map do |line, idx|
        next if line.lstrip.start_with?("#")
        next unless offending_text(line, human_facing: human)

        # 🔴 [I18N.4, 2026-08-16] Ключ — ПАРА «файл + сам текст», а НЕ `файл:рядок`.
        # Номер рядка volatile за побудовою: будь-яка правка вище по файлу зсувала його,
        # і гейт віддавав ДВА падіння одразу («незадеклароване повідомлення» +
        # «декларація пережила свій предмет»), які читаються як два різні дефекти, хоч
        # це один зсунутий якір. Виміряно двічі за одну сесію — тобто це не курйоз, а
        # базова ставка на файлі, який редагують. Текст уже є в руках (`offending_text`
        # його щойно повернув), тож стійкий ключ коштує нуль. ⚠️ Пара, а не склеєний
        # рядок: текст може містити будь-який роздільник, і склейка створила б власний
        # клас невидимих колізій.
        [ rel, offending_text(line, human_facing: human) ]
      end
    end
  end

  # Читабельний рядок для повідомлення про помилку — ключ тепер пара, і сира
  # `#inspect` замість нього дала б `["app/models/x.rb", "текст"]` у кожному рядку звіту.
  def self.format_key(key)
    file, text = key

    "#{file} — «#{text}»"
  end

  # Три форми авторства, кожна з власним якорем. `human_facing` перемикає лише
  # ПОРІГ (будь-який літерал ⊥ лише не-ASCII), не перелік форм — інакше вузька
  # множина мала б власну сліпоту.
  def self.offending_text(line, human_facing: false)
    [
      line[/(?<![_a-zA-Z])message:\s*(["'])(.*?)\1/, 2],
      line[/errors\.add\([^,]+,\s*(["'])(.*?)\1/, 2],
      line[/^\s*[A-Z][A-Z0-9_]*(?:MESSAGE|ERROR)[A-Z0-9_]*\s*=\s*(["'])(.*?)\1/, 2]
    ].compact.find { |text| human_facing || text.match?(NON_ASCII) }
  end
end

RSpec.describe ModelMessageLocalization, type: :quality do
  it "не лишає НЕЗАДЕКЛАРОВАНОГО зашитого повідомлення в моделях" do
    undeclared = described_class.hits - described_class::DECLARED.keys

    expect(undeclared).to be_empty, <<~MSG
      Зашите повідомлення валідації в моделі — воно однакове в усіх локалях:

      #{undeclared.map { |k| described_class.format_key(k) }.join("\n      ")}

      Порядок питань ПЕРЕД тим, як заводити ключ (кожне куплене окремо, I18N.4):
        1. Чи доходить воно до ЛЮДИНИ? `ErrorSummary` кличуть рівно шість форм —
           якщо ні, місце рядка у `DECLARED` із `why`/`back`, а не в локалі.
        2. Чи не має цього ключа ГЕМ? `active_storage_validations` везе власні
           у 17 локалях — тоді лік це видалити наш рядок, а не перекласти його.
        3. Чи не бреше ОДИНИЦЯ, яку ти інтерполюєш? `%{count}` у `length`-валідаторі
           це СИМВОЛИ, а не байти.
        4. Чи не потребує число plural-форми (`lt` має `few`)?

      Лік: `message: :symbol_key` (або `errors.add(attr, :symbol_key)`) +
      рядок у `config/locales/errors/{en,uk,lv,lt}.yml`. Дім → `04_04 §12.14`.
    MSG
  end

  it "не тримає декларації, що пережила свій предмет" do
    stale = described_class::DECLARED.keys - described_class.hits

    expect(stale).to be_empty, <<~MSG
      Декларація без предмета — рядок уже полагоджено чи переїхав:

      #{stale.map { |k| described_class.format_key(k) }.join("\n      ")}

      Зніми запис ТИМ САМИМ комітом, що й фікс: реєстр, який пережив свою
      причину, читається як чинний дозвіл.
    MSG
  end

  it "кожна декларація несе ПІДСТАВУ і ПОДІЮ-закриття" do
    malformed = described_class::DECLARED.reject do |_, row|
      row[:why].to_s.strip.length > 20 && row[:back].to_s.strip.length > 10
    end

    expect(malformed.keys).to be_empty,
                              "Порожні/куці `why`/`back` не піняться нічим — саме тому вони ПОЛЯ, а не проза: #{malformed.keys}"
  end

  # 🔦 Ліхтар: без нього «нуль незадекларованих» було б однаково правдиве і для
  # здорового дерева, і для зламаного екстрактора.
  #
  # 🔴 Вхід СИНТЕТИЧНИЙ навмисно. Перша редакція пінила живі `file:line` із
  # `DECLARED` — і мутація показала, що вона червонітиме рівно тоді, коли хтось
  # ці рядки ПОЛАГОДИТЬ, тобто карала б покращення (design-rule §Guard-craft:
  # канарка мусить рахувати те, чого робота не сміє змінити). Форми змінитись
  # не можуть — вони і є предметом гейта.
  # 🔴 [I18N.4] Живість ДЕКЛАРАЦІЇ людських поверхонь. Перелік не деривується
  # («чи побачить це людина» машинної форми не має), але його ПРЕДМЕТ —
  # деривується: множина файлів, що рендерять `ErrorSummary`, читається з
  # дерева. Звірка йде В ОБИДВА боки, тож нова форма робить гейт червоним,
  # доки її модель не оголошено, а знята форма не лишає протухлого рядка.
  # Без цього прикладу «нуль порушень» на вузькій множині означало б «нуль
  # перевірок»: досить було б помилитись у шляху, і множина стала б порожньою.
  it "тримає перелік людських поверхонь у синхроні з деревом" do
    declared = described_class::HUMAN_SURFACES.keys.to_set
    actual   = described_class.error_summary_renderers

    expect(actual).not_to be_empty, "жоден компонент не рендерить ErrorSummary — екстрактор зламано"
    expect(actual - declared).to be_empty,
      "нова форма рендерить ErrorSummary, а її модель не оголошена: #{(actual - declared).to_a.sort.join(", ")}"
    expect(declared - actual).to be_empty,
      "оголошена поверхня більше не рендерить ErrorSummary: #{(declared - actual).to_a.sort.join(", ")}"
  end

  # Поріг мусить РІЗНИТИСЬ між двома множинами — інакше «сильніше на вузькій»
  # є заявою, а не механізмом. Пара доводить обидві половини присуду одразу.
  it "вимагає СИМВОЛА на людській поверхні й лише не-ASCII на решті" do
    english = %(validates :x, presence: { message: "can't be blank" })

    expect(described_class.offending_text(english, human_facing: true)).to eq("can't be blank")
    expect(described_class.offending_text(english, human_facing: false)).to be_nil
  end

  it "екстрактор впізнає ВСІ ТРИ форми авторства — інакше гейт стереже порожнечу" do
    expect(described_class.offending_text(%(validates :x, format: { message: "мусить бути" })))
      .to eq("мусить бути")
    expect(described_class.offending_text(%(  errors.add(:base, "не можна видаляти"))))
      .to eq("не можна видаляти")
    expect(described_class.offending_text(%(  EIP55_MESSAGE = "невалідна сума")))
      .to eq("невалідна сума")
  end

  # 🔴 Негативний контроль на ОБИДВА якорі, куплені хибними спрацюваннями проби:
  # `error_message:` — колонка БД, а константа з символом — уже полагоджена форма.
  it "не червонить на сусідніх формах, які повідомленнями НЕ є" do
    expect(described_class.offending_text(%(error_message: "Актуатор недоступний"))).to be_nil
    expect(described_class.offending_text(%(EIP55_MESSAGE_KEY = :invalid_eip55_checksum))).to be_nil
    expect(described_class.offending_text(%(errors.add(attribute, :invalid_eip55_checksum)))).to be_nil
    expect(described_class.offending_text(%(message: "must be a valid 0x address"))).to be_nil

    expect(described_class.offending_text(%(message: "має бути валідною адресою"))).to be_present
  end
end
