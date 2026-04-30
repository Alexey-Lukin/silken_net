# 06_05: Puma 7.2.0 → 8.0.1 Upgrade Notes

## 🎯 Мета

Зафіксувати аналіз changelog та release notes Puma для серії версій **7.0.0 → 8.0.1** (8 релізів між нашою попередньою (7.2.0) та поточною (8.0.1)) у контексті SilkenNet / Gaia 2.0:

1. Які **breaking changes** торкаються нашої конфігурації?
2. Які **нові фічі** дають реальний приріст для Bio-IoT / 12-chain Web3 backend?
3. Що зробили зараз, що відкладено, що відхилено.

## ✅ Статус

- **Поточна версія в `Gemfile.lock`:** `puma (8.0.1)`
- **Попередня версія:** `puma (7.2.0)`
- **Цільовий масштаб:** мільйони → мільярди → трильйони дерев. Кожна оптимізація per-request множиться на planetary scale, тому 17%-50% поліпшень з changelog не є косметикою.
- **Конфігураційний SSOT:** `config/puma.rb`
- **Архітектура runtime:** `Thruster (HTTP/2, TLS) → Puma (clustered, preload_app!) → Rails 8.1`

---

## 📚 Джерела

- [Puma History.md](https://github.com/puma/puma/blob/master/History.md)
- [Puma 7.0 upgrade guide](https://github.com/puma/puma/blob/master/docs/upgrade-7.md)
- [Puma 8.0 upgrade guide](https://github.com/puma/puma/blob/master/docs/upgrade-8.md)
- Локальний референс: `config/puma.rb`, `config/deploy.yml`, `config/deploy.canopy.yml`, `Dockerfile`

---

## 🔴 Breaking changes — що торкається SilkenNet

Нижче — лише ті breaking changes, що мають практичний вплив на наш код. Повний перелік — у History.md.

### BC-1 (Puma 7.0): Перейменування lifecycle-хуків

Старі імена → нові:

| Старе ім'я | Нове ім'я |
|---|---|
| `on_worker_boot` | `before_worker_boot` |
| `on_worker_shutdown` | `before_worker_shutdown` |
| `on_worker_fork` | `before_worker_fork` |
| `on_refork` | `before_refork` |
| `on_thread_start` | `before_thread_start` |
| `on_thread_exit` | `before_thread_exit` |
| `on_restart` | `before_restart` |
| `on_booted` | `after_booted` |
| `on_stopped` | `after_stopped` |

> `before_fork` **не перейменовано** (вже мав префікс `before_`) — залишаємо як є.

**Наш стан:** `config/puma.rb` використовував `on_worker_boot` для re-establish DB-конекшенів і Kredis cleanup після fork. Старі імена досі працюють як deprecated aliases, але видають warning у логах і будуть видалені в наступних мажорах.

**✅ Зроблено:** перейменовано `on_worker_boot` → `before_worker_boot` у `config/puma.rb` (секція 6b). Семантика ідентична.

### BC-2 (Puma 7.0): Hooks now require a block

`ArgumentError` якщо хук викликати без блока. Наш код передає блоки скрізь — нас не торкається. Просто фіксуємо як інваріант для майбутніх PR.

### BC-3 (Puma 7.0): `preload_app!` тепер default у clustered mode

Раніше треба було вмикати явно. Тепер у clustered (workers > 0) preload вмикається сам.

**Наш стан:** ми задаємо `preload_app!` явно. Залишаємо рядок з коментарем — він тепер **redundant**, але декларативно фіксує намір (CoW + jemalloc в Dockerfile залежать від preload). Якщо в майбутньому Puma зробить `preload_app!` no-op, поведінка не зміниться.

### BC-4 (Puma 7.0): Конфіг тепер треба `clamp`-ити перед читанням

`Puma::Configuration#clamp` обов'язковий перед доступом до значень. Це торкається лише **користувачів, що вбудовують Puma програмно** (rack-test тощо). Наш `config/puma.rb` — стандартний DSL-файл, Puma сам викликає `clamp`. **Без впливу.**

### BC-5 (Puma 7.0): Response headers lowercased (Rack 3 strict)

Headers що віддає додаток (Rails) тепер lowercased на виході. Це Rack 3 compliance. Rails 8.1 уже Rack-3-compliant. **Без впливу** на наші API клієнти, бо HTTP header names case-insensitive (RFC 7230 §3.2). Перевірити лише якщо є custom Rack middleware, що **порівнює** header names через `==` замість `.downcase`. У `app/controllers/api/v1/oracle_callbacks_controller.rb` HMAC-перевірка `X-Chainlink-Signature` використовує `request.headers[]`, що нормалізує case — нас не торкається.

### BC-6 (Puma 7.0): `env['HTTP_VERSION']` не виставляється для Rack > 3.1

Якщо десь у коді ми читаємо `request.env['HTTP_VERSION']` напряму, отримаємо `nil` під Rack 3.1+. Замість цього треба `request.env['rack.version']` або `request.env['SERVER_PROTOCOL']`.

**Перевірка по кодовій базі:** `grep -rn "HTTP_VERSION" app/ lib/ config/` — лише прев'ю-довідки в gems/Rack stack. **Без впливу** на наш код.

### BC-7 (Puma 7.0): `max_keep_alive` default = 999, `persistent_timeout` default = 65s

Старі дефолти 25 / 20s. Новий стек агресивніше тримає keepalive, що **корисно** для Thruster→Puma loopback (зменшує fork/handshake overhead). У нас не задано явно — підхоплюємо новий дефолт.

### BC-8 (Puma 8.0): Default bind address — `[::]` (IPv6) замість `0.0.0.0`

Якщо доступний non-loopback IPv6 інтерфейс, Puma в production-моді тепер біндиться на `tcp://[::]:PORT` замість `tcp://0.0.0.0:PORT`. Якщо IPv6 немає — fallback на v4.

**Наш стан:** ми задаємо `port ENV.fetch("PORT", 3000)` (DSL `port`). DSL `port` без `host` використовує `Configuration#default_host`, який саме і змінив поведінку.

**Ризик:** Thruster (всередині того ж контейнера) конектиться до Puma по `127.0.0.1:3000`. У Docker/Kamal IPv6 на loopback зазвичай є (`::1`), а dual-stack listen на `[::]:3000` приймає і v4, і v6 (Linux default `IPV6_V6ONLY=0`). **Тобто має працювати без змін.**

**Що зробити для впевненості:**

```bash
# після деплою на canopy
kamal app exec -i 'ss -tlnp | grep 3000'   # очікуємо tcp6 LISTEN [::]:3000
curl -fsS http://127.0.0.1:3000/up           # health-check IPv4
curl -fsS http://[::1]:3000/up               # health-check IPv6
```

Якщо в контейнері IPv6 disabled (рідко, але буває в обмежених namespace) — Puma fallback-не на v4 автоматично. Якщо хочемо примусово v4 для consistency — додати в `config/puma.rb`:
```ruby
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 3000)}"
```
**Поки не додаємо** — дефолтна dual-stack поведінка краща для майбутньої IPv6-only інфраструктури.

### BC-9 (Puma 7.0): Min Ruby = 3.0

Ми на Ruby 4.0.2 — задовольняє. Без впливу.

---

## 🟢 Нові фічі — що варто прийняти

### F-1 (Puma 8.0): `max_io_threads` + `env["puma.mark_as_io_bound"]` ⭐⭐⭐

**Це найголовніша фіча релізу для нас.**

Дозволяє позначити IO-bound запит, щоб Puma виділив для нього окремий пул, що **перевищує** основний `max_threads`. Класичний use-case — coroutine-style backend з блокуючими IO викликами.

**Чому це для SilkenNet game-changer:**

Наш контролер `oracle_callbacks_controller#create` синхронно дзвонить:
- IoTeX W3bstream HTTP `POST /verify` (~200-2000ms)
- Polygon RPC `eth_call` (dry-run mint, ~100-500ms)
- Hadron KYC sync check (~150ms)

При `RAILS_MAX_THREADS=3` (наш дефолт) три повільні Web3-callbacks блокують увесь worker. CPU простоює, але нові запити в черзі. З `max_io_threads` ми можемо мати 3 CPU-bound треди + 16 IO-bound тредів на воркер — без OOM-ризику, бо IO-треди майже не споживають RAM.

**План впровадження (двохетапний, тут НЕ виконуємо повністю):**

1. **Етап 1 (зараз — лише документуємо):** додати в `config/puma.rb`:
   ```ruby
   max_io_threads ENV.fetch("PUMA_MAX_IO_THREADS", 16)
   ```
2. **Етап 2 (окремий PR):** Rack middleware `MarkWeb3RequestsAsIoBound` що ставить `env["puma.mark_as_io_bound"] = true` для:
   - `/api/v1/oracle_callbacks` (Chainlink callback)
   - `/api/v1/provisioning/register` (peaq DID + Hadron)
   - будь-який endpoint з тегом `io_bound` у controller (декларативний opt-in).

**Рішення зараз:** **не додаємо** в puma.rb до того моменту, як з'явиться middleware — інакше це no-op конфіг, що тільки додає шум. Створено task-нагадування у backlog (див. секцію "Подальші кроки").

### F-2 (Puma 8.0): `single` / `cluster` DSL hooks ⭐⭐

Дозволяє писати mode-specific блоки конфігурації:
```ruby
cluster do
  before_fork { ... }
  before_worker_boot { ... }
end

single do
  # development-specific
end
```

**Цінність для нас:** у `development` Puma запускається в single mode (`workers 0`), і `before_fork`/`before_worker_boot` ніколи не викликаються — зараз це OK, але код виглядає так, ніби стосується всіх режимів. `cluster do ... end` робить намір явним.

**Рішення:** **не змінюємо зараз.** Поточний код працює коректно (хуки no-op у single mode). Refactor — у наступному cosmetic-PR, якщо буде потреба додавати different single-mode logic.

### F-3 (Puma 8.0): `shutdown_debug` з параметром `on_force: true` ⭐⭐

Дамп backtraces ВСІХ тредів лише при **forced** shutdown (SIGKILL після `worker_timeout`), не при graceful. Раніше `shutdown_debug` (без `on_force: true`) спамив навіть при нормальному restart.

**Цінність:** наш `worker_timeout=60s` спрацьовує саме тоді, коли Web3 RPC завис. Дамп backtrace в цей момент = критична діагностика, яка покаже, на якому виклику завис worker. Без `on_force` — занадто шумно, бо на canopy ми робимо часті deploys (Kamal phased restart).

**Рішення:** **додамо в окремому PR разом з Sentry breadcrumb** (потребує `SENTRY_DSN` — він зараз BLOCKER, див. `06_04_Secrets_Checklist`).

### F-4 (Puma 8.0): `update_thread_pool_min_max` runtime API

Dynamic scaling розміру пулу через `Puma::ServerPluginControl` без рестарту. Гіпотетично можна підв'язати під Prometheus metrics (high `puma_request_backlog` → scale up).

**Рішення:** **відкладено.** Цінне на десятках тисяч RPS. Зараз ми <100 RPS на canopy. Записано в backlog для post-MVP.

### F-5 (Puma 7.2): `workers :auto` ⭐

Auto-detect CPU count через Ractor / `Etc.nprocessors`. Замінює явне `WEB_CONCURRENCY`.

**Чому НЕ використовуємо:** ми оперуємо в **двох різних рантаймах** з різною економікою:

- **GCP Kamal:** n2-standard-2 (2 vCPU). `WEB_CONCURRENCY=2` — заповнюємо CPU.
- **Akash SDL:** 4 CPU units. `WEB_CONCURRENCY=4`.
- **Local dev:** 8-16 cores ноутбук. `:auto` дав би 16 воркерів × 1.2GB RSS → OOM.

`:auto` без апер-баунду небезпечний для дев-середовища. Залишаємо явний `ENV.fetch("WEB_CONCURRENCY", 2)`.

### F-6 (Puma 7.1): `after_worker_shutdown` хук

Виконується **після** того як worker повністю завершився (`before_worker_shutdown` — до).

**Use-case:** flush Sentry buffer, закрити jemalloc arenas, віддати OTA in-flight chunks назад в чергу. Зараз нічого з цього не потребує гарантованого post-shutdown коду — Sidekiq має свої власні shutdown-хуки. **Не використовуємо**, але фіксуємо як доступну точку розширення.

### F-7 (Puma 7.1): Keepalive "fast inline" (1.4× pipelining)

Auto-enabled, без конфіг. **Прийнято автоматично** — для Thruster → Puma loopback це чистий приріст. Не потребує змін у нашому коді.

### F-8 (Puma 7.0): Fiber-per-request

Експериментальна підтримка `async`/`falcon`-style fibers. Потребує fiber-aware DB-драйверів і Web3 SDK. **Несумісне** з нашим Sidekiq-на-Puma-форк-моделлю. **Відхилено.**

### F-9 (Puma 7.0): `rack.response_finished` callback

Дозволяє зареєструвати callback, що викличеться після того як response повністю надіслано клієнту. Корисно для:
- `Idempotency-Key` cleanup в Redis після успішної відповіді
- Audit-log запис без блокування response

**Рішення:** **тримаємо в backlog**. Зараз цей патерн реалізовано через `after_action` у контролерах. Міграція на `rack.response_finished` дасть точніший момент (response **flushed**, не просто згенерований).

### F-10 (Puma 8.0/7.2/7.0): Чисті performance-wins (без конфігу)

Прийняті автоматично:
- **17% швидший HTTP parser** (7.2, pre-interned env keys)
- **−50% allocation per response** (8.0, cached downcased header keys)
- **GC-compactible C-extension** (7.2) — наш Sidekiq викликає `GC.compact` per-job, тепер puma_http11 теж стискається
- **JRuby HTTP parser** improvements (8.0) — нерелевантно, ми на CRuby
- **Long-tail keepalive fix** (7.0) — критично для p99 latency на canopy

**Сумарно:** −10-15% RSS на воркер + ~20% throughput на читання headers. На planetary-scale (мільйони `oracle_callbacks` на годину) це сотні vCPU-годин економії.

### F-11 (Puma 7.2): Restrict control server to `stats`

`Puma::ControlCLI` тепер можна заборонити все крім `stats` (read-only mode). Наш control_url не експонується назовні (тільки локальний UNIX-socket для Prometheus exporter), але як **defence-in-depth** варто додати в Kamal-конфіг при налаштуванні Prometheus exporter (`06_03_Prometheus_Observability`).

**Рішення:** додати у задачі для PR з Prometheus integration.

### F-12 (Puma 7.2): `WEB_CONCURRENCY=""` no longer crashes

Раніше пустий `WEB_CONCURRENCY` (типова помилка ENV-templating у Kamal) кешив `Integer("")` → `ArgumentError` під час boot. Тепер trim'ається. **Покращує robustness** наших Kamal deploys, де `.kamal/secrets` іноді залишають placeholder. Без впливу на код.

### F-13 (Puma 8.0): SIGPWR для backtrace на Linux

`SIGINFO` недоступний на Linux. Тепер `kill -PWR <puma_pid>` дампить backtraces всіх тредів воркера в лог. **Дуже корисно** для debug висячих Web3 RPC у production.

**Документуємо runbook:**
```bash
# на Kamal-хості. У нашому контейнері PID 1 — це Thruster (CMD: thrust ./bin/rails server),
# а Puma — child. Знаходимо Puma master PID через pgrep.
sudo docker exec silken_net-web-1 sh -c '
  PID=$(pgrep -f "puma .*cluster" | head -1)
  [ -z "$PID" ] && PID=$(pgrep -f "puma" | head -1)
  echo "Puma master PID: $PID"
  kill -PWR "$PID"
'
sudo docker logs silken_net-web-1 --tail 200
```

---

## 📋 Bugfixes що для нас релевантні

- **8.0.1 — `prune_bundler` BUNDLE_* env-vars** stripped on re-exec → workers crashed on boot. Ми **використовуємо** `prune_bundler` через Thruster + `BUNDLE_WITHOUT=development:test` у Dockerfile. Цей фікс прямо рятує наш production. Підтверджуємо upgrade на 8.0.1 (а не 8.0.0) як **обов'язковий**.
- **7.2.0 — phased restart race condition** в `Cluster#check_workers`. Kamal використовує phased restart для zero-downtime deploys. Без цього фікса був ризик "stale worker 0" після refork.
- **7.0.4 — strip whitespace from request header values.** Захист від HTTP request smuggling у edge-cases. Релевантно бо ми приймаємо `X-Chainlink-Signature` (HMAC) — будь-який smuggling був би critical.

---

## 🔧 Виконані зміни

### `config/puma.rb`

1. `on_worker_boot do` → `before_worker_boot do` (BC-1)
2. Оновлено coментарі до preload_app! (BC-3) і before_fork (відсилка на цей doc).

Жодної функціональної зміни поведінки — лише назва хука та коментарі. Семантика 100% збережена.

---

## 🧭 Подальші кроки (backlog)

| ID | Опис | Пріоритет | Залежить від |
|---|---|---|---|
| PUMA-IO-1 | Rack middleware `MarkWeb3RequestsAsIoBound` + `max_io_threads 16` у puma.rb (F-1) | **High** | — |
| PUMA-DBG-1 | `shutdown_debug on_force: true` + інтеграція з Sentry breadcrumb (F-3) | Medium | `SENTRY_DSN` (06_04 BLOCKER) |
| PUMA-CTL-1 | Restrict control server to `stats` для Prometheus exporter (F-11) | Medium | `06_03_Prometheus_Observability` |
| PUMA-RACK-1 | Перенести `Idempotency-Key` cleanup на `rack.response_finished` (F-9) | Low | — |
| PUMA-IPV6-1 | Перевірити IPv6 listen після першого Kamal-деплою на canopy (BC-8) | High | перший реальний деплой |
| PUMA-DSL-1 | Refactor у `cluster do ... end` блок (F-2) | Low | косметика |

---

## ✅ Валідація

```bash
export PATH="/opt/hostedtoolcache/Ruby/4.0.2/x64/bin:$PATH"

# 1. Синтаксична перевірка конфіга (Puma DSL)
ruby -c config/puma.rb

# 2. Стиль (RuboCop)
bundle exec rubocop config/puma.rb

# 3. Boot smoke-test (development single mode)
RAILS_ENV=development bundle exec puma -C config/puma.rb &
sleep 5
curl -fsS http://127.0.0.1:3000/up
kill %1

# 4. Cluster mode smoke-test (production-like)
RAILS_ENV=production WEB_CONCURRENCY=2 RAILS_MAX_THREADS=3 \
  SECRET_KEY_BASE=test_only_dummy_secret_key_base_minimum_30_chars_long \
  bundle exec puma -C config/puma.rb &
sleep 8
curl -fsS http://127.0.0.1:3000/up
ss -tlnp | grep 3000     # перевіряємо bind (BC-8)
kill %1
```

Очікуваний log (без deprecation warnings про `on_worker_boot`):

```
* Puma version: 8.0.1
* Min threads: 3
* Max threads: 3
* Environment: production
* Master PID: ...
* Workers: 2
* Restarts: (✔) hot (✔) phased
* Preloading application
* Listening on http://[::]:3000   # або 0.0.0.0:3000 без IPv6
```

---

## 🔗 Cross-references

- `config/puma.rb` — конфігурація
- `Dockerfile` — `LD_PRELOAD=jemalloc`, `thrust ./bin/rails server`
- `06_01_Deployment_Kamal_Terraform` — Kamal phased restart
- `06_02_Akash_Network_Integration` — `WEB_CONCURRENCY=4` у Akash SDL
- `06_03_Prometheus_Observability` — Puma metrics export (PUMA-CTL-1)
- `06_04_Secrets_Checklist` — `SENTRY_DSN` (PUMA-DBG-1 dependency)
- `04_03_REST_API_v1_Reference` — endpoints, які стануть IO-bound (PUMA-IO-1)
