# 06_05: Конфігурація Puma 8 (Web-сервер SilkenNet)

## 🎯 Мета

Зафіксувати архітектурні рішення та операційні runbook'и для Puma 8.0.2 — production HTTP-сервера SilkenNet. Документ описує **поточний стан** конфігурації та причини кожного вибору.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — конфігурація відповідає SSOT; IO-bound пул, cluster hooks і graceful shutdown **зашиті й покриті host-тестами**. ⚠️ **У Canopy НЕ верифіковані — і з 2026-09-01 підстава ЗМІНИЛАСЬ: staging-деплой БУВ** (серія прогонів `kamal deploy -d canopy`, контейнер стартував), але бут не завершується, тож Puma трафіку не приймала жодного разу — верифікація чекає не на деплой, а на завершений бут (⚠️ доказова дужка тут двічі протухала: у 2026-08-22 рядок стверджував верифікацію в середовищі, яке ніколи не піднімалось, а до 2026-09-01 цитував [`06_01`](06_01_Deployment_Kamal_Terraform) фразою «реальний деплой не проводився», яку той файл відтоді сам і спростував — дім факту лишається [`06_01 §Статус`](06_01_Deployment_Kamal_Terraform), але читай його, а не цю цитату). Реальна верифікація — після першого деплою, [`00_07`](00_07_Action_Plan_Tracker) S1.1.
- **Версія:** `puma (8.0.2)` (`Gemfile.lock`)
- **Конфігураційний SSOT:** `config/puma.rb`
- **Runtime-архітектура:** `Thruster (HTTP/2, TLS) → Puma (clustered, preload_app!) → Rails 8.1`
- **Puma middleware:** немає — `MarkWeb3RequestsAsIoBound` знято 2026-08-14 ([ARCH.80]; обґрунтування було мертве на обох шляхах)
- **Відкрите:** production verification (живий деплой) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `config/puma.rb` | Конфігурація (SSOT) |
| `Dockerfile` | `LD_PRELOAD=libjemalloc.so` (symlink на `libjemalloc.so.2`, пакет `libjemalloc2`), `CMD: thrust ./bin/rails server` |
| `config/application.rb` | Стек мідлварів: `Rack::Attack`, далі `PrometheusCollector` (після нього — НІЧОГО; те, що там стояло, знято [ARCH.80] — див. §IO-bound нижче) |
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | Kamal phased restart, `WEB_CONCURRENCY` |
| [`06_03` — Prometheus Observability](06_03_Prometheus_Observability) | `/metrics` endpoint |
| [`04_03` — REST API v1 Reference](04_03_REST_API_v1_Reference) | Список IO-bound endpoints |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | production verification |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Конфігурація — ключові рішення](#-конфігурація--ключові-рішення)
- [IO-bound позначення запитів — ЗНЯТО](#-io-bound-позначення-запитів--знято-arch80)
- [Операційні Runbooks](#-операційні-runbooks)
- [Валідація](#-валідація)
<!-- TOC:AUTO:END -->

---

## ⚙️ Конфігурація — ключові рішення

### 1. Потоки (threads) та IO-bound пул

```ruby
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)              # секція 1
threads threads_count, threads_count
max_io_threads ENV.fetch("PUMA_MAX_IO_THREADS", 16).to_i       # секція 1b
```

**Чому `threads = RAILS_MAX_THREADS` (default 3):** кожен потік відкриває власний DB-connection; пул рахує І io-burst: `pool = RAILS_MAX_THREADS + PUMA_MAX_IO_THREADS + 2 Cable = 21` (`config/database.yml` — SSOT формули; [INF.22]: io-марковані запити біжать понад `max_threads` і теж тримають checkout — пул без них голодує під сплеском; стеля, не преалокація). Job/Sidekiq-роль override `DB_POOL=17` — concurrency 15, деталі [`06_04 §2`](06_04_Secrets_Checklist). Бюджет з'єднань і запас `max_connections=400` — [`06_01 §Розрахунок max_connections`](06_01_Deployment_Kamal_Terraform).

**Чому `max_io_threads 16` лишається при НУЛІ позначених шляхів [ARCH.80]:** механізм Puma справний, але жоден запит більше не кличе `puma.mark_as_io_bound` — обґрунтування обох колишніх шляхів виявилось мертвим (обидва лише `perform_async`, синхронного HTTP немає), а на `provisioning/register` прапорець ще й брехав у шкідливий бік (HKDF = CPU-bound). Значення лишається як **готовність**, а не як активний бонус; деталі зняття — розділ нижче.

За замовчуванням `PUMA_MAX_IO_THREADS=16`. Нуль = відключено (backward-compatible з Puma < 8).

### 2. Workers

```ruby
default_workers = ENV.fetch("RAILS_ENV", "development") == "development" ? 0 : 2
workers ENV.fetch("WEB_CONCURRENCY", default_workers)
```

| Platform | vCPU | `WEB_CONCURRENCY` | RSS budget |
|---|---|---|---|
| Kamal app-хост | 2 vCPU (спека `config/deploy.yml`) | 2 | ~2 × 300 MB = 0.6 GB |
| GCP Kamal (fallback) | 2 vCPU | 2 | ~2 × 300 MB = 600 MB |
| Local dev | 8–16 cores | 0 (single-mode) | ~300 MB |

**Development (workers=0):** У development Puma запускається в single-mode (без fork). Це відповідає блоку `cluster do … end` в `puma.rb`, чиї хуки reconnect-after-fork **ніколи** не виконуються в single mode. Single-mode спрощує debugging (`binding.irb`, `debug` gem) та уникає master/worker fork-танцю.

**Чому не `:auto`:** `workers :auto` (Puma 7.2+) визначає count через `Etc.nprocessors`. На 16-core dev-ноутбуці це 16 workers × ~300 MB RSS = OOM при звичайному `bin/rails s`. Залишаємо явний `ENV.fetch` з dev-specific default `0`.

### 3. Preload app

```ruby
preload_app!
```

Завантажує Rails-додаток в master-процес перед fork. Forked workers успадковують незмінні сторінки пам'яті через OS-level CoW. В комбінації з `jemalloc` (`LD_PRELOAD` в Dockerfile) — −30–40% RSS на worker.

> Пума 8.0+ вмикає preload за замовчуванням у clustered mode. Рядок лишається для явного фіксування наміру.

### 4. Worker timeout та forced-shutdown debug

```ruby
worker_timeout ENV.fetch("PUMA_WORKER_TIMEOUT", 60)
shutdown_debug on_force: true
```

**Worker timeout:** Web3 RPC (Alchemy, Infura, Polygon) може зависнути на секунди. 60s — достатньо для легітимних довгих операцій (batch telemetry insert, Lorenz), але жорстко вбиває справді завислих workers.

**`shutdown_debug on_force: true`:** дамп backtraces ВСІХ threads виключно при forced shutdown (SIGKILL після `worker_timeout`) — не при graceful Kamal phased restart. Без `on_force:` дамп спамив би кожен деплой. Backtraces потрапляють у GCP Cloud Logging як structured JSON з `sentry_trace_id` для cross-reference у Sentry UI ([`06_03 §3.3`](06_03_Prometheus_Observability)).

### 5. Port

```ruby
port ENV.fetch("PORT", 3000)
```

Thruster слухає на `PORT` (80 у Docker) і reverse-proxy'ть до Puma на 3000. Puma 8.0+ за замовчуванням bind'иться на `tcp://[::]:3000` (dual-stack IPv4+IPv6) якщо доступний non-loopback IPv6 інтерфейс. `IPV6_V6ONLY=0` на Linux = `[::]:3000` приймає і v4, і v6.

Після першого Kamal-деплою на canopy перевірити **відповіддю, не переліком сокетів**:

```bash
kamal app exec -i "curl -sf -o /dev/null -w '%{http_code}\n' http://[::1]:3000/up"   # → 200
kamal app exec -i "grep -i ':0BB8 ' /proc/net/tcp6"                                  # zero-dependency дубль
```

🔴 **`ss -tlnp | grep 3000` тут НЕ працює, і це не «незручно», а неможливо (виміряно 2026-08-31):** `ss` дає пакет `iproute2`, а образ ставить рівно `curl libjemalloc2 libvips postgresql-client` (`Dockerfile`) — тобто форма `kamal app exec -i 'ss -tlnp | grep 3000'`, що стояла в §8 нижче, віддала б `command not found`. На хості ж 3000 не видно взагалі: Kamal-ролі мають `network-alias`, а не `publish` (`config/deploy.yml` — `publish` несе лише роль `coap`, і то `5683/udp`). ⚠️ Саме твердження, яке крок перевіряє, при цьому чинне — переміряне проти гема: `puma-8.0.2` `Configuration.default_tcp_host` = `ipv6_interface_available? ? '::' : '0.0.0.0'`. Відповідь на **IPv6-loopback** можлива лише при bind на `::`; `/up` виключений із `force_ssl`-редиректу й `host_authorization` (`probe_paths` у `production.rb`), тож 200 не маскується ані 301, ані 403.

Якщо потрібно примусово v4: `bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 3000)}"` — поки не додаємо, dual-stack краще для майбутньої IPv6-only інфраструктури.

### 6. Lifecycle hooks (clustered mode)

```ruby
cluster do
  before_fork { ... }
  before_worker_boot { ... }
end
```

`cluster do … end` — DSL Puma 8 — явно фіксує що хуки виконуються **лише** в clustered mode. В single mode (`workers 0`, dev) хуки no-op.

- **`before_fork`:** відключає всі ActiveRecord connection pools та Sidekiq Redis pool у master перед fork. Без цього — stale file descriptors у forked workers → socket hijacking. ⚠️ Виняток у цьому хуку Puma друкує в stdout разом із повідомленням, а `URI::InvalidURIError` несе ВЕСЬ URL із креденшелами (виміряно 2026-09-02 на скаліченому `REDIS_URL`); скраб Sentry (`sentry.rb`) на stdout не поширюється → ротація [`06_04 §5`](06_04_Secrets_Checklist).
- **`before_worker_boot`:** re-establish ActiveRecord connections + `Kredis.connections.clear` у кожному worker після fork. 🔴 **Доти тут стояв `Kredis.clear_all`, і це не синонім, а FLUSHDB** ([INF.22], 2026-08-30): гем гілкується на наявність namespace і без нього спорожняє базу — ту саму, що тримає живі Web3-локи й прапорці circuit-breaker'а. Чистити треба кеш ЗʼЄДНАНЬ (`connections`), а не сховище. ⚠️ **Дефект був ЛАТЕНТНИЙ, і це записано навмисно:** `clear_all` ітерує `connections.each_value`, тобто лише ВЖЕ закешовані зʼєднання, а майстер Puma на буті Kredis не торкається — успадкований хеш порожній, отже викликів до Redis було нуль. Озброївся б у день, коли щось прочитає Kredis-ключ у майстрі або ввімкнуть `fork_worker`. **Перша редакція цього рядка стверджувала, що воно «вимивало» локи на кожному деплої — це домисел, а не вимір** (гілку `flushdb` у гемі прочитали, досяжність не перевірили); поправка лишається тут, бо саме такий вигляд має підстава, вигадана заднім числом під правильний висновок.

---

### 7. `rack.response_finished` — відкладений запис кешу після flush (Puma 7.0+)

`actuators#execute` зберігає Idempotency-Key через `Rails.cache.write(cache_key, response_body, expires_in: 24.hours)` у Solid Cache (PostgreSQL). Запис перенесено у `rack.response_finished` callback (Puma 7.0+):

```ruby
env["rack.response_finished"] << ->(_env, _status, _headers, _error) {
  Rails.cache.write(cache_key, response_body, expires_in: 24.hours)
}
```

> ⚠️ **Сигнатура несуча (Rack SPEC):** Puma викликає кожен callback з **чотирма** аргументами `(env, status, headers, error)`. Вужча лямбда (`->(_env)`, як у першій редакції) кидає `ArgumentError`, який Puma **мовчки** ковтає у debug-лог — кеш ніколи не пишеться, а мережевий retry дублює фізичну актуацію. Зловлено аудитом 2026-07-04 (код+спека+цей канон утрьох носили ту саму хибну сигнатуру; спека симулювала виклик 1-аргументно і була зелена). Спека тепер симулює справжній 4-arity виклик.

Кеш пишеться **після** flush відповіді клієнту → зменшує p50 latency на ~1-2 мс. TTL та логіка незмінні. *(Мігровано з [`00_07`](00_07_Action_Plan_Tracker) PUMA-RACK-1.)*

> **Майбутнє (planetary scale):** при > 1M actuator-команд/добу — переглянути на користь batched cache writes.

---

## 🌐 IO-bound позначення запитів — ЗНЯТО [ARCH.80]

✅ **Присуд власника 2026-08-14: `MarkWeb3RequestsAsIoBound` видалено разом з обома його шляхами.** Тут доти жив опис живого механізму; збережено як запис про зняття, бо `max_io_threads` у `puma.rb` лишається налаштованим і наступний читач мусить розуміти, чому бонус недосяжний.

**Що було:** Puma 8.0+ виставляє `env["puma.mark_as_io_bound"]` — лямбду, після виклику якої thread переходить у IO-bound режим і може породжувати нові threads понад `max_threads`. Middleware кликав її для двох шляхів: `POST /api/v1/oracle_callbacks` і `POST /provisioning/register`.

🔴 **Чому знято — обґрунтування було мертве на ОБОХ шляхах, і вимір це показав, а не читання коментаря.** Канон (і сам middleware) стверджували «синхронно дзвонять по HTTP до IoTeX W3bstream / Polygon RPC / Hadron KYC (~200-2000 ms кожен)». Виміряно грепом по обох контролерах: єдиний зовнішній виклик у кожному — `perform_async`, тобто Sidekiq. **Синхронного вихідного HTTP на цих шляхах немає взагалі.**

🔴 **І прапорець брехав у ШКІДЛИВИЙ бік, не в нейтральний.** `provisioning#register` виконує HKDF-деривацію ключа (`HardwareKeyService`) — тобто він **CPU-bound**. Позначати CPU-роботу як IO-bound означає дозволяти Puma перепідписувати потоки під навантаження, що тримає процесор: пул, розрахований на «IO майже не споживає CPU», дістає рівно протилежне.

⚠️ **`max_io_threads 16` у `puma.rb` лишається СВІДОМО, і це не залишок:** механізм Puma справний, бонус просто недосяжний, доки ніхто не кличе лямбду. Того дня, коли зʼявиться справжній синхронний RPC-шлях, повертається і middleware (`git log` віддає його цілим), і рядок у пулі зʼєднань `database.yml`.

🔑 **Урок, ширший за цей файл: коментар, що НАЗИВАЄ причину, старіє тихіше за код, який її реалізує.** Обидві названі підстави (`peaq DID`, `Hadron KYC`) переїхали у воркери окремими комітами, і жоден із них не згадував ні middleware, ні цього канон-розділу. **Перед тим як спиратись на прапорець продуктивності, грепни те, що його ОБҐРУНТУВАННЯ називає — не сам прапорець.**

---

## 🔧 Операційні Runbooks

### SIGPWR — Backtrace dump у production

Puma 8.0+ підтримує `kill -PWR <puma_pid>` на Linux для негайного дампу backtraces всіх threads у лог (без зупинки worker).

```bash
# Команда для Kamal-хосту при підозрі на зависання Web3 RPC:
sudo docker exec silken_net-web-1 sh -c '
  PID=$(pgrep -f "puma .*cluster" | head -1)
  [ -z "$PID" ] && PID=$(pgrep -f "puma" | head -1)
  echo "Puma master PID: $PID"
  kill -PWR "$PID"
'
sudo docker logs silken_net-web-1 --tail 200
```

> У нашому контейнері PID 1 — Thruster (`CMD: thrust ./bin/rails server`). Puma — child. `pgrep -f "puma .*cluster"` знаходить master, `kill -PWR` дампить в STDERR → GCP Cloud Logging.

### IPv6 listen перевірка (після першого Kamal-deploy)

```bash
# ⚠️ ВСІ три — УСЕРЕДИНІ контейнера: голий `curl` на 127.0.0.1:3000 з машини оператора
# б'є в його ВЛАСНИЙ localhost (Kamal-ролі порт не публікують), тобто мовчки міряє не те.
kamal app exec -i "curl -sf -o /dev/null -w 'v4 %{http_code}\n' http://127.0.0.1:3000/up"
kamal app exec -i "curl -sf -o /dev/null -w 'v6 %{http_code}\n' http://[::1]:3000/up"
kamal app exec -i "grep -i ':0BB8 ' /proc/net/tcp6"   # 0x0BB8 = 3000; zero-dependency дубль
```

⛔ **`ss -tlnp` тут НЕ вживати** — `iproute2` в образі немає (підстава й вимір — §5 вище). Ця форма стояла в цьому блоці до 2026-08-31 і віддала б `command not found`, тобто верифікаційний крок повідомляв би про власну відсутність, а не про стан Puma.

Обидві відповіді `200` = dual-stack; `v4 200` при провалі `v6` = Puma сіла на `0.0.0.0:3000`, бо в namespace немає non-loopback IPv6-інтерфейсу (`Configuration.default_tcp_host` — §5). ✅ **Результат першого деплою (canopy, 2026-09-02): `v4 200` · `v6 000` · `/proc/net/tcp6` порожній, `/proc/net/tcp` несе `00000000:0BB8` — v4-only, і причину назвав прилад, не здогад: `docker network inspect kamal` → `EnableIPv6=false`, `/proc/net/if_inet6` у контейнері порожній.** Dual-stack є властивістю Docker-мережі `kamal` (її створює крок `docker network create kamal` у deploy-воркфлоу, без `--ipv6`), а не Puma; вмикати IPv6 у тій мережі сьогодні нема для кого — kamal-proxy ↔ контейнер ідуть v4-мостом, зовнішній IPv6 термінує Cloudflare — тож стан ПРИЙНЯТИЙ, а тригер перегляду той самий, що §5 називає для примусового v4: IPv6-only інфраструктура. ⚠️ Отже крок Фази 4 рунбука ([`06_01 §DEPLOY-DAY`](06_01_Deployment_Kamal_Terraform)) читай як «`v4 200` + записаний `v6`», а не як очікування `200` на `[::1]`.

### Health-проби: liveness `/up` · readiness `/ready`

| Endpoint | Перевіряє | Код | Роль |
|---|---|---|---|
| `GET /up` | процес живий (Rails `rails/health#show`, без залежностей) | 200 | **liveness** — рестарт-сигнал оркестратора (Kamal proxy / k8s) |
| `GET /ready` | DB (primary) + Sidekiq Redis + Kredis (mint/burn locks) round-trip (`ReadinessController`) — два різні КЛІЄНТИ, одна база | 200 `ready` / 503 `not_ready` | **readiness** — оркестратор гейтить трафік, поки залежність недоступна (обидва Redis мають відповісти — money-path safety) |

Обидва неавтентифіковані й виключені (production.rb) з `force_ssl`-redirect + host-authorization + Rack::Attack throttle — внутрішні HTTP/IP-проби працюють, часті проби не ловлять 429. Оркестратор (kamal-proxy / k8s) має вказувати `/ready` як healthcheck-ціль для readiness-gated cutover (не перемикати трафік, поки DB + Sidekiq-Redis + Kredis не готові); `/up` = liveness-рестарт. Багатий human-dashboard лишається admin-only `Api::V1::SystemHealthController` (CoAP / Sidekiq / DB; [`04_03 §4`](04_03_REST_API_v1_Reference)).

---

## ✅ Валідація

```bash
# 1. Синтаксична перевірка конфіга
ruby -c config/puma.rb

# 2. Стиль (RuboCop)
bin/rubocop config/puma.rb

# 3. Програмний boot (Puma::Configuration)
bundle exec ruby -e '
  require "puma"; require "puma/configuration"
  cfg = Puma::Configuration.new { |c| c.load("config/puma.rb") }
  cfg.clamp
  opts = cfg.options
  puts "workers: #{opts[:workers]}"
  puts "threads: #{opts[:min_threads]}/#{opts[:max_threads]}"
  puts "max_io_threads: #{opts[:max_io_threads]}"
  puts "shutdown_debug: #{opts[:shutdown_debug].inspect}"
  puts "before_fork hooks: #{opts[:before_fork]&.size || 0}"
  puts "before_worker_boot hooks: #{opts[:before_worker_boot]&.size || 0}"
'
# Очікується: workers=2, threads=3/3, max_io_threads=16, shutdown_debug=:on_force
```
