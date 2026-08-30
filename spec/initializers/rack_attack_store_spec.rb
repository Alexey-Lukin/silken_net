# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [INF.22] Носій прод-гілки cache-store'у Rack::Attack.
#
# 🔴 Чому цей файл існує окремо: до 2026-08-30 на цю гілку не стояло НІЧОГО.
# `rack_attack_spec.rb` пінить лише те, що в test-середовищі береться MemoryStore,
# тобто рівно ту гілку, яка в проді не виконується. Наслідок був виміряний, не
# теоретичний: store адресував `/2`, Upstash має рівно одну логічну базу, і
# `write`/`read`/`increment` тихо віддавали `nil` — throttle не рахував, поріг
# fail2ban не досягався, лог лишався порожнім. Дефект прожив стільки, скільки
# прожила відсутність цієї спеки.
#
# ⚠️ Оголошена стеля: прод-гілку не можна виконати під RSpec (`Rails.env.test?`
# бере MemoryStore, а CI не має Upstash — валкі-сервіс має всі 16 баз, тож
# відтворити відмову інтеграційно неможливо ЗА ПОБУДОВОЮ). Тому вісь ФОРМИ
# судиться статично — читанням самого ініціалізатора, — а вісь ПОВЕДІНКИ
# поведінково, через винесену константу `RACK_ATTACK_STORE_ERROR_HANDLER`.
# Гейт судить наявність механізму, ніколи його доречність у бою.
RSpec.describe "Rack::Attack cache store [INF.22]" do # rubocop:disable RSpec/DescribeClass
  let(:source) { Rails.root.join("config/initializers/rack_attack.rb").read }

  describe "форма прод-гілки (статично)" do
    it "не адресує ненульовий індекс Redis-бази — на Upstash його не існує" do
      # Ловить і колишню форму (`uri.path = "/2"`), і будь-яке повернення до неї
      # через URL-суфікс. Нульовий індекс легальний: він єдиний, що існує.
      offenders = source.lines.grep(%r{(uri\.path\s*=|:6379)/[1-9]})

      expect(offenders).to be_empty,
        "Прод-гілка адресує ненульову Redis-базу — Upstash віддасть " \
        "`ERR Only 0th database is supported!`, а RedisCacheStore проковтне це в nil:\n" \
        "#{offenders.join}"
    end

    it "розводить ключі namespace'ом, бо база тепер спільна" do
      expect(source).to match(/namespace:\s*["']rack-attack["']/)
    end

    it "дротує error_handler у сам store, а не лише оголошує його" do
      expect(source).to match(/error_handler:\s*RACK_ATTACK_STORE_ERROR_HANDLER/)
    end
  end

  describe "поведінка error_handler (те, що робить тишу гучною)" do
    let(:exception) { Redis::CommandError.new("ERR Only 0th database is supported! Selected DB: 2") }

    it "інкрементує лічильник, який читає sn-alert-rate-limit-store-errors" do
      expect {
        RACK_ATTACK_STORE_ERROR_HANDLER.call(method: :increment, returning: nil, exception: exception)
      }.to change(SilkenNet::Metrics::RATE_LIMIT_STORE_ERRORS_TOTAL, :get).by(1)
    end

    it "логує ERROR, який каже, що щита НЕМА — а не що він деградував" do
      allow(Rails.logger).to receive(:error)

      RACK_ATTACK_STORE_ERROR_HANDLER.call(method: :increment, returning: nil, exception: exception)

      expect(Rails.logger).to have_received(:error).with(
        a_string_including("RATE LIMITING IS NOT ENFORCED")
      )
    end

    it "несе в повідомленні і операцію, і причину — інакше з логу не діагностувати" do
      allow(Rails.logger).to receive(:error)

      RACK_ATTACK_STORE_ERROR_HANDLER.call(method: :read, returning: nil, exception: exception)

      expect(Rails.logger).to have_received(:error).with(
        a_string_including("read").and(a_string_including("Only 0th database is supported"))
      )
    end
  end
end
