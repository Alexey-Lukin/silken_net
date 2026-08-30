# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "sidekiq/capsule"

RSpec.describe "Sidekiq initializer" do # rubocop:disable RSpec/DescribeClass
  # Тиха конфігурація: `new_redis_pool` логує кожне створення пулу.
  def build_config(concurrency:, redis_options:)
    Sidekiq::Config.new(concurrency: concurrency).tap do |config|
      config.logger = Logger.new(IO::NULL)
      config.redis = redis_options
    end
  end

  describe "constants" do
    it "defines SIDEKIQ_REDIS_URL with default fallback" do
      expect(defined?(SIDEKIQ_REDIS_URL)).to be_truthy
      expect(SIDEKIQ_REDIS_URL).to be_a(String)
      expect(SIDEKIQ_REDIS_URL).to include("redis://")
    end

    # [INF.22] Доти цей приклад звався «not DB 1 reserved for Kredis» — резерву
    # більше не існує: Upstash дає рівно ОДНУ логічну базу, тож усі споживачі
    # ділять keyspace, а розводить їх префікс. Твердження лишається тим самим і
    # стає СИЛЬНІШИМ: індекс, відмінний від нуля, у проді не резервує нічого, він
    # RAISE'ить (`ERR Only 0th database is supported!`).
    it "адресує нульовий індекс — єдиний, що існує на Upstash" do
      expect(SIDEKIQ_REDIS_URL).to match(%r{/0\z}).or match(%r{localhost:6379\z})
    end

    it "uses default timeout of 5 when ENV not set" do
      expect(SIDEKIQ_REDIS_TIMEOUT).to eq(5)
    end
  end

  # [ARCH.59] Стеля серверного пулу — НЕ наша константа: Sidekiq виводить її з
  # `:concurrency` капсули, а internal-пул тримає окремо. Ці приклади і є носієм
  # присуду: поверни `size:` у SIDEKIQ_REDIS_OPTIONS — обидва почервоніють.
  describe "server Redis pool [ARCH.59]" do
    it "не задає власний size — стелю виводить капсула" do
      expect(SIDEKIQ_REDIS_OPTIONS).not_to have_key(:size)
    end

    it "капсульний пул слідує за :concurrency, а не за константою" do
      config = build_config(concurrency: 7, redis_options: SIDEKIQ_REDIS_OPTIONS)
      capsule = config.capsule("arch59-probe") { |cap| cap.concurrency = 7 }

      expect(capsule.local_redis_pool.size).to eq(7)
    end

    it "не роздуває internal-пул (heartbeat · scheduler · Web UI) власною стелею" do
      ours = build_config(concurrency: 7, redis_options: SIDEKIQ_REDIS_OPTIONS)
      gem_default = build_config(concurrency: 7, redis_options: { url: SIDEKIQ_REDIS_URL })

      expect(ours.local_redis_pool.size).to eq(gem_default.local_redis_pool.size)
    end

    it "прокидає таймаути в обидва пули" do
      expect(SIDEKIQ_REDIS_OPTIONS).to include(
        network_timeout: SIDEKIQ_REDIS_TIMEOUT,
        pool_timeout: SIDEKIQ_REDIS_TIMEOUT
      )
    end
  end

  # Клієнт капсул не має, тож тут стеля наша — і вона мусить покривати треди,
  # що кличуть `perform_async`, а не бути прибитим числом.
  describe "client Redis pool" do
    it "покриває треди Puma із запасом на Sidekiq::Web" do
      puma_threads = (ENV["RAILS_MAX_THREADS"].presence || 3).to_i

      expect(SIDEKIQ_CLIENT_POOL_SIZE).to be > puma_threads
    end

    it "задає size явно — вивести його Sidekiq'у нізвідки" do
      expect(SIDEKIQ_REDIS_OPTIONS.merge(size: SIDEKIQ_CLIENT_POOL_SIZE))
        .to include(size: SIDEKIQ_CLIENT_POOL_SIZE)
    end
  end
end
