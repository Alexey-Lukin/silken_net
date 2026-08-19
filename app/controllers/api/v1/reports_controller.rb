# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "csv"

module Api
  module V1
    class ReportsController < BaseController
      # [UI.7] Дім стрімінгу — спільний концерн: другий CSV-споживач (ledger
      # гаманця) зробив би приватну копію тут другим домом.
      include CsvStreamable

      # GET /reports
      # Список доступних звітів та зведена інформація для інвесторів
      def index
        org = acting_organization!

        # [ARCH.84] Одне читання покриття на обидві гілки формату — і скаляр, і підстава
        # під ним. `health_score` тепер nullable: `null` = не виміряно, ⊥ виміряний 0.0.
        health = org.health_coverage

        @summary = {
          total_trees: org.cached_trees_count,
          total_clusters: org.total_clusters,
          health_score: health.average,
          clusters_measured: health.measured,
          clusters_total: health.total,
          total_carbon_points: org.total_carbon_points,
          total_contracted: org.total_contracted,
          under_threat: org.under_threat?
        }

        respond_to do |format|
          format.json do
            render json: {
              organization: org.name,
              generated_at: Time.current.iso8601,
              summary: @summary,
              available_reports: %w[carbon_absorption financial_summary]
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("reports.index_title"),
              component: Reports::Index.new(organization: org, summary: @summary)
            )
          end
        end
      end

      # GET /reports/carbon_absorption
      # Звіт про поглинання CO₂ для екологічних аудитів
      def carbon_absorption
        org = acting_organization!
        wallets = org.wallets.includes(:tree)

        @data = {
          total_carbon_points: wallets.sum(:balance),
          wallets_count: wallets.count,
          trees_active: org.trees.where(status: :active).count,
          trees_total: org.cached_trees_count
        }

        respond_to do |format|
          format.json do
            render json: {
              report: "carbon_absorption",
              organization: org.name,
              generated_at: Time.current.iso8601,
              data: @data
            }
          end
          format.csv do
            stream_csv("carbon_absorption_#{org.id}_#{Date.current}.csv") do |yielder|
              generate_carbon_csv_enum(org, @data).each { |row| yielder << row }
            end
          end
          format.pdf do
            send_data generate_carbon_pdf(org, @data),
                      filename: "carbon_absorption_#{org.id}_#{Date.current}.pdf",
                      type: "application/pdf",
                      disposition: "inline"
          end
          format.html do
            render_dashboard(
              title: I18n.t("reports.carbon_absorption_title"),
              component: Reports::CarbonAbsorption.new(organization: org, data: @data)
            )
          end
        end
      end

      # GET /reports/financial_summary
      # Фінансовий звіт для інвесторів Series C
      def financial_summary
        org = acting_organization!

        # [ARCH.98] One-Home резолюції «чиї це гроші». Доти тут стояв
        # `joins(wallet: { tree: :cluster })` — INNER JOIN, тож cluster-sourced рядки
        # (`wallet_id IS NULL`: Celo-винагорода кластеру, слеш останнього дерева)
        # у ФІНАНСОВИЙ звіт організації не потрапляли взагалі.
        transactions = BlockchainTransaction.for_organization(org.id)

        # [S6.16] Один згрупований прохід замість чотирьох COUNT. Прунінгу тут не
        # буває за побудовою: звіт агрегує ВСЮ історію організації, тож будь-яка
        # `created_at`-межа змінила б відповідь, а не пришвидшила її. Знімається
        # саме кратність — доти кожна з дев'яти партицій сканувалась ЧОТИРИ рази
        # на один HTTP-запит. Ключі `group` — рядкові мітки enum'а.
        by_status = transactions.group(:status).count

        # [ARCH.90, присуд founder 2026-08-13] Премія переїхала СЮДИ, в org-секцію,
        # і стала скоупленою. Доти в блоці `network_emission` стояв
        # `NaasContract.total_insurance_premiums` — КЛАСОВА форма, тобто агрегат по
        # ВСІХ орендарях платформи, надрукований у звіті одного під міткою
        # «Total Premiums USDC». Дві причини, чому це не косметика: (1) число
        # відповідало на питання, якого читач не ставив, і виглядало як його
        # власне; (2) саме pooled-агрегат `protocols/legal/securities_review.md`
        # F8 називає фактором Howey prong 2 «common enterprise» + AIFMD, тож його
        # видимість на інвестор-facing поверхні — рішення з юридичною ціною.
        # Ключ перейменовано СВІДОМО: семантика змінилась, і тиха підміна значення
        # під старим іменем була б гіршою за гучний злам (клас «один токен, два
        # домени»). Скоуп працює тим самим прийомом, що `net_minted_supply` —
        # метод класу, викликаний на relation, чейнить `where` на неї.
        @data = {
          total_contracted: org.total_contracted,
          active_contracts: org.naas_contracts.active.count,
          total_contracts: org.naas_contracts.count,
          insurance_premiums_paid_usdc: org.naas_contracts.total_insurance_premiums.to_i,
          blockchain_transactions: {
            total: by_status.values.sum,
            confirmed: by_status.fetch("confirmed", 0),
            pending: by_status.fetch("pending", 0),
            failed: by_status.fetch("failed", 0)
          },
          network_emission: fetch_network_emission
        }

        respond_to do |format|
          format.json do
            render json: {
              report: "financial_summary",
              organization: org.name,
              generated_at: Time.current.iso8601,
              data: @data
            }
          end
          format.csv do
            stream_csv("financial_summary_#{org.id}_#{Date.current}.csv") do |yielder|
              generate_financial_csv_enum(org, @data).each { |row| yielder << row }
            end
          end
          format.pdf do
            send_data generate_financial_pdf(org, @data),
                      filename: "financial_summary_#{org.id}_#{Date.current}.pdf",
                      type: "application/pdf",
                      disposition: "inline"
          end
          format.html do
            render_dashboard(
              title: I18n.t("reports.financial_summary_title"),
              component: Reports::FinancialSummary.new(organization: org, data: @data)
            )
          end
        end
      end

      private

      # [ARCH.90] `total_premiums_usdc` звідси знято разом із самим полем: блок
      # тепер суто on-chain, тож `.except(...)` на кожному rescue-шляху більше не
      # потрібен — форма fallback'у збігається з формою успіху, і розійтись їм ніде.
      # 🔴 [ARCH.103] Fallback віддає `nil`, а НЕ нулі: збій subgraph — це «не
      # виміряно», і жодна з трьох величин на ньому не стає нулем. Доти недоступність
      # зовнішнього джерела друкувалась у фінзвіті як «намінтовано 0 / спалено 0 /
      # дефляція 0» — тобто найспокійніший можливий стан протоколу, невідрізнимий
      # від справжнього. ⚠️ Форма fallback'у й далі збігається з формою успіху
      # (ті самі три ключі) — змінилось лише те, що вони більше нічого не СТВЕРДЖУЮТЬ.
      NETWORK_EMISSION_DEFAULTS = { total_minted_scc: nil, total_burned_scc: nil, net_deflation: nil }.freeze

      # [SEC.1] Премія — off-chain USDC-факт (`NaasContract`), НЕ on-chain подія:
      # доти `total_premiums_usdc` читав ніколи-не-емітовану `PremiumPaid` → вічний 0
      # (знято, канон `05_03`). [ARCH.90] А тепер вона й фізично не тут: блок містить
      # ЛИШЕ on-chain протокольні величини (публічні дані subgraph, кеш 5 хв), а
      # премія живе в org-секції `@data` скоупленою на організацію. Наслідок для
      # читача цього методу: збій subgraph більше не має що «обнуляти» повз премію —
      # вони роз'єднані, і кожна відповідає рівно за свій домен.
      def fetch_network_emission
        cached_subgraph_network_emission
      end

      # SCC-показники з subgraph (minted/burned/net_deflation), кеш 5 хв — щоб не блокувати
      # HTTP-запит GraphQL-раундтрипом. Премії тут НЕ беруться (DB-джерело — див. вище).
      def cached_subgraph_network_emission
        Rails.cache.fetch("reports_real_yield", expires_in: 5.minutes) do
          financials = Timeout.timeout(10) do
            TheGraph::QueryService.new.fetch_protocol_financials
          end
          {
            total_minted_scc: financials[:total_minted],
            total_burned_scc: financials[:total_burned],
            net_deflation: financials[:total_burned] - financials[:total_minted]
          }
        end
      rescue TheGraph::QueryService::QueryError => e
        Rails.logger.warn("Real yield fetch failed: #{e.message}")
        NETWORK_EMISSION_DEFAULTS
      rescue StandardError => e
        Rails.logger.warn("Real yield fetch timeout: #{e.message}")
        NETWORK_EMISSION_DEFAULTS
      end

      def generate_carbon_csv_enum(org, data)
        Enumerator.new do |yielder|
          yielder << CSV.generate_line([ "Carbon Absorption Report" ])
          yielder << CSV.generate_line([ "Organization", org.name ])
          yielder << CSV.generate_line([ "Generated At", Time.current.iso8601 ])
          yielder << CSV.generate_line([])
          yielder << CSV.generate_line(%w[Metric Value])
          yielder << CSV.generate_line([ "Total Carbon Points", data[:total_carbon_points] ])
          yielder << CSV.generate_line([ "Active Wallets", data[:wallets_count] ])
          yielder << CSV.generate_line([ "Active Trees", data[:trees_active] ])
          yielder << CSV.generate_line([ "Total Trees", data[:trees_total] ])
        end
      end

      def generate_financial_csv_enum(org, data)
        tx = data[:blockchain_transactions]
        ry = data[:network_emission]

        Enumerator.new do |yielder|
          yielder << CSV.generate_line([ "Financial Summary Report" ])
          yielder << CSV.generate_line([ "Organization", org.name ])
          yielder << CSV.generate_line([ "Generated At", Time.current.iso8601 ])
          yielder << CSV.generate_line([])
          yielder << CSV.generate_line(%w[Metric Value])
          yielder << CSV.generate_line([ "Total Contracted", data[:total_contracted] ])
          yielder << CSV.generate_line([ "Active Contracts", data[:active_contracts] ])
          yielder << CSV.generate_line([ "Total Contracts", data[:total_contracts] ])
          # [ARCH.90] Мітка навмисно каже «Paid by This Organization»: доти рядок
          # звався «Total Premiums USDC» і стояв у мережевій секції, несучи агрегат
          # по ВСІХ орендарях — тобто підпис не давав читачеві жодного способу
          # зрозуміти, чиє це число.
          yielder << CSV.generate_line([ "Insurance Premiums Paid by This Organization (USDC)", data[:insurance_premiums_paid_usdc] ])
          yielder << CSV.generate_line([])
          yielder << CSV.generate_line([ "Blockchain Transactions" ])
          yielder << CSV.generate_line([ "Total", tx[:total] ])
          yielder << CSV.generate_line([ "Confirmed", tx[:confirmed] ])
          yielder << CSV.generate_line([ "Pending", tx[:pending] ])
          yielder << CSV.generate_line([ "Failed", tx[:failed] ])
          yielder << CSV.generate_line([])
          yielder << CSV.generate_line([ "Network Emission (DePIN/ReFi) — protocol-wide, not this organization" ])
          yielder << CSV.generate_line([ "Total Minted SCC", ry[:total_minted_scc] ])
          yielder << CSV.generate_line([ "Total Burned SCC", ry[:total_burned_scc] ])
          yielder << CSV.generate_line([ "Net Deflation", ry[:net_deflation] ])
        end
      end

      # --- PDF Generators (Prawn) ---
      # Prawn будує PDF в пам'яті (потребує повну структуру документа).
      # Для великих звітів (мільйони рядків) рекомендується генерувати PDF
      # у фоновому Sidekiq-воркері та зберігати результат в Active Storage,
      # а клієнту повертати URL для скачування.

      def generate_carbon_pdf(org, data)
        Prawn::Document.new do |pdf|
          pdf.text "Carbon Absorption Report", size: 20, style: :bold
          pdf.move_down 10
          pdf.text "Organization: #{org.name}", size: 12
          pdf.text "Generated: #{Time.current.strftime('%d.%m.%Y %H:%M UTC')}", size: 10, color: "666666"
          pdf.move_down 20

          pdf.table(
            [
              [ "Metric", "Value" ],
              [ "Total Carbon Points", data[:total_carbon_points].to_s ],
              [ "Active Wallets", data[:wallets_count].to_s ],
              [ "Active Trees", data[:trees_active].to_s ],
              [ "Total Trees", data[:trees_total].to_s ]
            ],
            header: true,
            width: pdf.bounds.width,
            cell_style: { size: 10, padding: 8 }
          ) do |t|
            t.row(0).font_style = :bold
            t.row(0).background_color = "10b981"
            t.row(0).text_color = "ffffff"
          end
        end.render
      end

      def generate_financial_pdf(org, data)
        tx = data[:blockchain_transactions]
        ry = data[:network_emission]

        Prawn::Document.new do |pdf|
          pdf.text "Financial Summary Report", size: 20, style: :bold
          pdf.move_down 10
          pdf.text "Organization: #{org.name}", size: 12
          pdf.text "Generated: #{Time.current.strftime('%d.%m.%Y %H:%M UTC')}", size: 10, color: "666666"
          pdf.move_down 20

          pdf.table(
            [
              [ "Metric", "Value" ],
              [ "Total Contracted", data[:total_contracted].to_s ],
              [ "Active Contracts", data[:active_contracts].to_s ],
              [ "Total Contracts", data[:total_contracts].to_s ],
              # [ARCH.90] Див. CSV-двійник: підпис мусить називати ВЛАСНИКА числа.
              [ "Insurance Premiums Paid by This Organization (USDC)", data[:insurance_premiums_paid_usdc].to_s ]
            ],
            header: true,
            width: pdf.bounds.width,
            cell_style: { size: 10, padding: 8 }
          ) do |t|
            t.row(0).font_style = :bold
            t.row(0).background_color = "10b981"
            t.row(0).text_color = "ffffff"
          end

          pdf.move_down 20
          pdf.text "Blockchain Transactions Breakdown", size: 14, style: :bold
          pdf.move_down 10

          pdf.table(
            [
              [ "Category", "Count" ],
              [ "Total", tx[:total].to_s ],
              [ "Confirmed", tx[:confirmed].to_s ],
              [ "Pending", tx[:pending].to_s ],
              [ "Failed", tx[:failed].to_s ]
            ],
            header: true,
            width: pdf.bounds.width,
            cell_style: { size: 10, padding: 8 }
          ) do |t|
            t.row(0).font_style = :bold
            t.row(0).background_color = "10b981"
            t.row(0).text_color = "ffffff"
          end

          pdf.move_down 20
          pdf.text "Network Emission (DePIN/ReFi)", size: 14, style: :bold
          pdf.move_down 4
          pdf.text "Protocol-wide on-chain figures — not this organization's.", size: 9, color: "666666"
          pdf.move_down 10

          pdf.table(
            [
              [ "Metric", "Value" ],
              [ "Total Minted SCC", ry[:total_minted_scc].to_s ],
              [ "Total Burned SCC", ry[:total_burned_scc].to_s ],
              [ "Net Deflation", ry[:net_deflation].to_s ]
            ],
            header: true,
            width: pdf.bounds.width,
            cell_style: { size: 10, padding: 8 }
          ) do |t|
            t.row(0).font_style = :bold
            t.row(0).background_color = "10b981"
            t.row(0).text_color = "ffffff"
          end
        end.render
      end
    end
  end
end
