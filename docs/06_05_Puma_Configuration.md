# 06_05: Конфігурація Puma 8 (Web-сервер SilkenNet)

## 🎯 Мета

Зафіксувати архітектурні рішення та операційні runbook'и для Puma 8.0.1 — production HTTP-сервера SilkenNet. Документ описує **поточний стан** конфігурації та причини кожного вибору.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — конфігурація відповідає SSOT; IO-bound пул, cluster hooks та graceful shutdown верифіковані в Canopy.
- **Версія:** `puma (8.0.1)` (`Gemfile.lock`)
- **Конфігураційний SSOT:** `config/puma.rb`
- **Runtime-архітектура:** `Thruster (HTTP/2, TLS) → Puma (clustered, preload_app!) → Rails 8.1`
- **Puma middleware:** `MarkWeb3RequestsAsIoBound` (`app/middleware/mark_web3_requests_as_io_bound.rb`)
- **Відкрите:** production verification (живий деплой) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `config/puma.rb` | Конфігурація (SSOT) |
| `app/middleware/mark_web3_requests_as_io_bound.rb` | IO-bound middleware |
| `Dockerfile` | `LD_PRELOAD=libjemalloc2.so`, `CMD: thrust ./bin/rails server` |
| `config/application.rb` | Реєстрація middleware (після `PrometheusCollector`) |
| [06_01_Deployment_Kamal_Terraform](06_01_Deployment_Kamal_Terraform) | Kamal phased restart, `WEB_CONCURRENCY` |
| [06_02_Akash_Network_Integration](06_02_Akash_Network_Integration) | `WEB_CONCURRENCY=4` у Akash SDL |
| [06_03_Prometheus_Observability](06_03_Prometheus_Observability) | `/metrics` endpoint |
| [04_03_REST_API_v1_Reference](04_03_REST_API_v1_Reference) | Список IO-bound endpoints |
| [00_07_Action_Plan_Tracker](00_07_Action_Plan_Tracker) | production verification |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Конфігурація — ключові рішення](#-конфігурація--ключові-рішення)
- [MarkWeb3RequestsAsIoBound Middleware](#-markweb3requestsasiobound-middleware)
- [Операційні Runbooks](#-операційні-runbooks)
- [Валідація](#-валідація)
<!-- TOC:AUTO:END -->

---

## ⚙️ Конфігурація — ключові рішення

### 1. Потоки (threads) та IO-bound пул

```ruby
threads 3, 3                                                    # секція 1
max_io_threads ENV.fetch("PUMA_MAX_IO_THREADS", 16).to_i       # секція 1b
```

**Чому `threads 3, 3`:** кожен потік відкриває власний DB-connection. `Akash: 4 workers × 3 threads = 12 threads → 12 connections`. Значення `400` у `database.tf max_connections` має великий запас.

**Чому `max_io_threads 16`:** запити до Oracle (`oracle_callbacks` — Chainlink HMAC + Polygon `eth_call` через Alchemy) та provisioning (`provisioning/register` — peaq DID + Hadron KYC) синхронно дзвонять по HTTP (~200-2000ms кожен). При лише 3 CPU-threads три таких запити блокують увесь worker. IO-bound пул дозволяє до 3+16 паралельних threads на worker без OOM (IO-threads майже не споживають CPU).

За замовчуванням `PUMA_MAX_IO_THREADS=16`. Нуль = відключено (backward-compatible з Puma < 8).

### 2. Workers

```ruby
default_workers = ENV.fetch("RAILS_ENV", "development") == "development" ? 0 : 2
workers ENV.fetch("WEB_CONCURRENCY", default_workers)
```

| Platform | vCPU | `WEB_CONCURRENCY` | RSS budget |
|---|---|---|---|
| Akash SDL | 4 CPU units | 4 | ~4 × 300 MB = 1.2 GB |
| GCP Kamal (n2-standard-2) | 2 vCPU | 2 | ~2 × 300 MB = 600 MB |
| Local dev | 8–16 cores | 0 (single-mode) | ~300 MB |

**Development (workers=0):** У development Puma запускається в single-mode (без fork). Це відповідає блоку `cluster do … end` в `puma.rb`, чиї хуки reconnect-after-fork **ніколи** не виконуються в single mode. Single-mode спрощує debugging (`binding.irb`, `debug` gem) та уникає master/worker fork-танцю.

**Чому не `:auto`:** `workers :auto` (Puma 7.2+) визначає count через `Etc.nprocessors`. На 16-core dev-ноутбуці це 16 workers × ~300 MB RSS = OOM при звичайному `bundle exec rails s`. Залишаємо явний `ENV.fetch` з dev-specific default `0`.

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

**`shutdown_debug on_force: true`:** дамп backtraces ВСІХ threads виключно при forced shutdown (SIGKILL після `worker_timeout`) — не при graceful Kamal phased restart. Без `on_force:` дамп спамив би кожен деплой. Backtraces потрапляють у GCP Cloud Logging як structured JSON з `sentry_trace_id` для cross-reference у Sentry UI (`06_03 §3.3`).

### 5. Port

```ruby
port ENV.fetch("PORT", 3000)
```

Thruster слухає на `PORT` (80 у Docker) і reverse-proxy'ть до Puma на 3000. Puma 8.0+ за замовчуванням bind'иться на `tcp://[::]:3000` (dual-stack IPv4+IPv6) якщо доступний non-loopback IPv6 інтерфейс. `IPV6_V6ONLY=0` на Linux = `[::]:3000` приймає і v4, і v6.

Після першого Kamal-деплою на canopy: перевірити `ss -tlnp | grep 3000` (має показати `tcp6 LISTEN [::]:3000`) та виконати health-check через обидві адреси. Якщо потрібно примусово v4: `bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 3000)}"` — поки не додаємо, dual-stack краще для майбутньої IPv6-only інфраструктури.

### 6. Lifecycle hooks (clustered mode)

```ruby
cluster do
  before_fork { ... }
  before_worker_boot { ... }
end
```

`cluster do … end` — DSL Puma 8 — явно фіксує що хуки виконуються **лише** в clustered mode. В single mode (`workers 0`, dev) хуки no-op.

- **`before_fork`:** відключає всі ActiveRecord connection pools та Sidekiq Redis pool у master перед fork. Без цього — stale file descriptors у forked workers → socket hijacking.
- **`before_worker_boot`:** re-establish ActiveRecord connections + `Kredis.clear_all` у кожному worker після fork.

---

### 7. `rack.response_finished` — відкладений запис кешу після flush (Puma 7.0+)

`actuators#execute` зберігає Idempotency-Key через `Rails.cache.write(cache_key, response_body, expires_in: 24.hours)` у Solid Cache (PostgreSQL). Запис перенесено у `rack.response_finished` callback (Puma 7.0+):

```ruby
env["rack.response_finished"] << -> { Rails.cache.write(cache_key, response_body, expires_in: 24.hours) }
```

Кеш пишеться **після** flush відповіді клієнту → зменшує p50 latency на ~1-2 мс. TTL та логіка незмінні; spec coverage оновлено. *(Мігровано з `00_07 PUMA-RACK-1` 2026-05-28.)*

> **Майбутнє (planetary scale):** при > 1M actuator-команд/добу — переглянути на користь batched cache writes.

---

## 🌐 MarkWeb3RequestsAsIoBound Middleware

**Файл:** `app/middleware/mark_web3_requests_as_io_bound.rb`
**Реєстрація:** `config/application.rb` — після `PrometheusCollector`

### Як це працює

Puma 8.0+ виставляє `env["puma.mark_as_io_bound"]` → лямбду ДО виклику Rack-додатка (`puma/response.rb:75`). Middleware викликає цю лямбду (`&.call`) для вибраних endpoints:

```
POST /api/v1/oracle_callbacks       — Chainlink HMAC + Polygon eth_call dry-run
POST /api/v1/provisioning/register  — peaq DID registration + Hadron KYC HTTP
```

Після виклику лямбди Puma переводить цей thread у IO-bound режим і може породжувати нові threads понад `max_threads` (до `max_threads + max_io_threads`).

`&.call` — no-op коли env-key відсутній (rack-test, Falcon, dev single mode). Backward-compatible з будь-яким Rack сервером.

### Opt-in для нових endpoints

```ruby
# декларативний before_action у контролері:
before_action { request.env["silken_net.io_bound"] = true }

# або додати шлях у константу:
# app/middleware/mark_web3_requests_as_io_bound.rb
IO_BOUND_PATHS = Set.new(%w[
  /api/v1/oracle_callbacks
  /api/v1/provisioning/register
  /api/v1/new_io_heavy_endpoint   # ← додати тут
]).freeze
```

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
kamal app exec -i 'ss -tlnp | grep 3000'   # очікуємо: tcp6 LISTEN [::]:3000
curl -fsS http://127.0.0.1:3000/up           # health-check IPv4 loopback
curl -fsS http://[::1]:3000/up               # health-check IPv6 loopback
```

Якщо IPv6 відключено в namespace → Puma автоматично fallback'ає на `0.0.0.0:3000`. Задокументувати результат після першого деплою.

---

## ✅ Валідація

```bash
# 1. Синтаксична перевірка конфіга
ruby -c config/puma.rb

# 2. Стиль (RuboCop)
bundle exec rubocop config/puma.rb

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

# 4. RSpec для middleware
bundle exec rspec spec/middleware/mark_web3_requests_as_io_bound_spec.rb
# Очікується: 10 examples, 0 failures
```
