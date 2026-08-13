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
    "app/models/actuator_command.rb:112" => {
      why: "формат команди; `actuators#execute` створює наказ усередині контролера, але " \
           "`RecordInvalid` там свідомо не має `rescue_from` і летить у generic 500 — " \
           "людина бачить `errors.api.internal`, кирилиця йде в `Rails.logger.fatal`",
      back: "як тільки помилка створення наказу почне рендеритись у формі"
    },
    "app/models/ai_insight.rb:66" => {
      why: "унікальність добового звіту; `AiInsight` створює лише InsightGenerator і воркери — " \
           "жодного контролера з create/update у дереві немає",
      back: "поява людського шляху створення інсайту"
    },
    "app/models/blockchain_transaction.rb:260" => {
      why: "формат Solana-адреси; рядки пише лише money-path із Sidekiq, контролер має " \
           "тільки index/show",
      back: "поява форми, що приймає адресу від людини"
    },
    "app/models/ews_alert.rb:135" => {
      why: "унікальність активної тривоги; алерти народжуються виключно у воркерах/сервісах, " \
           "`alerts_controller` має лише index/show/resolve",
      back: "поява create-шляху тривоги з UI"
    },
    "app/models/identity.rb:27" => {
      why: "прив'язка OAuth-акаунта; `save!` у `sessions#omniauth_create` → generic 500, " \
           "текст лише в лозі",
      back: "коли omniauth-гілка почне рендерити помилку у формі входу"
    },
    "app/models/tiny_ml_model.rb:37" => {
      why: "семантична версія; єдине місце створення в дереві — `db/seeds.rb`, поза продовим трафіком",
      back: "поява UI чи API для завантаження TinyML-моделі"
    },
    "app/models/wallet.rb:289" => {
      why: "MRV-guard у `before_destroy`; `.destroy` на `Wallet` не кличе НІХТО в `app/`, " \
           "а `wallets_controller` не має дії `destroy` взагалі — гілка недосяжна",
      back: "поява будь-якого шляху знищення гаманця"
    }
  }.freeze

  def self.hits
    Dir[Rails.root.join("app/models/**/*.rb")].sort.flat_map do |path|
      rel = Pathname.new(path).relative_path_from(Rails.root).to_s

      File.readlines(path).each_with_index.filter_map do |line, idx|
        next if line.lstrip.start_with?("#")
        next unless offending_text(line)

        "#{rel}:#{idx + 1}"
      end
    end
  end

  # Три форми авторства, кожна з власним якорем.
  def self.offending_text(line)
    declarative = line[/(?<![_a-zA-Z])message:\s*(["'])(.*?)\1/, 2]
    return declarative if declarative&.match?(NON_ASCII)

    imperative = line[/errors\.add\([^,]+,\s*(["'])(.*?)\1/, 2]
    return imperative if imperative&.match?(NON_ASCII)

    constant = line[/^\s*[A-Z][A-Z0-9_]*(?:MESSAGE|ERROR)[A-Z0-9_]*\s*=\s*(["'])(.*?)\1/, 2]
    return constant if constant&.match?(NON_ASCII)

    nil
  end
end

RSpec.describe ModelMessageLocalization, type: :quality do
  it "не лишає НЕЗАДЕКЛАРОВАНОГО зашитого повідомлення в моделях" do
    undeclared = described_class.hits - described_class::DECLARED.keys

    expect(undeclared).to be_empty, <<~MSG
      Зашите повідомлення валідації в моделі — воно однакове в усіх локалях:

      #{undeclared.join("\n      ")}

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

      #{stale.join("\n      ")}

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
