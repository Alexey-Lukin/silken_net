# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# [DOC-T.88] Канонічний реєстр метрик у `06_03` вівся РУКАМИ — і розійшовся з
# Prometheus-реєстром рівно так, як передбачає правило `00_06 §1` про волатильні
# лічильники: шапка заявляла 47 counters при 48, бо `insurance_reserve_hold_total`
# лежав у таблиці ГЕЙДЖІВ (алерт на нього бере `increase()`, тобто читав його
# правильно, а док — ні).
#
# 🔴 Гейт судить ІМЕНА і ТИПИ, ніколи число. Саме число і є тим лічильником, який
# правило забороняє: воно дрейфує щокоміту, а множина імен — ні. Друга вісь нижче
# тримає цю заборону явно, інакше «поверни лічильник у шапку» повернулось би тихо.
#
# ⚠️ Дім — RSpec, а не крок `docs.yml` (як у `model_doc_sync`), і це вибір за
# ПЕРИМЕТРОМ: джерело істини тут `config/initializers/prometheus.rb`, а `docs.yml`
# тригериться на `docs/**` і `app/models/**` — тобто на зміну реєстру він би не
# прокинувся, і дрейф з боку КОДУ проходив би зеленим. Сюїта біжить завжди.
RSpec.describe "metric registry ⟷ 06_03 canonical tables" do # rubocop:disable RSpec/DescribeClass
  # Ліниво, як у `spec/deploy/grafana_alerts_spec.rb` [DOC-T.76]: у повній сюїті
  # Rails уже `load`-нув ініціалізатор, а `load` не пише в `$LOADED_FEATURES`,
  # тож безумовний `require_relative` дав би стос «already initialized constant».
  let(:registry) do
    unless defined?(SilkenNet::Metrics::REGISTRY)
      require_relative "../../config/initializers/prometheus"
    end
    SilkenNet::Metrics::REGISTRY
  end

  let(:doc) { REPO_ROOT.join("docs/06_03_Prometheus_Observability.md").read }

  # Метод, а не константа: константа в `describe` тече в глобальний простір
  # (RSpec/LeakyConstantDeclaration) — і сусідній спек дістав би її мовчки.
  def sections = { counter: "Counters", gauge: "Gauges", histogram: "Histograms" }

  # Таблиця живе між своєю шапкою і наступною; остання — до кінця секції.
  def documented(kind)
    label = sections.fetch(kind)
    body = doc[/^\*\*#{label}[^:]*:\*\*(.*?)(?=^\*\*(?:#{sections.values.join("|")})[^:]*:\*\*|\A\z|^---$)/m, 1]
    raise "у 06_03 немає таблиці `**#{label}:**`" if body.nil?

    body.scan(/^\|\s*`(silkennet_[a-z0-9_]+)`/).flatten.uniq
  end

  def registered(kind)
    registry.metrics.select { |m| m.type == kind }.map { |m| m.name.to_s }
  end

  %i[counter gauge histogram].each do |kind|
    it "the #{kind} table lists exactly the registered #{kind} metrics" do
      missing_from_doc = registered(kind) - documented(kind)
      missing_from_code = documented(kind) - registered(kind)

      expect(missing_from_doc).to be_empty,
        "У реєстрі є `#{kind}`, яких НЕМА в таблиці 06_03: #{missing_from_doc.join(', ')}. " \
        "Додай рядок — інакше метрика існує, а канон про неї мовчить."
      expect(missing_from_code).to be_empty,
        "У таблиці 06_03 (`#{kind}`) є метрики, яких НЕМА в реєстрі з таким типом: " \
        "#{missing_from_code.join(', ')}. Перевір ТИП — саме так `insurance_reserve_hold_total` " \
        "(counter) роками лежав серед гейджів."
    end
  end

  # 🔴 Друга вісь, і вона не косметична: доти шапки несли `(N)`, і саме це число
  # протухло. Гейт на імена сам по собі не забороняє повернути лічильник назад.
  it "the table headers carry NO volatile count (00_06 §1)" do
    offenders = doc.scan(/^\*\*(#{sections.values.join("|")}) \(\d+\)\:\*\*/).flatten

    expect(offenders).to be_empty,
      "Шапки таблиць метрик знову несуть лічильник: #{offenders.join(', ')}. " \
      "`00_06 §1` це забороняє — число дрейфує щокоміту, а парність тримає цей гейт по ІМЕНАХ."
  end
end
