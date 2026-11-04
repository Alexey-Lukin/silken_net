# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.59, 2026-11-04] Черга воркера в картці `04_02 §11` — дзеркало `sidekiq_options
# queue:`, і доти воно не мало носія. Переїзд трьох воркерів у `web3_emission` свіпнули
# за ланцюжками викликів і прозою, а рядки `| **Черга** |` усіх трьох карток пережили
# його на зеленому CI — у ДОМІ реєстру воркерів, де черга несуча (strict-priority,
# CLAUDE.md §5). Виміряно до побудови: розходились рівно ці три.
#
# Судить: картка ДЖОБИ (Sidekiq::Job · ActiveJob) несе рядок черги, і він == коду;
# картка класу, що не є джобою (`ActuatorCommandWorker`), звільнена; картка класу, якого
# немає, мусить бути надгробком (`ВИДАЛЕНО` в заголовку).
# ⛔ Стеля: прозу й ланцюжки викликів (`04_02` call chains, `05_01`, `06_03`) НЕ судить —
# лише рядок `**Черга**` картки; відсутність КАРТКИ для нового воркера — теж не його вісь.
RSpec.describe "04_02 worker cards ⟷ the queue the code runs them in" do # rubocop:disable RSpec/DescribeClass
  let(:lines) { Rails.root.join("docs/04_02_Business_Logic_and_Services.md").readlines }
  let(:cards) do
    lines.each_with_index.filter_map do |line, i|
      # `[\w:]` — неймспейсні картки (`Governance::ParameterSyncWorker`) теж у периметрі.
      name = line[/\A#### `([\w:]+Worker)`/, 1] or next
      row = lines[(i + 1)..(i + 12)].find { |l| l.start_with?("| **Черга** |") }
      { name:, line: i + 1, heading: line, queue: row&.[](/\A\| \*\*Черга\*\* \| *`([a-z0-9_]+)`/, 1) }
    end
  end

  def code_queue(klass)
    return klass.get_sidekiq_options["queue"].to_s if klass.include?(Sidekiq::Job)

    klass.queue_name.to_s if klass < ActiveJob::Base
  end

  # Підлога проти колапсу парсера: зміна форми заголовка картки дала б нуль карток і
  # зелений прогін над порожньою множиною.
  it "finds the card population at all" do
    expect(cards.size).to be >= 50
  end

  it "states, for every job card, the queue the code runs it in" do
    drift = cards.filter_map do |card|
      klass = card[:name].safe_constantize or next
      expected = code_queue(klass) or next
      next if card[:queue] == expected

      "#{card[:name]} (04_02:#{card[:line]}): картка #{card[:queue].inspect}, код #{expected.inspect}"
    end
    expect(drift).to be_empty, "Черга в картці розійшлася з кодом:\n#{drift.join("\n")}"
  end

  it "marks a card of a class that no longer exists as a tombstone" do
    ghosts = cards.select { |card| card[:name].safe_constantize.nil? && !card[:heading].include?("ВИДАЛЕНО") }
    expect(ghosts.map { |card| card[:name] }).to be_empty
  end
end
