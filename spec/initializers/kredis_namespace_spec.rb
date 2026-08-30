# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [INF.22] Носій ОДНОГО рядка — `Kredis.global_namespace` у
# `config/initializers/kredis.rb`.
#
# 🔴 Чому рядок вартий власної спеки: його зникнення не червонить НІЧОГО, а ціна
# асиметрична. Гем гілкується на наявність namespace —
#   `if Kredis.namespace` → `keys("<ns>:*")` + `del`
#   `else`                → `connection.flushdb`
# — і `Kredis.clear_all` біжить у `spec/rails_helper.rb` перед КОЖНИМ прикладом.
# Оскільки Upstash має одну логічну базу, dev/test/prod ділять keyspace із
# чергами Sidekiq. Тобто зняття рядка дає: сюїта лишається ЗЕЛЕНОЮ (flushdb їй не
# шкодить), а кожен приклад мовчки спорожняє спільну базу — dev-черги Sidekiq і
# ключ-власник TEST.8 разом із ними, що повертає гард конкуренції в режим
# «вимикає сам себе», який уже одного разу вимірювали й лагодили.
#
# ⚠️ Асиметрія, яку ця спека вирівнює: namespace сусіда (Rack::Attack) дістав
# носія з мутацією ×4 того ж дня, а цей — ні. Знайшов адверсарний прохід, не гейт.
RSpec.describe "Kredis key namespace [INF.22]" do # rubocop:disable RSpec/DescribeClass
  describe "поведінка" do
    it "має непорожній global_namespace — інакше clear_all стає FLUSHDB" do
      expect(Kredis.global_namespace).to be_present
    end

    it "префіксує ключі, тобто розводить їх із Sidekiq у спільній базі" do
      expect(Kredis.namespaced_key("lock:web3:oracle:0xABC"))
        .to eq("#{Kredis.global_namespace}:lock:web3:oracle:0xABC")
    end

    it "лишає ключ-власник прогону ПОЗА своїм простором — його чистить лише after(:suite)" do
      # SUITE_OWNER_KEY навмисно не проходить через namespaced_key: зачистка
      # між прикладами не сміє його стирати (TEST.8).
      expect(SUITE_OWNER_KEY).not_to start_with("#{Kredis.global_namespace}:")
    end
  end

  describe "форма ініціалізатора (щоб рядок не зник тихо)" do
    let(:source) { Rails.root.join("config/initializers/kredis.rb").read }

    it "присвоює global_namespace на рівні файлу" do
      expect(source).to match(/^Kredis\.global_namespace\s*=\s*["']\w+["']/)
    end
  end
end
