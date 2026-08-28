# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [ARCH.41] Момент ПРИЙОМУ пакета мусить їхати job-аргументом від КОЖНОГО
# продового enqueuer'а телеметрії.
#
# Чому це потребує окремого гейта, а не лише поведінкових пінів у сервісі:
# аргумент опціональний за побудовою (`received_at_iso = nil` — bench, HIL і
# спеки кличуть воркер напряму), тож його ВТРАТА на прод-сайті не ламає нічого
# видимого. Тракт мовчки повертається до деривації від `Time.now.utc` у момент
# ОБРОБКИ — тобто рівно до дефекту, який цей аргумент закриває: Sidekiq-ретрай
# через межу півночі UTC дає іншу добу → інший (x₀,y₀,z₀) → категоричний
# DCI-мисматч на ЧЕСНОМУ дереві, і саме там, де `try_time_sync_recovery` не
# працює (він гейтований `!cold_start_flag`, а це — гілка cold-start).
#
# 🔒 СТЕЛІ, названі, щоб зелене не читалось ширше:
#   · гейт судить НАЯВНІСТЬ четвертого аргументу, ніколи його ПРАВИЛЬНІСТЬ —
#     мітка з хибним часом пройде;
#   · він не стверджує, що сервіс мітку СПОЖИВАЄ: цю вісь тримають поведінкові
#     піни в `spec/services/telemetry_unpacker_service_spec.rb` («доба
#     cold-derive»), мутаційно перевірені;
#   · перелік сайтів не рукописний — його стереже ліхтар периметра нижче, тож
#     новий продовий enqueuer червонить, а не проходить мовчки.
module TelemetryReceivedAtPropagation
  # Продові точки входу телеметрії. `lib/silken_net/load_test/**` свідомо поза
  # периметром: bench-гарнес НЕ моделює прийом і чесно лишає мітку порожньою.
  PROD_ENQUEUERS = [
    "lib/coap_gate.rb",
    "app/controllers/api/v1/telemetry_controller.rb"
  ].freeze

  ENQUEUE_MARKER = "UnpackTelemetryWorker.perform_async"

  def self.sites
    Dir.chdir(REPO_ROOT) do
      Dir["{app,lib}/**/*.rb"].select { |f| REPO_ROOT.join(f).read.include?(ENQUEUE_MARKER) }
    end
  end

  # Текст виклику від маркера до збалансованої закривної дужки: у демоні він
  # однорядковий, у контролері багаторядковий, тож рахуємо глибину, а не рядки.
  def self.enqueue_call(path)
    src = REPO_ROOT.join(path).read
    idx = src.index(ENQUEUE_MARKER)
    return nil if idx.nil?

    start = src.index("(", idx)
    depth = 0
    src[start..].each_char.with_index do |ch, i|
      depth += 1 if ch == "("
      depth -= 1 if ch == ")"
      return src[start..(start + i)] if depth.zero?
    end
    nil
  end

  # Коми ВЕРХНЬОГО рівня — вкладені виклики (`Time.current.utc.iso8601`) ком не
  # мають сьогодні, але страхуємось від майбутніх аргументів із дужками.
  def self.top_level_arity(call)
    depth = 0
    1 + call.each_char.count do |ch|
      depth += 1 if "([{".include?(ch)
      depth -= 1 if ")]}".include?(ch)
      ch == "," && depth == 1
    end
  end
end

RSpec.describe TelemetryReceivedAtPropagation, type: :quality do
  it "ліхтар: перелік продових enqueuer'ів збігається з деревом" do
    found = described_class.sites
    bench = found.grep(%r{\Alib/silken_net/load_test/})

    expect(found - bench).to match_array(described_class::PROD_ENQUEUERS),
                             "новий продовий enqueuer телеметрії — додай його у PROD_ENQUEUERS " \
                             "і переконайся, що він передає received_at [ARCH.41]"
    # Ліхтар на сам ліхтар: якщо греп перестане щось знаходити, порівняння вище
    # стало б вакуумним (порожнє з порожнім).
    expect(bench).not_to be_empty
  end

  TelemetryReceivedAtPropagation::PROD_ENQUEUERS.each do |path|
    it "#{path} передає момент прийому четвертим аргументом" do
      call = described_class.enqueue_call(path)
      expect(call).not_to be_nil, "не знайдено виклик perform_async у #{path}"

      expect(described_class.top_level_arity(call)).to be >= 4,
                                                       "#{path}: enqueue має нести received_at (4-й аргумент) — без нього " \
                                                       "cold-derive мовчки повертається до доби ОБРОБКИ [ARCH.41]"
      expect(call).to include("iso8601"),
                      "#{path}: мітка часу мусить бути ISO-8601 — сервіс парсить її через Time.zone.iso8601"
    end
  end
end
