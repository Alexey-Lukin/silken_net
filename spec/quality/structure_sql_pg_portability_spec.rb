# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# 🔴 Мажор Postgres у CI мусить дорівнювати продовому — а GUC у `db/structure.sql`
# судиться ПРОТИ цього мажора, не проти зашитого числа.
#
# Механізм, і чому гейт саме такий. Дамп знімається `pg_dump`-ом тієї ж мажорної
# версії, що dev-сервер; кожен новий мажор додає у шапку свої `SET`-и, і сервер
# СТАРІШОГО мажора падає на першому ж рядку — тобто не на міграції, яку людина
# щойно писала, а на схемі цілком.
#
# 🔴 **Доти цей гейт забороняв `transaction_timeout` БЕЗУМОВНО — і це було
# лікуванням симптому.** Причина була не в дампі: dev і прод стояли на pg17
# (`terraform/database.tf` → `POSTGRES_17`), а CI — на pg16, тобто CI СУДИВ КОД
# НА СТАРІШОМУ ДВИГУНІ, ніж той, що виконає його в проді. Ручний крок «зрізати
# рядок перед комітом» був єдиним наслідком, який хтось помічав, і він
# приховував ширшу розбіжність. Виміряно контейнерами 2026-08-21 [OPS.27]:
# pg17 вантажить дамп у тому вигляді, як його віддає pg17 (EXIT=0) · pg16 на
# ньому падає (`unrecognized configuration parameter "transaction_timeout"`) ·
# pg17 вантажить і поточний стрипнутий дамп. Тож CI піднято до 17, а гейт
# перецілено з ОДНОГО забороненого слова на ПАРИТЕТ версій.
#
# 🔒 Стелі, названі чесно:
#   · Прод-мажор читається з `terraform/database.tf` — це НАША декларація, не
#     жива Cloud SQL API. Гейт доводить згоду двох наших домів, ніколи не
#     істинність жодного з них (§Guard-craft #67); якщо інстанс у хмарі
#     оновлять поза terraform, обидва файли лишаться згодні й обидва хибні.
#   · `VERSION_GATED_GUC` — реєстр ПОІМЕННО, а не «будь-що, чого не знає старий
#     мажор»: множину «pg18-only» сьогодні ніхто не знає, а allowlist усіх
#     легальних `SET` гнив би тихо. Наступний такий рядок додається сюди з
#     номером мажора, у якому він зʼявився.
#   · Гейт не бачить випадку «дамп знято КЛІЄНТОМ, новішим за CI і за прод
#     одночасно» — там обидва наші доми згодні, а файл усе одно нестерпний.
#     Проти цього працює не гейт, а те, що dev-сервер і прод тримають один мажор.
module StructureSqlPortability
  ROOT = REPO_ROOT
  STRUCTURE = ROOT.join("db/structure.sql")
  CI_WORKFLOW = ROOT.join(".github/workflows/ci.yml")
  TERRAFORM_DB = ROOT.join("terraform/database.tf")

  # GUC → мажор, починаючи з якого сервер його розуміє.
  VERSION_GATED_GUC = { "transaction_timeout" => 17 }.freeze

  def self.ci_majors
    CI_WORKFLOW.read.scan(%r{image:\s*postgis/postgis:(\d+)-}).flatten.map(&:to_i)
  end

  def self.prod_majors
    TERRAFORM_DB.read.scan(/database_version\s*=\s*"POSTGRES_(\d+)"/).flatten.map(&:to_i)
  end
end

RSpec.describe "Postgres major: CI ⟷ prod parity, and structure.sql against it [OPS.27]" do # rubocop:disable RSpec/DescribeClass
  let(:ci) { StructureSqlPortability.ci_majors }
  let(:prod) { StructureSqlPortability.prod_majors }

  # Ліхтар на власний вимір: обидва regex мусять щось знайти, інакше «паритет»
  # доводиться порівнянням двох порожніх множин — зелено й порожньо.
  it "actually extracts a major from BOTH sides" do
    expect(ci).not_to be_empty, "не знайдено `image: postgis/postgis:NN-` у ci.yml — regex осліп"
    expect(prod).not_to be_empty, "не знайдено `database_version = \"POSTGRES_NN\"` у terraform/database.tf"
    expect(StructureSqlPortability::STRUCTURE.read.lines.size).to be > 1_000
  end

  it "runs every CI service on the SAME major as production" do
    expect(ci.uniq).to eq(prod.uniq), <<~MSG
      Мажор Postgres у CI розійшовся з продовим.

        CI   (.github/workflows/ci.yml)  → #{ci.uniq.inspect}
        prod (terraform/database.tf)     → #{prod.uniq.inspect}

      ЧОМУ це не косметика: CI судить код на іншому движку, ніж той, що виконає
      його в проді. Розходження бачать не як «версії різні», а як випадковий
      симптом — саме так pg16-у CI при pg17-му проді роками виглядав як ручний
      крок «зрізати `SET transaction_timeout` із дампу».

      ЛІК — вирівняти образ у ci.yml по продовому мажору (обидві джоби), а не
      підганяти дамп під старіший движок.
    MSG
  end

  it "carries no GUC newer than the major CI actually runs" do
    major = ci.min or raise "немає CI-мажора"
    sql = StructureSqlPortability::STRUCTURE.read

    offenders = StructureSqlPortability::VERSION_GATED_GUC.flat_map do |guc, since|
      next [] if major >= since

      sql.lines.each_with_index.filter_map do |line, idx|
        "db/structure.sql:#{idx + 1}: #{line.strip}  (потребує pg#{since}, CI має pg#{major})" if line.include?(guc)
      end
    end

    expect(offenders).to be_empty, <<~MSG
      `db/structure.sql` несе GUC, новіший за мажор, який реально біжить у CI —
      `db:structure:load` помре на шапці схеми, і помилка вкаже на всю схему,
      а не на твою міграцію.

      #{offenders.join("\n")}

      Два ліки, і перший майже завжди правильний:
        1. ПІДНЯТИ CI до мажора прода (корінь — див. приклад паритету вище);
        2. лише якщо (1) неможливе — зрізати саме цей рядок із дампу
           (не редагувати решту structure.sql руками: перегенеруй і зніми рядок).
    MSG
  end
end
