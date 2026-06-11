#!/usr/bin/env ruby
# frozen_string_literal: true

# [S2.2/S2.3/FW.18b] One-command імпорт Grafana IaC у Grafana Cloud.
#
# Замінює багатокроковий ручний шлях (UI-кліки + curl із плейсхолдерами):
#   GRAFANA_URL=https://<stack>.grafana.net GRAFANA_API_TOKEN=<token> \
#     ruby deploy/grafana/import.rb
#
# Робить:
#   1. Авто-виявлення UID Prometheus datasource (або ENV DATASOURCE_UID).
#   2. Folder "SilkenNet" (створює, якщо нема; або ENV GRAFANA_FOLDER).
#   3. Дашборд: POST /api/dashboards/import з ПРАВИЛЬНИМ wrapper'ом
#      ({dashboard, overwrite, inputs: [DS_PROMETHEUS → uid]}) — голий JSON
#      без inputs datasource не прив'язує.
#   4. Alert rules: підстановка ${DATASOURCE_UID} У ПАМ'ЯТІ (репо-файл не
#      чіпається) → ідемпотентний upsert per-rule через Alerting
#      Provisioning API (POST, при конфлікті uid — PUT) з
#      X-Disable-Provenance (рулі лишаються редагованими в UI) → інтервал
#      групи best-effort через rule-groups endpoint.
#
# `--dry-run` — без credentials і без HTTP: валідація форми обох артефактів
# (JSON парситься + DS_PROMETHEUS input; YAML парситься, uid'и унікальні,
# всі datasourceUid = плейсхолдер) + план дій.
#
# Контакт-поінт/notification policy НЕ створює — вибір каналу (Slack/
# PagerDuty/Email) лишається owner-рішенням (README).

require "json"
require "yaml"
require "net/http"
require "uri"

ROOT           = File.expand_path(__dir__)
DASHBOARD_PATH = File.join(ROOT, "dashboards", "silkennet-overview.json")
ALERTS_PATH    = File.join(ROOT, "alerts", "silkennet-alerts.yaml")
PLACEHOLDER    = "${DATASOURCE_UID}"
DS_INPUT_NAME  = "DS_PROMETHEUS"

def fail!(msg)
  warn "✗ #{msg}"
  exit 1
end

def step(msg)
  puts "→ #{msg}"
end

# ---------------------------------------------------------------------------
# Локальна валідація артефактів (працює і в dry-run, і перед live-імпортом)
# ---------------------------------------------------------------------------
def load_dashboard
  dash = JSON.parse(File.read(DASHBOARD_PATH))
  inputs = dash["__inputs"] || []
  ds = inputs.find { |i| i["name"] == DS_INPUT_NAME }
  fail! "#{DASHBOARD_PATH}: нема __inputs #{DS_INPUT_NAME} — import не зможе прив'язати datasource" unless ds
  fail! "#{DASHBOARD_PATH}: порожні panels" if Array(dash["panels"]).empty?
  dash
end

def load_alert_groups
  doc = YAML.safe_load(File.read(ALERTS_PATH))
  groups = doc.fetch("groups") { fail! "#{ALERTS_PATH}: нема груп" }
  uids = groups.flat_map { |g| g["rules"].map { |r| r["uid"] } }
  fail! "#{ALERTS_PATH}: дублікати uid: #{uids.tally.select { |_, c| c > 1 }.keys}" unless uids.uniq == uids
  groups.each do |g|
    g["rules"].each do |r|
      %w[uid title condition data].each do |k|
        fail! "#{ALERTS_PATH}: рул без '#{k}' у групі #{g['name']}" unless r[k]
      end
      r["data"].each do |d|
        next unless d.key?("datasourceUid")
        next if d["datasourceUid"] == PLACEHOLDER || d["datasourceUid"] == "__expr__"

        fail! "#{ALERTS_PATH}: #{r['uid']}: datasourceUid '#{d['datasourceUid']}' — не плейсхолдер і не __expr__"
      end
    end
  end
  groups
end

dashboard = load_dashboard
groups    = load_alert_groups
rule_count = groups.sum { |g| g["rules"].length }

if ARGV.include?("--dry-run")
  puts "✅ dry-run: артефакти валідні"
  puts "   дашборд: #{Array(dashboard['panels']).length} панелей, input #{DS_INPUT_NAME}"
  groups.each { |g| puts "   група #{g['name']}: #{g['rules'].length} рулів, interval #{g['interval']}" }
  puts "   план: discover datasource UID → folder → dashboards/import → #{rule_count}× provisioning upsert"
  exit 0
end

# ---------------------------------------------------------------------------
# Live-імпорт
# ---------------------------------------------------------------------------
GRAFANA_URL = ENV["GRAFANA_URL"] or fail! "GRAFANA_URL не заданий (https://<stack>.grafana.net)"
TOKEN       = ENV["GRAFANA_API_TOKEN"] or fail! "GRAFANA_API_TOKEN не заданий (service-account token з роллю Editor+)"
FOLDER      = ENV.fetch("GRAFANA_FOLDER", "SilkenNet")

def request(method, path, body: nil, headers: {})
  uri = URI.join(GRAFANA_URL, path)
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method)
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{TOKEN}"
  req["Content-Type"]  = "application/json"
  headers.each { |k, v| req[k] = v }
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
  [ res.code.to_i, res.body.to_s.empty? ? {} : JSON.parse(res.body) ]
rescue JSON::ParserError
  [ res.code.to_i, { "raw" => res.body } ]
end

# 1. Datasource UID
ds_uid = ENV["DATASOURCE_UID"]
if ds_uid.nil?
  code, list = request(:get, "/api/datasources")
  fail! "GET /api/datasources → #{code}: #{list}" unless code == 200
  prom = list.find { |d| d["type"] == "prometheus" }
  fail! "Prometheus datasource не знайдено — задай DATASOURCE_UID явно" unless prom
  ds_uid = prom["uid"]
  step "datasource: #{prom['name']} (uid #{ds_uid})"
end

# 2. Folder
code, folders = request(:get, "/api/folders")
fail! "GET /api/folders → #{code}" unless code == 200
folder = folders.find { |f| f["title"] == FOLDER }
if folder
  step "folder «#{FOLDER}» вже існує (uid #{folder['uid']})"
else
  code, folder = request(:post, "/api/folders", body: { title: FOLDER })
  fail! "POST /api/folders → #{code}: #{folder}" unless code == 200
  step "folder «#{FOLDER}» створено (uid #{folder['uid']})"
end
folder_uid = folder["uid"]

# 3. Dashboard
code, res = request(:post, "/api/dashboards/import", body: {
                      dashboard: dashboard,
                      overwrite: true,
                      folderUid: folder_uid,
                      inputs: [ { name: DS_INPUT_NAME, type: "datasource",
                                  pluginId: "prometheus", value: ds_uid } ]
                    })
fail! "dashboards/import → #{code}: #{res}" unless code == 200
step "дашборд імпортовано: #{res['importedUrl'] || res['url']}"

# 4. Alert rules — per-rule upsert (стабільні uid'и в YAML = ідемпотентність)
prov_headers = { "X-Disable-Provenance" => "true" }
groups.each do |g|
  g["rules"].each do |rule|
    body = rule.merge("folderUID" => folder_uid, "ruleGroup" => g["name"], "orgID" => g.fetch("orgId", 1))
    body["data"] = rule["data"].map do |d|
      d.key?("datasourceUid") && d["datasourceUid"] == PLACEHOLDER ? d.merge("datasourceUid" => ds_uid) : d
    end
    code, res = request(:post, "/api/v1/provisioning/alert-rules", body: body, headers: prov_headers)
    if code == 409 || (code == 400 && res.to_s.include?("already exists"))
      code, res = request(:put, "/api/v1/provisioning/alert-rules/#{rule['uid']}", body: body, headers: prov_headers)
    end
    fail! "rule #{rule['uid']} → #{code}: #{res}" unless [ 200, 201, 202 ].include?(code)
    step "rule #{rule['uid']} ✓"
  end

  # Інтервал групи — best-effort: GET поточну групу → PUT з interval з YAML.
  code, grp = request(:get, "/api/v1/provisioning/folder/#{folder_uid}/rule-groups/#{g['name']}")
  if code == 200 && grp["interval"] != g["interval"]
    grp["interval"] = g["interval"]
    code, = request(:put, "/api/v1/provisioning/folder/#{folder_uid}/rule-groups/#{g['name']}",
                    body: grp, headers: prov_headers)
    warn "⚠ interval групи #{g['name']} не виставився (#{code}) — перевір у UI" unless code == 200
  end
end

puts "✅ імпортовано: дашборд + #{rule_count} alert rules у «#{FOLDER}»."
puts "   Лишається вручну: Contact point + Notification policy (README §Notification channel)."
