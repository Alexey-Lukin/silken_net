# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "yaml"

# =============================================================================
# ⚖️ ЧЕРГУ ActiveJob-ДЖОБИ ОБИРАЄМО МИ, А НЕ ДЕФОЛТ ГЕМА
# =============================================================================
# Присуд ARCH.60/ARCH.52, 2026-08-23. Наші Sidekiq-воркери оголошують чергу самі
# (`sidekiq_options queue:`), тож CLAUDE.md §5 «не міняй чергу без обґрунтування»
# їх стереже. Але ActiveJob-джоби приходять із гемів БЕЗ `queue_as`, і тоді
# `ActiveJob::Base.default_queue_name` кладе їх у `default`(5) — п'ятою з дев'яти
# у strict-ланцюгу, тобто ПОЗАДУ `uplink`/`alerts`/`critical`/`downlink`.
#
# 🔴 Чому це не гігієна. Вимір 2026-08-23 дав чотирнадцять ActiveJob-нащадків, і
# ВСІ чотирнадцять сиділи в `default` — жодного ми не обирали. Серед них був
# єдиний формальний лист про critical-тривогу: `AlertNotificationWorker` судить
# про критичність у `alerts`(2), Telegram-фан-аут теж `alerts`(2), а лист падав
# за `downlink`(4) — тобто за чанками OTA-кампанії. Ланцюг ламався на тому кроці,
# який єдиний доходить до людини.
#
# ⚠️ Що цей гейт НЕ обіцяє (оголошена стеля). Він судить ПРИЗНАЧЕННЯ черги, а не
# виживання під насиченням: при безперервному `uplink`(1) strict не дренує НІЧОГО
# нижчого, і жодне призначення від цього не рятує. Лік того класу вже
# ратифіковано окремо й він інший — виділений процес (`06_08 §2.5`, ARCH.52).
# Тут закривається реалістичніший випадок: backlog OTA-кампанії в `downlink`(4).
#
# 🔒 Порожня множина тут була б хибним зеленим, тому популяція пінується окремо
# (`ssot-maintenance` §Guard-craft: пін на порожній множині зелений завжди).
#
# Дім доктрини черг — `04_02 §11`; сам strict-порядок — `config/sidekiq.yml`.
# Реєстр — ОДИН рядок на клас, і він є ЗАПИСОМ ПРИСУДУ, а не описом стану.
# Новий ActiveJob-нащадок (свій чи з гема) валить приклад доти, доки хтось не
# напише сюди рядок — тобто доки чергу не ОБЕРУТЬ.
DECLARED_JOB_QUEUES = {
  # --- наші ---
  "ApplicationJob"                     => "default",

  # --- пошта: черга резолвиться ПЕР-МЕЙЛЕРНО, тому судиться нижче ---
  "ActionMailer::MailDeliveryJob"      => :per_mailer,

  # --- Turbo-броадкасти: UI-редрав ---
  # ⚖️ Лишаються на `default` СВІДОМО: застарілий екран оборотний
  # перезавантаженням, а підняття редраву над `downlink`(4) поставило б
  # перемальовку попереду наказу актуатору. Ефемерний канал пріоритету не несе.
  # ⊕ `BroadcastJob` живить `broadcast_render_later_to`, якого в дереві нуль —
  # запис лишається, бо клас завантажений і мусить мати оголошену чергу.
  "Turbo::Streams::ActionBroadcastJob" => "default",
  "Turbo::Streams::BroadcastStreamJob" => "default",
  "Turbo::Streams::BroadcastJob"       => "default",

  # --- ActiveStorage: фонові справи вкладень (фото обслуговування, лого) ---
  # `default` правильний: це не safety і не гроші. `AnalyzeJob` знімає метадані,
  # `TransformJob`/`PreviewImageJob` роблять варіанти, `PurgeJob` прибирає.
  "ActiveStorage::BaseJob"             => "default",
  "ActiveStorage::AnalyzeJob"          => "default",
  "ActiveStorage::MirrorJob"           => "default",
  "ActiveStorage::PreviewImageJob"     => "default",
  "ActiveStorage::PurgeJob"            => "default",
  "ActiveStorage::TransformJob"        => "default",

  # --- завантажені, але БЕЗ ActiveJob-пускача (виміряно 2026-08-23) ---
  # Записані саме як фантоми, щоб наступний прохід не «лагодив» їхнє
  # голодування: `SolidCable::TrimJob` кличеться `perform_now` інлайн у
  # listener-адаптері; `SolidCache::ExpiryJob` недосяжний, бо `expiry_method`
  # за замовчуванням `:thread`, а ми його не перекриваємо; `Sentry::SendEventJob`
  # не має жодного викликача в `sentry-ruby`/`sentry-rails` — Sentry шле
  # власним пулом тредів (`background_worker_threads`).
  "SolidCable::TrimJob"                => "default",
  "SolidCache::ExpiryJob"              => "default",
  "Sentry::SendEventJob"               => "default"
}.freeze

# `deliver_later_queue_name` — `class_attribute` на `ActionMailer::Base`, тож
# успадковується; `nil` означає «падай у `ActiveJob::Base.default_queue_name`».
DECLARED_MAILER_QUEUES = {
  "ApplicationMailer" => nil,     # абстрактний предок — власної пошти не шле
  "AlertMailer"       => :alerts, # ⚖️ ARCH.60: лист про critical їде чергою свого рішення
  "PasswordMailer"    => nil      # ⚖️ свідомо `default`: UX, не безпека — над слешинг не піднімаємо
}.freeze

RSpec.describe "ActiveJob queue assignment is declared, never inherited" do # rubocop:disable RSpec/DescribeClass
  before { Rails.application.eager_load! }

  let(:live_jobs)    { ActiveJob::Base.descendants.map(&:name).compact }
  let(:live_mailers) { ActionMailer::Base.descendants.map(&:name).compact }

  let(:sidekiq_queues) do
    YAML.load_file(Rails.root.join("config/sidekiq.yml"), permitted_classes: [ Symbol ], aliases: true)
        .fetch(:queues)
        .map(&:to_s)
  end

  # 🔒 Ліхтар: усі приклади нижче ітерують ці дві множини, тож порожня зробила б
  # їх зеленими без жодної перевірки.
  it "sees a non-empty population of jobs and mailers" do
    expect(live_jobs.size).to be >= 10
    expect(live_mailers.size).to be >= 2
  end

  it "has a declared queue for every loaded ActiveJob descendant" do
    undeclared = live_jobs - DECLARED_JOB_QUEUES.keys

    expect(undeclared).to be_empty, <<~MSG
      ActiveJob-нащадок без оголошеної черги: #{undeclared.join(', ')}.
      Без `queue_as` він тихо падає в `default`(5) — позаду uplink/alerts/critical/downlink.
      Обери чергу свідомо й додай рядок у DECLARED_JOB_QUEUES (#{__FILE__}),
      назвавши ПІДСТАВУ. Доктрина черг — `04_02 §11`.
    MSG
  end

  it "carries no stale registry entries" do
    stale = DECLARED_JOB_QUEUES.keys - live_jobs

    expect(stale).to be_empty, <<~MSG
      Реєстр називає класи, яких у дереві вже немає: #{stale.join(', ')}.
      Прибери рядки — інакше реєстр стверджує присуд про неіснуючий предмет.
    MSG
  end

  it "resolves each declared job to the queue it declares" do
    drift = DECLARED_JOB_QUEUES.filter_map do |name, declared|
      next if declared == :per_mailer

      actual = name.constantize.new.queue_name
      "#{name}: оголошено #{declared.inspect}, фактично #{actual.inspect}" if actual != declared
    end

    expect(drift).to be_empty, "Черга розійшлася з оголошеною:\n#{drift.join("\n")}"
  end

  it "resolves each mailer to the queue it declares" do
    drift = DECLARED_MAILER_QUEUES.filter_map do |name, declared|
      actual = name.constantize.deliver_later_queue_name
      "#{name}: оголошено #{declared.inspect}, фактично #{actual.inspect}" if actual != declared
    end

    expect(drift).to be_empty, "`deliver_later_queue_name` розійшовся з оголошеним:\n#{drift.join("\n")}"
  end

  it "has a declaration for every loaded mailer" do
    undeclared = live_mailers - DECLARED_MAILER_QUEUES.keys

    expect(undeclared).to be_empty, <<~MSG
      Мейлер без оголошеної черги: #{undeclared.join(', ')}.
      `nil` теж легальне оголошення (= `default`), але воно мусить бути ЗАПИСАНЕ
      з підставою: `default`(5) стоїть позаду `downlink`(4), тобто позаду OTA-чанків.
    MSG
  end

  # 🔴 Найгостріший режим відмови всього класу: черга, якої немає в `sidekiq.yml`,
  # не слухається ЖОДНИМ процесом — джоба лягає в Redis і не виконується ніколи,
  # мовчки. Саме сюди веде наївне «постав пошті власну чергу `mailers`»: це і є
  # framework-дефолт `ActionMailer::Base` до `load_defaults 6.1`.
  it "declares only queues that a Sidekiq process actually listens on" do
    declared = (
      DECLARED_JOB_QUEUES.values.reject { |v| v == :per_mailer } +
      DECLARED_MAILER_QUEUES.values.compact.map(&:to_s)
    ).uniq

    orphans = declared - sidekiq_queues

    expect(orphans).to be_empty, <<~MSG
      Оголошено чергу, якої немає в `config/sidekiq.yml`: #{orphans.join(', ')}.
      Жоден процес її не слухає — джоби осядуть у Redis і не виконаються НІКОЛИ,
      без помилки. Або додай чергу в strict-ланцюг, або обери наявну.
    MSG
  end
end
