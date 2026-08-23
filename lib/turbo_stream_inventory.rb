# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "ripper"

# Інвентар Turbo-стрім-тракту, знятий з AST (`Ripper`), а не регексом.
#
# 🔴 Чому AST, і це виміряно, не estetika: регекс наявного гейта
# (`spec/i18n/broadcast_payload_invariance_spec.rb`) вимагає БАГАТОРЯДКОВОГО
# виклику, тож однорядковий `broadcast_*_to(...)` для нього не існує — у
# `unpack_telemetry_worker.rb` він бачить 1 виклик із 2. Для гейта, якому
# потрібен ПОВНИЙ набір, пропущений виклик = хибно-зелений.
#
# 🔴 І друга причина, чому якір — ІМʼЯ МЕТОДУ, а не ресівер: turbo-rails
# домішує `Turbo::Broadcastable` у КОЖНУ AR-модель, тож `broadcast_refresh_later_to`
# легально викликається як instance-метод, без жодного `Turbo::StreamsChannel.`
# Екстрактор, прив'язаний до ресівера, пропустив би найідіоматичніший спосіб
# додати новий стрім.
#
# Pure Ruby: без Rails, без I/O понад читання переданих шляхів. Два консюмери
# за дизайном (вісь скоупу + вісь локалі payload'а) — тому й окремий модуль.
module TurboStreamInventory
  SUBSCRIBE_METHOD = "turbo_stream_from"

  # Токени, що роблять імʼя стріму самоочевидно тенант-скоупленим.
  SCOPE_TOKENS = %w[_org_ _organization_].freeze

  # Благословенний дім імен (`lib/turbo_streams/name.rb`) — єдине легальне
  # джерело РЯДКОВОГО імені стріму по обидва боки тракту.
  #
  # 🔴 Клас читається з ІМЕНІ МЕТОДУ, не з форми аргументу, і це не стиль:
  # аргумент після переїзду в дім став би просто `:indirect`, тобто два різні
  # обовʼязки доказу («org-токен в імені» проти «токена немає, безпечно лише
  # транзитивно») злились би в один клас — і гейт перестав би бачити зміну класу,
  # найгіршу подію на цій осі.
  #
  # `org_at` — той самий клас, що `org`, і навмисно: він будує імʼя ПОПЕРЕДНЬОЇ
  # епохи для tombstone'а при ротації [SEC.25 Ф3]. Без цього запису єдиний виклик
  # у дереві, що адресує щойно відкликане імʼя, падав би в `:indirect` — тобто
  # ставав би для гейта непрозорим саме там, де прозорість найпотрібніша.
  BLESSED_RECEIVER = %w[TurboStreams Name].freeze
  BLESSED_KINDS = {
    "org" => :derived_org,
    "org_at" => :derived_org,
    "gateway_ota" => :derived_gateway
  }.freeze


  # ⚠️ Член зветься `call_name`, а НЕ `method`: `Struct.new(:method)` перекриває
  # `Object#method`, тобто мовчки ламає інтроспекцію на кожному екземплярі.
  Site = Struct.new(:file, :line, :call_name, :arg_kind, :arg_pattern, keyword_init: true)

  class << self
    # Місця ПІДПИСКИ (`turbo_stream_from`) — саме вони мінтять capability-токен.
    def subscriptions(paths)
      scan(paths) { |name| name == SUBSCRIBE_METHOD }
    end

    # Імена локалів, яким у цьому файлі присвоєно виведене з ДОМУ імʼя стріму
    # (`stream = TurboStreams::Name.org(...)`).
    #
    # 🔴 Нащо це окремо, і чому саме воно, а не «пара продюсер⟷підписник».
    # Продюсер, що передає стрім НЕПРОЗОРО (`:indirect`), — це не дрібниця форми,
    # а фактична популяція дефектів цієї поверхні: пʼять продюсерів, знятих
    # 2026-07-27 як «у порожнечу», адресували стрім **параметром методу**
    # (`broadcast_slashing_event(contract, …)` → `contract`;
    # `broadcast_final_state(command, organization)` → `organization`), тобто
    # адресою, яку статично не бачить ніхто. Локал, присвоєний із дому, —
    # протилежний випадок: адреса виведена там само, де й у підписника.
    # Розрізнити їх коштує однієї передачі по AST; РЕЗОЛЬВИТИ значення не треба
    # ніколи — треба лише знати, що воно НЕ з дому.
    #
    # 🔒 Стеля названа: скоуп тут ФАЙЛОВИЙ, не методний. Однойменний локал в
    # іншому методі того ж файлу, присвоєний не з дому, пройде. Метод-скоуп
    # коштував би обходу `:def`-меж заради випадку, якого в дереві нема; коли
    # зʼявиться — звужувати сюди, а не в гейт.
    def blessed_locals(path)
      sexp = Ripper.sexp(File.read(path))
      return [] if sexp.nil?

      assigned_from_home(sexp)
    end

    # Місця БРОАДКАСТУ. Набір імен передає ВИКЛИКАЧ, і це свідомо:
    # 🔴 будь-який патерн тут хибний в обидва боки, і я зробив обидві помилки
    # по черзі, зміряв кожну. `broadcast_\w*_to` пропускає не-`_to` форми
    # (`broadcast_refresh` шле у ВЛАСНИЙ стрім моделі — стрім без імені й без
    # реєстру), а `broadcast_\w+` загрібає ВЛАСНІ приватні хелпери застосунку
    # (`broadcast_ota_progress`, `broadcast_command_state_static`…), що до API
    # гема не належать. Єдине незгниване джерело — сам гем:
    # `Turbo::Streams::Broadcasts` ∪ `Turbo::Broadcastable`, дериване у виклику,
    # тож апгрейд гема з новим методом покривається без правки цього файлу.
    def producers(paths, methods:)
      allowed = Array(methods).map(&:to_s)
      scan(paths) { |name| allowed.include?(name) }
    end

    private

    # `[:assign, [:var_field, [:@ident, "stream", …]], <rhs>]` — беремо лише ті,
    # де права частина є викликом благословенного дому. Рекурсія та сама, що в
    # `calls`: одна передача, без стану.
    def assigned_from_home(node, acc = [])
      if node[0] == :assign && node[1].is_a?(Array) && node[1][0] == :var_field
        name = ident_token(node[1][1])&.first
        acc << name if name && blessed_kind(node[2])
      end

      node.each { |child| assigned_from_home(child, acc) if child.is_a?(Array) }
      acc
    end

    def scan(paths)
      Array(paths).flat_map do |path|
        src = File.read(path)
        sexp = Ripper.sexp(src)
        next [] if sexp.nil? # синтаксично битий файл — не наша відповідальність

        calls(sexp).filter_map do |(name, line, first_arg)|
          next unless yield(name)

          # Не-`_to` форма адресує не аргументом, а САМИМ записом (`[self]`),
          # тож її перший аргумент — не імʼя стріму, і класифікувати його хибно.
          kind, pattern = name.end_with?("_to") || name == SUBSCRIBE_METHOD ? classify(first_arg) : [ :implicit_self, nil ]
          Site.new(file: path, line: line, call_name: name, arg_kind: kind, arg_pattern: pattern)
        end
      end
    end

    # ШІСТЬ форм виклику, які Ripper розрізняє, і всі шість тут перелічені
    # свідомо: `foo(a)` · `foo a` · `X.foo(a)` · `X.foo a` · `foo` · `X.foo`.
    # 🔴 Дві останні — БЕЗАРГУМЕНТНІ, і спершу я їх пропустив. Ціна була
    # виміряна мутацією: `broadcast_refresh` (успадкований, найідіоматичніша
    # форма того, що гейт забороняє) давав `:vcall`, тож приклад лишався
    # ЗЕЛЕНИМ при приземленій мутації — гейт не бачив рівно свого класу.
    # `consumed` не дає порахувати `X.foo(a)` двічі: внутрішній `:call`-вузол
    # уже спожитий обгорткою `:method_add_arg` (та відвідується раніше).
    # ⚠️ `consumed` — identity-хеш, а не мапа `object_id`: ключем іде сам вузол.
    # `object_id` як ключ переживає свій обʼєкт (id перевикористовуються після
    # GC), тобто теоретично дає ХИБНЕ «вже спожито» на чужому вузлі; тут дерево
    # живе весь прохід, тож різниця не в поведінці, а в тому, що форма більше
    # не спирається на цю обставину.
    def calls(node, acc = [], consumed = {}.compare_by_identity)
      name_node, args_node = shape(node, consumed)
      ident = name_node && ident_token(name_node)
      acc << [ ident[0], ident[1], first_arg(args_node) ] if ident

      node.each { |child| calls(child, acc, consumed) if child.is_a?(Array) }
      acc
    end

    # Кожна форма зводиться до пари (вузол-імені, вузол-аргументів) — рівно
    # ОДИН emit-шлях вище. Це не косметика: пʼять дубльованих emit'ів давали
    # пʼять окремих недосяжних гілок «а якщо імені немає».
    def shape(node, consumed)
      case node[0]
      when :method_add_arg
        consumed[node[1]] = true
        [ target_name(node[1]), node[2] ]
      when :command      then [ node[1], node[2] ]
      when :command_call then [ node[3], node[4] ]
      when :vcall        then [ node[1], nil ]
      when :call         then [ consumed[node] ? nil : node[3], nil ]
      else [ nil, nil ]
      end
    end

    # `[:fcall, ident]` (без ресівера) або `[:call, recv, period, ident]` (з ним).
    def target_name(target)
      target[0] == :fcall ? target[1] : target[3]
    end

    # ⚠️ Guard РЕАЛЬНО досяжний, не перестраховка: у proc-виклику `obj.()`
    # Ripper ставить на місце імені СИМВОЛ `:call`, не ident-вузол.
    def ident_token(node)
      return nil unless node.is_a?(Array) && node[0] == :@ident

      [ node[1], node[2][0] ] # [name, line]
    end

    def first_arg(args)
      list = args_list(args)
      list&.first
    end

    # 🔴 ТРЕТЯ сліпота форми виклику в цьому файлі, і знайдена так само — пробою,
    # не читанням (сиблінги: безаргументний `:vcall` у `shape`; `var_ref` ≠ запис
    # у `ref_kind`). Коли ВКЛАДЕНИЙ виклик іде без дужок — `f X.m a, b` — він
    # зʼїдає список аргументів собі, і вузол аргументів зовнішнього `:command`
    # приходить ГОЛИМ масивом arg-вузлів, без обгортки `:args_add_block`, яку
    # єдино й розпізнавала ця функція. Наслідок був `:absent`, тобто «аргументу
    # немає» на виклику, що його явно має.
    def args_list(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :arg_paren      then args_list(node[1])
      when :args_add_block then node[1]
      when Array           then node
      end
    end

    # Класифікація ПЕРШОГО аргументу — вона ж диспетчер proof-обовʼязку.
    # ⚠️ Класифікатор НЕ є перевіркою безпеки: він лише каже, який доказ
    # мусить існувати для цього сайту. Скоуп доводиться спекою, не формою імені.
    def classify(node)
      return [ :absent, nil ] if node.nil?

      blessed = blessed_kind(node)
      return [ blessed, nil ] if blessed

      case node[0]
      when :string_literal  then string_kind(node)
      when :array           then [ :record_array, nil ]
      when :symbol_literal  then [ :bare_symbol, nil ]
      when :var_ref, :vcall then ref_kind(node[1])
      else [ :indirect, nil ]
      end
    end

    # `TurboStreams::Name.org(...)` проти `.gateway_ota(...)`. Обидві форми
    # виклику з ресівером зводяться до однієї пари (`X.m(a)` = `:method_add_arg`
    # над `:call`; `X.m a` = `:command_call`) — той самий урок, що з
    # безаргументним `:vcall` у `shape`: форм виклику більше, ніж здається.
    # Ресівер звіряється як ПОВНИЙ набір const-токенів, тож `::TurboStreams::Name`
    # проходить, а однойменний `Name` з іншого простору імен — ні.
    def blessed_kind(node)
      call = node[0] == :method_add_arg ? node[1] : node
      return nil unless call.is_a?(Array) && %i[call command_call].include?(call[0])

      kind = BLESSED_KINDS[ident_token(call[3])&.first]
      return nil unless kind
      # ⚠️ Ресівер мусить бути ЧИСТИМ const-шляхом на ВСЮ глибину, не лише
      # зовнішнім вузлом: `const_tokens` сплощує піддерево, тож будь-який виклик
      # усередині дає ті самі токени й благословляється, хоч значення повертає
      # той виклик. Перша редакція перевіряла лише зовнішній вузол — і пропускала
      # `TurboStreams.dup::Name.org(...)` (перевірено Ripper'ом), тобто гейт
      # недо-імплементував власний коментар. Рекурсія закриває обидві форми.
      return nil unless pure_const_path?(call[1])

      const_tokens(call[1]) == BLESSED_RECEIVER ? kind : nil
    end

    # Приймає рівно `Name` · `A::Name` · `::A::Name`; відкидає все, де в дорозі
    # трапляється виклик, індексація чи будь-який інший вузол.
    def pure_const_path?(node)
      return false unless node.is_a?(Array)

      case node[0]
      when :@const                  then true
      when :var_ref, :top_const_ref then pure_const_path?(node[1])
      when :const_path_ref          then pure_const_path?(node[1]) && pure_const_path?(node[2])
      else false
      end
    end

    def const_tokens(node)
      return [] unless node.is_a?(Array)
      return [ node[1] ] if node[0] == :@const

      node.flat_map { |child| const_tokens(child) }
    end

    # ⚠️ `var_ref` НЕ означає «запис»: `@wallet` — запис, а локал `stream`, що
    # тримає рядок, — ні. Розрізняє саме тип токена, і це знайшлось заміром
    # проти ручного підрахунку (`unpack_telemetry_worker` маркувався `record_ref`,
    # хоч там локальна змінна з інтерполяцією) — тобто екстрактор ПЕРЕОЦІНЮВАВ
    # безпеку сайту, а це найгірший напрямок помилки для диспетчера.
    #
    # Для `:indirect` віддаємо ще й ІМʼЯ токена — без нього гейт не може відрізнити
    # локал, що несе виведене з дому імʼя, від параметра методу. А різниця тут
    # рівно та, що відділяє єдиний легітимний сайт від пʼяти історичних дефектів
    # (див. `blessed_locals`). `self` та інші не-ident токени лишаються безіменні.
    def ref_kind(inner)
      return [ :record_ref, nil ] if inner[0] == :@ivar

      [ :indirect, inner[0] == :@ident ? inner[1] : nil ]
    end

    def string_kind(node)
      parts = node[1][1..] || []
      literal = parts.select { |p| p.is_a?(Array) && p[0] == :@tstring_content }.map { |p| p[1] }.join
      interpolated = parts.any? { |p| p.is_a?(Array) && p[0] == :string_embexpr }
      pattern = interpolated ? "#{literal}\#{…}" : literal

      return [ :bare_string, pattern ] unless interpolated
      return [ :scoped_string, pattern ] if SCOPE_TOKENS.any? { |t| literal.include?(t) }

      [ :unscoped_interpolation, pattern ]
    end
  end
end
