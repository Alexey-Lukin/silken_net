# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../lib/turbo_stream_inventory"

# Юніт-покриття AST-екстрактора, що живить гейт осі скоупу
# (`spec/security/turbo_stream_scope_spec.rb`, канон `04_04 §8.1`).
#
# 🔴 Чому синтетичні фікстури, а не лише прогін по `app/`: захисні гілки
# класифікатора (`bare_string`, `bare_symbol`, `implicit_self`, битий синтаксис)
# реальним кодом НЕ проходяться саме тому, що кодова база чиста — тобто
# найважливіші для гейта класи були б непокриті рівно доти, доки хтось не
# внесе дефект. Near-miss'и тут же стережуть від протилежної помилки:
# екстрактор не сміє рахувати те, що не є API гема.
RSpec.describe TurboStreamInventory do
  # Реальний набір гема передається гейтом; тут — мінімальний, достатній набір.
  let(:methods) { %w[broadcast_replace_to broadcast_refresh_later_to broadcast_refresh broadcast_remove_to] }

  def with_source(code)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "probe.rb")
      File.write(path, code)
      yield path
    end
  end

  def subscription_kind(expr)
    with_source("class P\n  def t\n    turbo_stream_from #{expr}\n  end\nend\n") do |path|
      described_class.subscriptions([ path ]).first
    end
  end

  describe "classification of the subscription's first argument" do
    it "flags a bare global name — the class that shipped the SEC.25 leak" do
      site = subscription_kind('"telemetry_stream"')

      expect(site.arg_kind).to eq(:bare_string)
      expect(site.arg_pattern).to eq("telemetry_stream")
    end

    it "flags a bare symbol the same way" do
      expect(subscription_kind(":global_events").arg_kind).to eq(:bare_symbol)
    end

    it "recognises an org-scoped interpolation" do
      # rubocop:disable Lint/InterpolationCheck -- це РЯДОК-ФІКСТУРА вихідного коду
      # під розбір Ripper-ом; `#{...}` мусить лишитись літеральним.
      site = subscription_kind('"telemetry_stream_org_#{@organization.id}"')
      # rubocop:enable Lint/InterpolationCheck

      expect(site.arg_kind).to eq(:scoped_string)
      expect(site.arg_pattern).to include("_org_")
    end

    it "separates interpolation WITHOUT an org token (safe only transitively)" do
      # rubocop:disable Lint/InterpolationCheck -- рядок-фікстура вихідного коду, див. вище.
      expect(subscription_kind('"ota_channel_#{@gateway.uid}"').arg_kind).to eq(:unscoped_interpolation)
      # rubocop:enable Lint/InterpolationCheck
    end

    it "treats an ivar as a record reference" do
      expect(subscription_kind("@wallet, :transactions").arg_kind).to eq(:record_ref)
    end

    # Благословенний дім імен. Клас читається з ІМЕНІ МЕТОДУ, не з форми
    # аргументу — інакше два різні обовʼязки доказу злились би в `:indirect`.
    it "reads the proof class off the blessed home's METHOD name" do
      expect(subscription_kind("TurboStreams::Name.org(:telemetry, @organization)").arg_kind)
        .to eq(:derived_org)
      expect(subscription_kind("TurboStreams::Name.gateway_ota(@gateway)").arg_kind)
        .to eq(:derived_gateway)
    end

    # 🔴 Форма, що вкусила при написанні цього класу, і третя така в цьому файлі
    # (сиблінги: безаргументний `:vcall`, `var_ref` ≠ запис). Коли ВКЛАДЕНИЙ
    # виклик іде без дужок, він зʼїдає список аргументів собі, тож вузол
    # аргументів зовнішнього виклику приходить голим масивом — і давав `:absent`,
    # тобто «аргументу немає» там, де він явно є.
    it "sees the blessed call written WITHOUT parens (the nested-command shape)" do
      expect(subscription_kind("TurboStreams::Name.org :telemetry, @organization").arg_kind)
        .to eq(:derived_org)
    end

    it "does not bless a look-alike receiver" do
      expect(subscription_kind("Other::Name.org(:telemetry, @organization)").arg_kind).to eq(:indirect)
      expect(subscription_kind("TurboStreams::Other.org(:telemetry, @organization)").arg_kind).to eq(:indirect)
    end

    # `const_tokens` сплощує все піддерево ресівера, тож без перевірки самої ФОРМИ
    # вузла ланцюжок через проміжний виклик давав ті самі токени й благословлявся,
    # хоч значення повертає щось інше. Знайдено adversarial-проходом, Ripper'ом.
    # Обидві форми обходу, і другу знайдено ЛИШЕ четвертим adversarial-раундом:
    # перша редакція перевіряла тільки ЗОВНІШНІЙ вузол ресівера, тож виклик,
    # засунутий у ЛІВУ ногу const-шляху, проходив — гейт недо-імплементував
    # власний коментар рівно через добу після того, як цей клас був headline'ом.
    it "does not bless the blessed constant reached through an intermediate call" do
      expect(subscription_kind("TurboStreams::Name.dup.org(:telemetry, @organization)").arg_kind)
        .to eq(:indirect)
      expect(subscription_kind("TurboStreams.dup::Name.org(:telemetry, @organization)").arg_kind)
        .to eq(:indirect)
    end

    it "blesses the fully-qualified receiver" do
      expect(subscription_kind("::TurboStreams::Name.gateway_ota(gateway)").arg_kind)
        .to eq(:derived_gateway)
    end

    it "treats an array literal as a record reference" do
      expect(subscription_kind("[ @cluster, :alerts ]").arg_kind).to eq(:record_array)
    end

    # 🔴 Пастка, знайдена заміром проти ручного підрахунку: локальна змінна теж
    # `var_ref`, і маркувати її записом означало б ПЕРЕОЦІНИТИ безпеку сайту —
    # найгірший напрямок помилки для диспетчера обовʼязку доказу.
    it "does NOT mistake a local variable holding a string for a record" do
      site = with_source(<<~RUBY) { |p| described_class.subscriptions([ p ]).first }
        class P
          def t
            stream = "telemetry_stream_org_1"
            turbo_stream_from stream
          end
        end
      RUBY

      expect(site.arg_kind).to eq(:indirect)
    end
  end

  describe "producer collection" do
    it "sees a receiver-less instance call (Turbo::Broadcastable is mixed into every model)" do
      sites = with_source(<<~RUBY) { |p| described_class.producers([ p ], methods: methods) }
        class P
          def go
            broadcast_refresh
          end
        end
      RUBY

      expect(sites.map(&:arg_kind)).to eq([ :implicit_self ])
    end

    it "collects the single-line form (the regex extractor's measured blind spot)" do
      sites = with_source(<<~RUBY) { |p| described_class.producers([ p ], methods: methods) }
        class P
          def go
            Turbo::StreamsChannel.broadcast_remove_to(stream, target: "x")
          end
        end
      RUBY

      expect(sites.size).to eq(1)
    end

    it "counts a parenthesised receiver call exactly ONCE" do
      sites = with_source(<<~RUBY) { |p| described_class.producers([ p ], methods: methods) }
        class P
          def go
            Turbo::StreamsChannel.broadcast_replace_to("a_org_1", target: "x")
          end
        end
      RUBY

      expect(sites.size).to eq(1)
    end

    # Near-miss: власні приватні хелпери застосунку мають той самий префікс, але
    # до API гема не належать. Саме на цьому завалився патерн `broadcast_\w+`.
    it "ignores an app-private helper that merely shares the prefix" do
      sites = with_source(<<~RUBY) { |p| described_class.producers([ p ], methods: methods) }
        class P
          def go
            broadcast_ota_progress(gateway, 42)
          end
        end
      RUBY

      expect(sites).to be_empty
    end

    it "ignores a broadcast name that appears only in a comment" do
      sites = with_source(<<~RUBY) { |p| described_class.producers([ p ], methods: methods) }
        class P
          # broadcast_refresh_later_to("a_org_1") — лише згадка в коментарі
          def go = nil
        end
      RUBY

      expect(sites).to be_empty
    end
  end

  describe "shapes that are NOT a named call (guards that look defensive but are reachable)" do
    it "ignores a proc-call `obj.()` — Ripper puts a bare symbol where the name would be" do
      sites = with_source(<<~RUBY) { |p| described_class.producers([ p ], methods: methods) }
        class P
          def go
            handler.("x")
          end
        end
      RUBY

      expect(sites).to be_empty
    end

    it "handles an empty argument list (`foo()`) without mistaking it for an argument" do
      sites = with_source(<<~RUBY) { |p| described_class.producers([ p ], methods: methods) }
        class P
          def go
            broadcast_refresh()
          end
        end
      RUBY

      expect(sites.map(&:arg_kind)).to eq([ :implicit_self ])
    end

    it "classifies a method call in the first argument as indirect, never as a record" do
      site = with_source(<<~RUBY) { |p| described_class.subscriptions([ p ]).first }
        class P
          def t
            turbo_stream_from stream_name_for(user)
          end
        end
      RUBY

      expect(site.arg_kind).to eq(:indirect)
    end
  end

  describe "robustness" do
    it "skips a syntactically broken file instead of raising" do
      sites = with_source("class Broken\n  def go(\n") { |p| described_class.producers([ p ], methods: methods) }

      expect(sites).to be_empty
    end

    it "returns an empty inventory for an empty path list" do
      expect(described_class.subscriptions([])).to be_empty
    end
  end
end
