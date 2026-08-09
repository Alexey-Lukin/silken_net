# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 Кожен файловий шлях, названий у прозі `.claude/**` (скіли · промти · хуки),
# мусить існувати ВІД КОРЕНЯ РЕПО.
#
# Механізм і чому це не косметика. Скіли авто-інвокуються й читаються ЗАМІСТЬ
# коду — читач іде за адресою, не знаходить файлу і або вважає його видаленим,
# або створює новий поруч. Ніщо не червоніє: markdown не резолвить шляхів, а
# `docs_check` перевіряє лише форму `docs/NN_NN`, тобто до довільного шляху
# сліпий за побудовою.
#
# Улов на момент написання — 0, і це ВАЖЛИВО: до цього гейта їх було 30, усі
# трьох системних форм, жодної «регресії». (а) гібрид `docs/NN_NN` — префікс
# `docs/` приліплений до канонічного шортката, тобто ані шлях, ані шорткат;
# (б) шлях відносно TOOL-ROOT свого скіла (`lib/constants.py` у in-silico,
# `common/*.h` у firmware, `protocols/…` у legal-business); (в) шлях відносно
# каталогу, названого в сусідній колонці таблиці. Тобто гейт ставиться ПІСЛЯ
# фіксу прози — поставлений раніше, він давав би 30/30 «не той баг» щопрогону,
# а вічно-червона стійка навчає скіпати (`ssot-maintenance` §Guard-craft).
#
# 🔒 Стелі, названі чесно:
#   · Судиться лише токен у бектиках із файловим РОЗШИРЕННЯМ. Каталог
#     (`app/services/`) не перевіряється — форма надто розмита, а `firmware/
#     build-host` взагалі СТВОРЮЄТЬСЯ командою `cmake -B` і має не існувати.
#   · Glob'и, плейсхолдери (`<name>`, `{a,b}`) і `..` виключені: вони не адреси.
#   · Гейт не бачить шляхів, названих ПРОЗОЮ без бектиків — і це навмисно,
#     інакше він ловив би англійські слова з крапкою.
module ClaudeProsePathRefs
  ROOT = Rails.root
  SCAN_GLOB = ".claude/**/*.md"

  PATH_RE = /`([^`\s]+)`/
  FILE_EXT_RE = /\.(?:md|rb|py|c|h|sh|yml|yaml|sol|cs|json|toml|css|erb)\z/

  # ОГОЛОШЕНІ винятки — кожен із причиною. Виняток без причини гниє тихо;
  # виняток, чий предмет зник, сам є знахідкою (див. приклад нижче).
  EXEMPT = {
    "activestorage/engine.rb" => "файл ГЕМА (Rails), не наше дерево — цитується як місце дефолту",
    "radio_driver/radio.h" => "vendored Semtech API; його база (`firmware/extern/subghz-phy`) названа в ТІЙ САМІЙ комірці таблиці, тож форма однозначна для читача"
  }.freeze

  module_function

  def candidates
    Dir.glob(ROOT.join(SCAN_GLOB)).sort.flat_map do |file|
      rel = Pathname(file).relative_path_from(ROOT).to_s
      File.readlines(file).each_with_index.flat_map do |line, idx|
        line.scan(PATH_RE).flatten.filter_map do |raw|
          token = raw.sub(/[.,;:)]+\z/, "")
          next unless token.include?("/") && FILE_EXT_RE.match?(token)
          next if token.match?(/[*<>{}]/) || token.include?("..")
          # плейсхолдери зі скороченням шляху (`…/memory/MEMORY.md`) — не адреси
          next if token.include?("…") || token.include?('"')

          { token: token, at: "#{rel}:#{idx + 1}" }
        end
      end
    end
  end
end

RSpec.describe "[.claude prose] every cited file path resolves from the repo root" do # rubocop:disable RSpec/DescribeClass
  let(:candidates) { ClaudeProsePathRefs.candidates }

  # Ліхтар на власний вимір: звузили glob чи зламали регекс — і «нуль мертвих»
  # означає «нуль перевірених». Без цього гейт тихо стає декоративним.
  it "scans a non-trivial population of cited paths" do
    expect(candidates.size).to be > 100
    expect(candidates.map { _1[:at] }.uniq.size).to be > 20
  end

  it "cites no path that does not exist" do
    dead = candidates.reject { ClaudeProsePathRefs::EXEMPT.key?(_1[:token]) }
                     .reject { ClaudeProsePathRefs::ROOT.join(_1[:token]).exist? }

    report = dead.map { "  #{_1[:token]}  ← #{_1[:at]}" }

    expect(dead).to be_empty, <<~MSG
      `.claude/**` prose cites paths that do not exist from the repo root.

      A skill is read INSTEAD of the code, so a dead address sends the reader
      to nothing — and nothing goes red: markdown does not resolve paths.

      Three forms produce almost all of these:
        · `docs/NN_NN` — the `docs/` prefix glued onto the canonical shortcut;
          write either the full `docs/NN_NN_Full_Name.md` or the bare `NN_NN §N`
        · a path relative to the SKILL's tool-root (`lib/…` in in-silico,
          `common/…` in firmware) — prefix it from the repo root
        · a path relative to a directory named in the neighbouring table cell

      #{report.join("\n")}
    MSG
  end

  # Виняток, чий предмет зник, мовчки благословить наступний шлях, що сяде на
  # ту саму адресу. Тому список винятків стереже сам себе.
  it "carries no exemption whose subject has gone" do
    cited = candidates.map { _1[:token] }.to_set
    stale = ClaudeProsePathRefs::EXEMPT.keys.reject { cited.include?(_1) }

    expect(stale).to be_empty,
                     "EXEMPT entries whose path is no longer cited anywhere — remove them: #{stale.inspect}"
  end
end
