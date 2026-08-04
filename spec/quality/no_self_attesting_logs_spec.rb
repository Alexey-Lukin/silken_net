# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Заборона журнального рядка, що СТВЕРДЖУЄ доставку поруч із вимкненим транспортом.
#
# 🔴 Клас — «самосвідчення»: артефакт рапортує про результат, якого не перевіряв,
# бо слово-результат укладене в момент СПРОБИ, а не ПІДТВЕРДЖЕННЯ. Він відрізняється
# від «мертвого шляху» ([`feedback_mechanism_vs_its_trigger`]-клас, «конфіг повний,
# шлях мертвий») однією властивістю: там канал МОВЧИТЬ, і тишу зрештою помітять;
# тут канал ГОВОРИТЬ, і брехня стає першим доказом під час розбору інциденту.
#
# Виміряний привід ([`ARCH.78`], 2026-08-04): `SingleNotificationWorker` тримав
# закоментований виклик Twilio і одразу писав «Надіслано патрульному», а FCM —
# «Доставлено в додаток». Обидва рядки їхали на тракті пожежної та вандалізм-сирени,
# і сусідня спека пінила їх як бажану поведінку. Мертвий SMS-канал виявився б
# першою ж пожежею, якби лог не стверджував доставку.
#
# 🔒 Стеля — чотири речі, яких гейт НЕ бачить; мовчання тут означало б «перевірено».
#   1. Лише пара «закоментований виклик + лог поруч». Форма-АГРЕГАТОР невидима за
#      побудовою — саме нею вижив третій брехливий рядок того ж інциденту
#      (`AlertNotificationWorker` підсумовував «розіслано», не спитавши жодного
#      з трьох каналів). Виправлено руками, гейтом не покрито.
#   2. Транспорт, ВИДАЛЕНИЙ повністю, а не закоментований: лог лишається сам, і
#      поруч уже нема сліду, за який тут можна зачепитись.
#   3. Статус у БД замість логу (`update!(status: :confirmed)` до підтвердження) —
#      та сама хвороба на іншому носії ([`FW.63`]: стан просувається при ПОБУДОВІ
#      відповіді, не при її отриманні). Потребує власного детектора.
#   4. Дієслова беруться списком, тобто мовно-обмежені. Новий канал, що рапортує
#      незнайомим словом, пройде повз.
#
# ⚠️ Чому floor-assert на популяцію: після фіксу [`ARCH.78`] легальний улов = 0, а
# гейт над порожньою множиною зелений назавжди — рівно той клас, який цей файл і
# ловить. Тому сканована множина сама себе стереже.
RSpec.describe "no self-attesting delivery logs" do # rubocop:disable RSpec/DescribeClass
  # Слово, що називає ДОСЯГНУТИЙ результат доставки. Заперечені форми («НЕ надіслано»)
  # свідомо не рахуються — вони і є правильною редакцією для незадротованого каналу.
  let(:outcome_word) do
    /(?<!НЕ )(?<!не )\b(Надіслано|надіслано|Доставлено|доставлено|Розіслано|розіслано|[Ss]ent|[Dd]elivered)\b/
  end
  # Закоментований виклик зовнішнього клієнта: `# TwilioClient.send_sms(...)`.
  let(:commented_call) { /\A\s*#\s*[A-Z][\w:]*\.\w*(send|call|post|put|deliver|notify|publish|push)\w*\s*\(/ }
  let(:window) { 3 }

  let(:scanned_files) { Dir[Rails.root.join("app/**/*.rb")].sort }

  let(:offenders) do
    scanned_files.flat_map do |path|
      lines = File.readlines(path)

      lines.each_with_index.filter_map do |line, idx|
        next unless line.match?(commented_call)

        lo = [ idx - window, 0 ].max
        neighbours = lines[lo..(idx + window)] || []
        claim = neighbours.find do |n|
          n.match?(/\blogger\.(info|warn|error|debug)\b/) && n.match?(outcome_word)
        end
        next if claim.nil?

        "#{path.delete_prefix(Rails.root.to_s + '/')}:#{idx + 1} — вимкнений транспорт поруч із «#{claim.strip[0, 90]}»"
      end
    end
  end

  it "scans a non-empty population of application files" do
    expect(scanned_files.size).to be > 100
  end

  it "has no log line claiming a delivery its transport cannot perform" do
    expect(offenders).to be_empty, <<~MSG
      Журнал стверджує доставку, а транспорт поруч закоментований (#{offenders.size}):

      #{offenders.join("\n")}

      Лік — назвати СТАН КАНАЛУ, а не результат:
        Rails.logger.warn "[SMS] Канал не сконфігуровано — ... НЕ надіслано"
      Доки клієнт не задротований, рядок про успіх є твердженням без доказу.
    MSG
  end
end
