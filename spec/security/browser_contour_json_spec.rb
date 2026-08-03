# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/browser_contour_inventory")
require Rails.root.join("spec/support/browser_contour_registry")

# [SEC.25] Сторож інваріанта `04_03 §2.2б`: дія браузерного контуру не сміє
# відповідати сирим JSON без `respond_to`.
#
# 🔴 Чому він узагалі потрібен, хоч вісь «закрита». Сім таких гілок закрито
# вручну, і жодна з них не могла почервоніти — периметр міряли грепом, тричі,
# і тричі помилялись. Наступний голий `render json:` у новому екшені проходить
# зеленим так само, як проходили ці. Тобто без цього файла «закрито» означає
# лише «здорове сьогодні».
#
# 🧱 ФОРМА — курована мапа, що ЛИШЕ СКОРОЧУЄТЬСЯ, і це вибір проти двох гірших:
#   · skip-list, який дозволяє дописувати винятки, гниє тихо й за півроку стає
#     фактичною політикою (та сама підстава, за якою відхилено `verify_authorized`);
#   · «полагодити всі 70» — відкидається тим, що більшість із них законна, а
#     решта недосяжна з UI, тобто фікс купував би вакуумні піни й з'їдений
#     coverage-слек проти невидимого промаху.
# Реєстр нижче не є дозволом. Кожен запис несе ПІДСТАВУ (`why`) і УМОВУ
# ПОВЕРНЕННЯ (`back`) — подію, після якої рядок звідси зникає, а гілка стає
# must-fix. Обидва поля гейтуються нижче, кожне окремим прикладом.
#
# ⚠️ Ключ реєстру — `файл#екшен`, свідомо БЕЗ номера рядка: рядки їдуть від
# кожної правки, і реєстр, ключований ними, червонів би на переміщенні коду,
# тобто навчав би себе ігнорувати.
#
# ─────────────────────────────────────────────────────────────────────────────
# 🔒 ЧОГО ЦЕЙ ГЕЙТ НЕ БАЧИТЬ — стелі названо явно, інакше зелений читається як
# «перевірено все». Перші три куплені написанням, решта — виміром [SEC.31].
#
#   1. Гейт бачить СИНТАКСИС, не намір. Він не знає, чи маршрут браузерний —
#      це вирішує `routes.rb` і питання «хто відвантажує клієнта» (ARCH.77).
#      Тому реєстр — декларація людини, а не висновок екстрактора.
#   2. Приватний JSON-хелпер (`render_forbidden_json`) синтаксично не
#      відрізняється від порушення; він у реєстрі саме як хелпер.
#   3. Гейт не ловить зворотний бік — дію, що має `respond_to`, але з ХИБНИМ
#      статусом. Її дім — `04_03 §2.2а` і піни на `media_type`.
#   4. 🔴 **Периметр — ЕКШЕНИ, не САЙТИ.** Ключ реєстру `файл#екшен` покриває
#      весь екшен цілком, тож ДРУГИЙ голий `render json:`, доданий у вже
#      зареєстрований екшен, гейт не побачить. Сьогодні 37 ключів покривають 70
#      сайтів, тобто половина периметра тримається підставою сусіда. Лічильник
#      сайтів на екшен відхилено виміром: 15 із 17 багатосайтових ключів не
#      називають числа в прозі, тож пін став би реєстром неперевірених чисел,
#      а машинне додавання (`request.format.json?`-гілка) червонило б чесний
#      рефактор. Ціна стелі реальна й ось де вона: у `codex/comments#create`
#      два сайти з трьох мають природу, іншу за зареєстровану.
#   5. 🔴 **Форма виклику лишається значущою і на рівні AST.** Екстрактор
#      бачить `render json:` та `render(json:)`, але хеш у дужках як один
#      позиційний аргумент, подвійний сплат і рядковий ключ — інші вузли, тобто
#      невидимі. Живих сайтів кожної форми сьогодні НУЛЬ (виміряно Prism-пробою),
#      тож це «порожньо», а не «безпечно». Деталь — у шапці екстрактора.
#   6. 🔴 **Усе всередині `respond_to` благословенне за побудовою** — включно з
#      `format.html { render json: … }`, який є §2.2б у чистому вигляді, і з
#      блоком, що має лише `format.json`. Виміряно по всіх 121 `respond_to`
#      дерева: блоків без `format.html` — нуль. Знову порожньо, не безпечно.
#   7. 🔴 **Гейт міряє ОБСЯГ зняття, і сліпий до трьох перемикачів, що вимикають
#      захист, нічого не знімаючи.** Перший — `handle_unverified_request`: для
#      41 з 45 контролерів реальна політика живе в тілі цього методу в
#      `Api::V1::BaseController`, а `protect_from_forgery` лише МАРШРУТИЗУЄ туди
#      неперевірений запит (сьогодні там свідомий і обґрунтований Bearer-обхід).
#      Другий — `protect_against_forgery?`/`verified_request?`: перевизначення
#      будь-якого робить гард no-op. Третій — глобальний
#      `config.action_controller.allow_forgery_protection`, який у test-середовищі
#      вже `false`, тобто звичайна request-спека цю вісь не бачить у принципі.
#      Кожен із трьох лишає всі приклади нижче зеленими.
# ─────────────────────────────────────────────────────────────────────────────
RSpec.describe "Браузерний контур: голий render json", type: :model do
  let(:sites)   { BrowserContourInventory.scan }
  let(:actual)  { sites.map { |s| BrowserContourInventory.key_for(s) }.uniq }

  it "жодна НОВА дія не відповідає сирим JSON поза реєстром" do
    unknown = actual - BrowserContourRegistry::ALL.keys

    expect(unknown).to be_empty, <<~MSG
      Нові сайти голого `render json:`/`head` поза `respond_to`:
        #{unknown.join("\n  ")}

      Це або дефект (`04_03 §2.2б` — людина побачить сирий блоб замість сторінки),
      або законний машинний/приватний випадок. Якщо друге — додай рядок у реєстр
      РАЗОМ із `why` та `back`. Голий запис без них не приймається:
      саме так skip-list стає фактичною політикою.
    MSG
  end

  # Друга половина «лише скорочується»: реєстр не сміє переживати свій предмет.
  it "реєстр не гниє — кожен його запис досі існує в дереві" do
    stale = BrowserContourRegistry::ALL.keys - actual

    expect(stale).to be_empty, <<~MSG
      Записи реєстру без відповідного сайту (гілку полагоджено або знято):
        #{stale.join("\n  ")}
      Прибери рядок — інакше реєстр описує світ, якого вже немає.
    MSG
  end

  # Ліхтар: реєстр без підстави — це просто дозвіл.
  it "кожен запис несе змістовну підставу" do
    empty = BrowserContourRegistry::ALL.select { |_k, e| e[:why].to_s.strip.length < 20 }
    expect(empty).to be_empty, "порожні підстави: #{empty.keys.join(', ')}"
  end

  # 🔴 ДРУГА ПОЛОВИНА ТІЄЇ САМОЇ КОНВЕНЦІЇ [SEC.31]. Шапка реєстру обіцяла
  # «підстава І умова повернення» з дня народження файла, а міряли лише першу —
  # і 17 із 37 записів другої не мали. Класика «гейт недо-імплементує контракт,
  # який сам оголошує»: двобічне формулювання — це обіцянка ДВОХ перевірок.
  #
  # ⚠️ Гейт навмисно НЕ лексичний. Пошук слова «повертається» червонів би на
  # чесній DRY-прозі («той самий клас query-гарда») і задовольнявся б порожнім
  # реченням — тобто міряв би СЛОВНИК. Тут міряється наявність ПОЛЯ.
  describe "умова повернення [SEC.31]" do
    it "кожен запис оголошує `back` — умову або явне :none" do
      undeclared = BrowserContourRegistry::ALL.reject do |_k, e|
        e[:back] == :none || e[:back].to_s.strip.length >= 10
      end

      expect(undeclared).to be_empty, <<~MSG
        Записи без оголошеної умови повернення: #{undeclared.keys.join(', ')}.
        `back:` — це подія, після якої рядок зникає, а гілка стає must-fix.
        Якщо браузерного двійника цій дії не існує — напиши `back: :none` ЯВНО.
      MSG
    end

    # `:none` тут не «я не придумав», а твердження «двійника не існує». Для
    # тимчасових категорій воно хибне за визначенням: вони й заведені тому, що
    # чогось ЩЕ не збудовано.
    it "LATENT і BY_DESIGN не мають права на :none — вони тимчасові за визначенням" do
      permanent = BrowserContourRegistry::LATENT
                  .merge(BrowserContourRegistry::BY_DESIGN)
                  .select { |_k, e| e[:back] == :none }

      expect(permanent).to be_empty, <<~MSG
        #{permanent.keys.join(', ')} оголошені постійними, хоч лежать у тимчасовій категорії.
        Або назви подію повернення, або перенеси запис у MACHINE/HELPERS із підставою.
      MSG
    end
  end

  # ─── ДРУГА ВІСЬ ТОГО САМОГО ПИТАННЯ [SEC.30] ────────────────────────────────
  # «Хто відвантажує клієнта» вирішує не лише формат відповіді, а й те, чи має
  # запит ambient authority. Машинний вхід її не має (доказ явний у кожному
  # запиті), браузерний має (cookie) — і CSRF стереже саме її.
  #
  # 🔴 Інваріант двобічний НЕ для симетрії: одна половина ловить мертвий
  # машинний вхід (знято автентифікацію, забуто CSRF → 500 до крипто-гарда),
  # друга — відкритий браузерний (знято CSRF там, де cookie реальна). Друга
  # важливіша, бо її промах тихий: жоден тест не падає від зайвої дірки.
  describe "CSRF на машинному контурі [SEC.30]" do
    def controller_root = Rails.root.join("app/controllers").to_s

    # 🔴 Предикат мусить міряти ДІЮ колбека, а не його ІМʼЯ [SEC.31]. Попередня
    # редакція питала `filter.include?(:verify_authenticity_token)` — і читала як
    # «гард на місці» ЧОТИРИ різні способи його зняти, бо `skip_callback` з
    # умовою не видаляє колбек, а підміняє його умовним близнюком із ТИМ САМИМ
    # символом. Виміряно: `only:` · `except:` · `skip_before_action` зі скоупом ·
    # `with: :null_session` — усі чотири давали `true`. Тобто приклад «частково
    # звільнений ЗБЕРІГАЄ гард» був тавтологією і не міг почервоніти НІКОЛИ.
    #
    # 🔴 І питати треба не «чи є умова», а НА ЯКИХ ДІЯХ гарда немає. Перша спроба
    # фіксу зупинилась на «умовний/безумовний» — і пропускала повну ІНВЕРСІЮ:
    # `only: :refresh` закриває машинну дію й відкриває cookie-дію, лишаючись
    # «умовним», як і правильне `only: :create`. Так само `except:` і
    # `only: [:create, :refresh]`. Тобто вердикт був про ФОРМУ зняття, а важить
    # його ОБСЯГ.
    #
    # Вимір поведінковий, а не структурний, і це не стиль: `only:` кладе фільтр
    # у `@unless`, а `except:` — у `@if`, тож розбір ivar-ів розсипався б на
    # формах. `ActionFilter#match?` — публічний API, і він відповідає рівно на
    # питання «чи спрацює колбек на цій дії».
    def unguarded_actions(klass)
      actions = klass.action_methods.to_a.sort
      # Сімʼя без CSRF-машинерії (`ActionController::API`) віддає ВСІ дії як
      # незахищені. Семантично це «не було», а не «знято», але наслідок для
      # браузерного контуру той самий, тож вердикт свідомо fail-closed: такий
      # контролер червонить, доки його не оголосять машинним. Живих нащадків
      # `ActionController::API` у дереві сьогодні нема.
      return actions unless klass.ancestors.include?(ActionController::RequestForgeryProtection)

      callback = klass._process_action_callbacks.find { |c| c.filter == :verify_authenticity_token }
      return actions if callback.nil?

      conditions = %i[@if @unless].map do |ivar|
        unless callback.instance_variable_defined?(ivar)
          raise "ActiveSupport::Callbacks::Callback більше не має #{ivar} — вимір треба переписати"
        end

        callback.instance_variable_get(ivar)
      end
      positive, negative = conditions

      actions.reject do |action|
        probe = klass.new
        probe.instance_variable_set(:@_action_name, action)
        positive.all? { |f| f.match?(probe) } && negative.none? { |f| f.match?(probe) }
      end
    end

    # Друга, НЕЗАЛЕЖНА вісь: колбек може стояти на всіх діях і однаково нічого не
    # робити, якщо стратегію підмінено (`with: :null_session` мовчки чистить
    # сесію замість кидати). Обсяг і стратегія падають окремо, тож і міряються
    # окремо — інакше одна перевірка обслуговувала б два різні твердження.
    def strategy_raises?(klass)
      klass.forgery_protection_strategy == ActionController::RequestForgeryProtection::ProtectionMethods::Exception
    end

    # 🔴 Корені деривуються з РЕАЛЬНОСТІ, а не перелічуються [SEC.31]. Літерал
    # знав два (`ApplicationController`, `Api::V1::BaseController`), а їх три:
    # `ReadinessController` успадковує `ActionController::Base` НАПРЯМУ. Перша
    # редакція знала лише один і міряла порожню множину; друга додала другий і
    # проґавила третій — тобто клас відтворювався щоразу, коли корінь дописували
    # руками. Корінь узято на рівень `Metal` (спільний предок `Base` і `API`),
    # щоб наступна сімʼя не випала так само мовчки; фільтр — походження файла.
    #
    # ⚠️ Стеля фільтра: анонімний клас (`Class.new`) імені не має, тож нашим
    # вважатись не може за побудовою — і сюди не потрапляє. Це безпечно рівно
    # доти, доки наші контролери оголошуються як константи у файлах.
    def ours?(klass)
      return false if klass.name.nil?

      Object.const_source_location(klass.name)&.first.to_s.start_with?(controller_root)
    rescue NameError
      false
    end

    def all_controllers
      Rails.application.eager_load!
      ActionController::Metal.descendants.select { |k| ours?(k) }
    end

    # Незалежне джерело істини — ФАЙЛИ. Роутер для цієї ролі не годиться, хоч і
    # спокушає: маршрутизований контролер є нащадком `Metal` за побудовою диспетча
    # і проходить той самий `ours?`, тож «маршрутизовані мінус деривовані» —
    # порожня множина ЗАВЖДИ, а не сьогодні. Тобто ліхтар із роутера був би
    # тавтологією й не побачив би навіть повного обвалу множини.
    #
    # `concerns/` виключено як Rails-конвенцію (це неймспейс міксинів, не
    # контролерів). Це єдиний літерал тут, і він гучний: файл поза `concerns/`,
    # який класу не оголошує, червонить гейт — краще хибна тривога, ніж тиха
    # сліпота, за яку цей пункт і заведено.
    def controller_files
      Dir.glob(Rails.root.join("app/controllers/**/*.rb"))
         .reject { |path| path.include?("/concerns/") }
         .sort
    end

    def declared_unguarded(klass, entry)
      entry[:unguarded] == :all ? klass.action_methods.to_a.sort : entry[:unguarded].sort
    end

    # 🔴 Дві сторони ОДНОГО обсягу, і кожна має власне падіння — інакше одна
    # перевірка обслуговувала б два протилежні дефекти й не розрізняла їх.
    it "жодна машинна дія не лишилась під CSRF-гардом" do
      under = BrowserContourRegistry::MACHINE_ENTRIES.filter_map do |name, entry|
        klass = name.constantize
        missing = declared_unguarded(klass, entry) - unguarded_actions(klass)
        "#{name}: #{missing.join(', ')}" if missing.any?
      end

      expect(under).to be_empty, <<~MSG
        Машинні дії, з яких CSRF НЕ знято: #{under.join('; ')}.
        Такий вхід падає `InvalidAuthenticityToken` → 500 ще ДО HMAC/Ed25519-перевірки,
        і сюїта цього НЕ бачить, бо test.rb вимикає allow_forgery_protection.
      MSG
    end

    # 🔴 Друга сторона, і саме вона перестала бути тавтологією: перевіряється не
    # «чи зняття скоуплене», а ЩО САМЕ звільнено. Інверсія (`only:` на cookie-дію),
    # розширення на весь контролер і `except:` дають РІЗНІ множини, тож кожна з
    # них червонить — доти всі три читались однаково як «скоуплене».
    it "жодна НЕзадекларована дія не втратила гард" do
      over = BrowserContourRegistry::MACHINE_ENTRIES.filter_map do |name, entry|
        klass = name.constantize
        extra = unguarded_actions(klass) - declared_unguarded(klass, entry)
        "#{name}: #{extra.join(', ')}" if extra.any?
      end

      expect(over).to be_empty, <<~MSG
        CSRF знято з дій, яких реєстр не оголошував: #{over.join('; ')}.
        У цих контролерах є дія, що автентифікується cookie-сесією (ambient authority
        реальна), тож зняття мусить накривати РІВНО машинні дії — інакше машинний
        вхід полагоджено ціною відкриття браузерного.
      MSG
    end

    it "стратегія кожного захищеного контролера справді КИДАЄ" do
      weak = all_controllers.reject { |k| strategy_raises?(k) }
                            .map(&:name) - BrowserContourRegistry::MACHINE_ENTRIES.keys

      expect(weak).to be_empty, <<~MSG
        `protect_from_forgery with:` не `:exception` у: #{weak.join(', ')}.
        Колбек стоїть на всіх діях і однаково нічого не боронить: `null_session`
        і `reset_session` мовчки чистять сесію замість відхилити запит.
      MSG
    end

    # Ліхтар на сам ВИМІР, і він міряє ПОВНОТУ, а не обвал: поріг на розмір
    # стеріг лише зникнення множини (45 контролерів при порозі 20 — запас на
    # втрату більш ніж половини), а промах цієї осі виглядає як ОДИН відсутній
    # елемент. Мутація-верифіковано звуженням `controller_root`: випадає рівно
    # `ReadinessController`, і саме його файл зʼявляється тут.
    it "деривована множина накриває кожен файл контролера" do
      covered = all_controllers.filter_map { |k| Object.const_source_location(k.name)&.first }.uniq
      missing = controller_files - covered

      expect(missing).to be_empty, <<~MSG
        Файли контролерів поза наглядом: #{missing.map { |p| p.sub("#{Rails.root}/", '') }.join(', ')}.
        Тобто клас у дереві є, а гейт його не міряє — рівно та форма сліпоти,
        через яку `ReadinessController` випадав із периметра [SEC.31].
      MSG
    end

    it "ніхто ІНШИЙ не знімає CSRF (тиха дірка не має симптому)" do
      unexpected = all_controllers.reject { |k| unguarded_actions(k).empty? }
                                  .map(&:name) - BrowserContourRegistry::MACHINE_ENTRIES.keys

      expect(unexpected).to be_empty, <<~MSG
        CSRF знято поза машинним реєстром: #{unexpected.join(', ')}.
        Звільнені дії: #{unexpected.map { |n| "#{n}=#{unguarded_actions(n.constantize).inspect}" }.join(', ')}.
        Якщо вхід справді машинний — додай його у BrowserContourRegistry::MACHINE_ENTRIES
        з `unguarded` та `why`. Якщо ні — це відкритий браузерний ендпоінт, і промах тут тихий.
      MSG
    end

    # Дзеркало ліхтаря «змістовної підстави» для CSRF-половини: доти її три
    # записи несли голий символ, тобто жили поза конвенцією, яку файл декларує,
    # а повідомлення гейта просило «додай із підставою» — те, чого структура
    # прийняти не вміла.
    it "кожен машинний вхід несе підставу зняття" do
      empty = BrowserContourRegistry::MACHINE_ENTRIES.select { |_n, e| e[:why].to_s.strip.length < 20 }
      expect(empty).to be_empty, "машинні входи без підстави: #{empty.keys.join(', ')}"
    end
  end
end
