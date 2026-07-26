# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [INF.22] Ловить «конфіг повний, шлях мертвий» для Grafana-алертів: alert-правило, що
# посилається на метрику з typo в назві (або на прибрану з реєстру метрику), тихо НІКОЛИ
# не спрацює — так само як web:80 віддавав job-метрики нулями (§06-нора). Цей spec звіряє
# КОЖНУ silkennet_-метрику з усіх alert-expr проти Prometheus::Client реєстру, який будує
# config/initializers/prometheus.rb.
RSpec.describe "Grafana alert rules ↔ Prometheus registry consistency" do # rubocop:disable RSpec/DescribeClass
  # Base-імена всіх зареєстрованих метрик (counter несе _total у назві; histogram — базове
  # ім'я, expr додає _bucket/_sum/_count — нормалізуємо на боці referenced нижче).
  let(:registered) { SilkenNet::Metrics::REGISTRY.metrics.map { |m| m.name.to_s }.to_set }

  let(:alerts_file) { Rails.root.join("deploy/grafana/alerts/silkennet-alerts.yaml") }

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
end
