# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 `db/structure.sql` не сміє нести pg17-only GUC `transaction_timeout`.
#
# Механізм. Дамп робиться pg17-им `pg_dump` (партиції вимагають свіжого), а
# Postgres у CI — нижчої мажорної версії. `SET transaction_timeout = 0;` у
# ТАКОМУ сервері невідомий, тож `db:structure:load` падає на першому ж рядку
# файлу — тобто не на тій міграції, яку людина щойно писала, а на схемі цілком.
# Рядок треба зрізати ПЕРЕД комітом; це вже ловилось одного разу вручну
# (CHANGELOG: «drop PG17-only `SET transaction_timeout = 0;`»).
#
# 🔒 Чому спека, а не покладатись на CI. CI цей клас таки ловить — але аж на
# кроці завантаження схеми, повідомленням про синтаксис, і вже після push'у.
# Тут він червоніє в тому ж `bin/rspec`, що й так біжить перед комітом, і
# називає причину словами. Правило доти жило ЛИШЕ прозою (`CLAUDE.md §2`,
# `.cursorrules`) — тобто трималось памʼяттю того, хто робить дамп.
#
# 🔒 Чесна стеля, названа, а не обійдена: гейт пінує ОДИН відомий GUC, а не
# «будь-що, чого не знає стара мажорна версія». Allowlist усіх легальних `SET`
# гнив би тихо (кожен новий легальний GUC = червоне на здоровому дампі), а
# множину «pg18-only» сьогодні ніхто не знає. Тож коли впаде наступний такий
# рядок, лік — додати його сюди поіменно, а не узагальнювати цей гейт.
module StructureSqlPortability
  PATH = Rails.root.join("db/structure.sql")

  # pg17-only GUC-и, що ламають завантаження на нижчій мажорній версії.
  # Поіменно — див. стелю в шапці.
  FORBIDDEN = [ "transaction_timeout" ].freeze
end

RSpec.describe "db/structure.sql portability to the CI Postgres major" do # rubocop:disable RSpec/DescribeClass
  let(:sql) { File.read(StructureSqlPortability::PATH) }

  # Ліхтар на власний вимір: без цього «нуль порушень» означало б і «нуль
  # перевірок» — файл перейменували чи обрізали, а гейт звітує зелене над
  # порожнім рядком.
  it "reads a non-trivial dump that actually carries a GUC header" do
    expect(StructureSqlPortability::PATH).to exist
    expect(sql.lines.size).to be > 1_000
    expect(sql).to include("SET statement_timeout = 0;")
  end

  it "carries no pg17-only GUC the CI Postgres cannot parse" do
    offenders = StructureSqlPortability::FORBIDDEN.flat_map do |guc|
      sql.lines.each_with_index.filter_map do |line, idx|
        "db/structure.sql:#{idx + 1}: #{line.strip}" if line.include?(guc)
      end
    end

    expect(offenders).to be_empty, <<~MSG
      `db/structure.sql` carries a pg17-only GUC. The CI Postgres is an older
      major and does not know it, so `db:structure:load` dies on the schema
      header — the failure points at the whole schema, never at your migration.

      Fix: strip the offending line from the dump (do NOT hand-edit the rest of
      structure.sql — regenerate, then remove just this line), then re-run.

      #{offenders.join("\n")}
    MSG
  end
end
