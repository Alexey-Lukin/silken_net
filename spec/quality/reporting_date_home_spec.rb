# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.100] Доба звіту мусить мати РІВНО ОДИН дім — `AiInsight.reporting_date`.
#
# Механізм дефекту, який купив цей гейт. Денний інсайт є агрегатом UTC-доби, і
# `AiInsight.for_date` шукає ТОЧНОЮ рівністю. Доки якір стояв двома формами —
# чотири копії `Time.current.utc.to_date - 1` на боці запису й `Cluster#local_yesterday`
# («вчора» в поясі орендаря) дефолтом у шести вердикт-несучих читачах — для кожного
# поясу західніше UTC−2 читач питав добу, якої писач не писав. Промах був ТИХИЙ:
# порожня вибірка не є помилкою, тож кожен споживач чесно застосував свій дефолт на
# «немає даних», і одна вигадана порожнеча роз'їхалась чотирма вироками протилежного
# знаку — `health_index = 1.0`, `:blackout` → Field Audit, страховий no-data → Field
# Audit, `:frozen` на слешингу.
#
# 🔒 Чому саме така форма. Дефект був НЕ в тому, що хтось написав неправильний вираз —
# обидва вирази були правильні кожен для свого наміру. Дефект був у тому, що їх було
# ДВА. Тож гейт стереже не значення й не поведінку (їх тримають піни в
# `cluster_health_check_worker_spec` · `naas_contract_spec` · `cluster_spec`), а
# ЄДИНІСТЬ: будь-яка друга форма вибору «вчорашньої доби» в `app/` червонить тут.
#
# ⚠️ Стеля, названа прямо: гейт статичний і бачить лише ці дві форми написання. Він
# НЕ побачить третю (наприклад `1.day.ago.to_date` чи дату з `SystemParameter`), і
# закрити цю половину статично неможливо. Її тримає сам дім: доки читачі беруть дату
# параметром або з `reporting_date`, вигадати третю форму нема де.
module ReportingDateHome
  HOME = "app/models/ai_insight.rb"

  # Обидві історичні форми якоря: UTC-вираз (боку запису) і per-tenant «вчора» (боку
  # читання). Друга не має в `app/` жодного легального вжитку — саме вона й була багом.
  RAW_UTC_ANCHOR = /utc\.to_date\s*-\s*1/
  PER_TENANT_ANCHOR = /Date\.yesterday/
  HOME_CALL = /AiInsight\.reporting_date/

  # Рядки КОДУ, не проза: коментарі цитують `AiInsight.reporting_date` навмисно.
  # ⚠️ Повертаємо шляхи без номерів рядків — інакше гейт червонів би на будь-якому
  # зсуві файлу, тобто стеріг би форматування замість єдності.
  def self.files_matching(pattern)
    Dir[Rails.root.join("app/**/*.rb")].filter_map do |path|
      hit = File.readlines(path).any? do |line|
        !line.lstrip.start_with?("#") && line.match?(pattern)
      end
      Pathname.new(path).relative_path_from(Rails.root).to_s if hit
    end.sort
  end
end

RSpec.describe ReportingDateHome, type: :quality do
  it "keeps the raw UTC anchor expression inside its home and nowhere else" do
    expect(described_class.files_matching(described_class::RAW_UTC_ANCHOR))
      .to eq([ described_class::HOME ])
  end

  it "carries no per-tenant «yesterday» anywhere in app/" do
    expect(described_class.files_matching(described_class::PER_TENANT_ANCHOR)).to be_empty
  end

  # 🔦 Ліхтар на предмет, не на форму. Без нього обидва приклади вище лишились би
  # зеленими, якби дім здеградував у мертвий метод, а читачі розійшлись третьою формою:
  # «нуль сирих якорів» однаково правдиве і для полагодженого дерева, і для порожнього.
  it "the home has real consumers — otherwise the two examples above guard emptiness" do
    consumers = described_class.files_matching(described_class::HOME_CALL)

    expect(consumers.size).to be >= 8
    # І сам дім мусить існувати з тією арністю, яку піни викликають обома способами.
    expect(AiInsight.method(:reporting_date).arity).to eq(-1)
  end
end
