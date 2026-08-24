# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require_relative "../support/repo_root"

# [INF.22] Ловить «конфіг повний, шлях мертвий» для Grafana-алертів: alert-правило, що
# посилається на метрику з typo в назві (або на прибрану з реєстру метрику), тихо НІКОЛИ
# не спрацює — так само як web:80 віддавав job-метрики нулями (§06-нора). Цей spec звіряє
# КОЖНУ silkennet_-метрику з усіх alert-expr проти Prometheus::Client реєстру, який будує
# config/initializers/prometheus.rb.
RSpec.describe "Grafana alert rules ↔ Prometheus registry consistency" do # rubocop:disable RSpec/DescribeClass
  # Base-імена всіх зареєстрованих метрик (counter несе _total у назві; histogram — базове
  # ім'я, expr додає _bucket/_sum/_count — нормалізуємо на боці referenced нижче).
  # 🔴 [DOC-T.76] Реєстр метрик живе в Rails-ІНІЦІАЛІЗАТОРІ, а джоба `docs_check`
  # Rails не піднімає за побудовою. Файл вантажиться автономно: усі його
  # `Rails.`-звернення сидять у тілах sampler-методів, що на load-time не біжать.
  # ⚠️ Гард І ЛІНЬ несучі РАЗОМ: у повній сюїті (`ci.yml` job `test`) Rails уже
  # `load`-нув цей файл, а `load` НЕ пише в `$LOADED_FEATURES`, тож безумовний
  # `require_relative` дав би 83 попередження «already initialized constant».
  # Ліниво = на момент виклику Rails або вже є, або його не буде, і порядок
  # завантаження спек не впливає ні на що.
  let(:registered) do
    require_relative "../../config/initializers/prometheus" unless defined?(SilkenNet::Metrics::REGISTRY)
    SilkenNet::Metrics::REGISTRY.metrics.map { |m| m.name.to_s }.to_set
  end

  let(:alerts_file) { REPO_ROOT.join("deploy/grafana/alerts/silkennet-alerts.yaml") }

  let(:referenced) do
    yaml = YAML.safe_load(File.read(alerts_file), aliases: true)
    exprs = yaml.fetch("groups").flat_map do |group|
      group.fetch("rules").flat_map do |rule|
        rule.fetch("data").map { |datum| datum.dig("model", "expr") }
      end
    end
    exprs.compact.join(" ").scan(/\bsilkennet_[a-z0-9_]+/).uniq
  end

  it "every silkennet_ metric referenced in an alert expr exists in the Prometheus registry" do
    missing = referenced.reject do |name|
      registered.include?(name) || registered.include?(name.sub(/_(bucket|sum|count)\z/, ""))
    end

    expect(missing).to be_empty,
      "Alert-правила посилаються на НЕзареєстровані метрики (мертвий alert — ніколи не спрацює): " \
      "#{missing.join(', ')}. Звір deploy/grafana/alerts/silkennet-alerts.yaml ↔ " \
      "config/initializers/prometheus.rb."
  end

  it "the three INF.22 observability metrics are wired to an alert" do
    %w[
      silkennet_anchor_missed_weeks_total
      silkennet_filecoin_unarchived_depth
      silkennet_hadron_kyc_pending_depth
    ].each do |name|
      expect(referenced).to include(name), "#{name} втратив alert-правило (INF.22 регресія)"
    end
  end

  it "the ARCH.66 anchor-confirmation metrics are wired to an alert" do
    %w[
      silkennet_ethereum_anchor_stuck_sent_depth
      silkennet_ethereum_anchor_manual_review_depth
      silkennet_ethereum_anchor_reverted_total
    ].each do |name|
      expect(referenced).to include(name), "#{name} втратив alert-правило (ARCH.66 регресія)"
    end
  end

  it "the S6.1 Redis→DB nonce-fallback counters are wired to an alert" do
    %w[
      silkennet_m2m_nonce_fallback_total
      silkennet_qatt_nonce_fallback_total
    ].each do |name|
      expect(referenced).to include(name),
        "#{name} без alert-правила — escalation-тригер multi-zone Upstash сліпий (S6.1, 04_03 §5.15)"
    end
  end

  it "the E.37 telemetry-volume scale trigger is wired to an alert" do
    expect(referenced).to include("silkennet_telemetry_processed_total"),
      "row-count-тригер E.37 (>100M/міс) знову сліпий — ⚖️-рішення про scale-двигун без раннього сигналу"
  end

  # [ARCH.70] Сиблінг E.37-піна вище, і поставлений із тієї самої підстави: обидві
  # осі росту існують ЛИШЕ щоб ⚖️ (ширина вікна дропу) ухвалювався за кривою, а не
  # наосліп. Гейдж без alert-правила — саме той дефект, який E.37 уже оплатив
  # («метрика існувала, дивитись на неї проти порога не було кому»).
  it "the ARCH.70 partition-growth gauges are wired to an alert" do
    %w[
      silkennet_partitions
      silkennet_partitioned_table_bytes
      silkennet_partition_sample_timestamp_seconds
    ].each do |name|
      expect(referenced).to include(name),
        "#{name} без alert-правила — поріг «пора дропати» знову невидимий, і ⚖️ ширини вікна (ARCH.70) " \
        "ухвалюватиметься наосліп разом із SEC.18-retention та SLA §3.3"
    end
  end
end
