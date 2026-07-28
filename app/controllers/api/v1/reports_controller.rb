# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "csv"

module Api
  module V1
    class ReportsController < BaseController
      # GET /api/v1/reports
      # Список доступних звітів та зведена інформація для інвесторів
      def index
        org = acting_organization!

        @summary = {
          total_trees: org.cached_trees_count,
          total_clusters: org.total_clusters,
          health_score: org.health_score,
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

      # GET /api/v1/reports/carbon_absorption
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

      # GET /api/v1/reports/financial_summary
      # Фінансовий звіт для інвесторів Series C
      def financial_summary
        org = acting_organization!

        transactions = BlockchainTransaction
                         .joins(wallet: { tree: :cluster })
                         .where(clusters: { organization_id: org.id })

        @data = {
          total_contracted: org.total_contracted,
          active_contracts: org.naas_contracts.active.count,
          total_contracts: org.naas_contracts.count,
          blockchain_transactions: {
            total: transactions.count,
            confirmed: transactions.where(status: :confirmed).count,
            pending: transactions.where(status: :pending).count,
            failed: transactions.where(status: :failed).count
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

      NETWORK_EMISSION_DEFAULTS = { total_minted_scc: 0, total_burned_scc: 0, total_premiums_usdc: 0, net_deflation: 0 }.freeze

      # [SEC.1] Премія — off-chain USDC-факт (NaasContract), береться з БД і мерджиться
      # сюди, тож збій subgraph НЕ обнуляє відому премію. Minted/burned/net_deflation —
      # з subgraph (кеш 5 хв). Раніше total_premiums_usdc читав ніколи-не-емітовану
      # on-chain подію PremiumPaid → вічний 0 (знято, канон 05_03).
      def fetch_network_emission
        cached_subgraph_network_emission.merge(total_premiums_usdc: NaasContract.total_insurance_premiums.to_i)
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
        NETWORK_EMISSION_DEFAULTS.except(:total_premiums_usdc)
      rescue StandardError => e
        Rails.logger.warn("Real yield fetch timeout: #{e.message}")
        NETWORK_EMISSION_DEFAULTS.except(:total_premiums_usdc)
      end

      # --- CSV Streaming ---
      # Використовуємо Enumerator для стрімінгу CSV-рядків до клієнта.
      # Це дозволяє обробляти мільйони рядків без навантаження на пам'ять.
      # Для summary-звітів це 4-5 рядків, але при масштабуванні до per-tree exports
      # (мільярди дерев) стрімінг критичний.

      def stream_csv(filename, &block)
        headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
        headers["Content-Type"] = "text/csv"
        headers["Cache-Control"] = "no-cache"

        self.response_body = Enumerator.new(&block)
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
          yielder << CSV.generate_line([])
          yielder << CSV.generate_line([ "Blockchain Transactions" ])
          yielder << CSV.generate_line([ "Total", tx[:total] ])
          yielder << CSV.generate_line([ "Confirmed", tx[:confirmed] ])
          yielder << CSV.generate_line([ "Pending", tx[:pending] ])
          yielder << CSV.generate_line([ "Failed", tx[:failed] ])
          yielder << CSV.generate_line([])
          yielder << CSV.generate_line([ "Network Emission (DePIN/ReFi)" ])
          yielder << CSV.generate_line([ "Total Minted SCC", ry[:total_minted_scc] ])
          yielder << CSV.generate_line([ "Total Burned SCC", ry[:total_burned_scc] ])
          yielder << CSV.generate_line([ "Total Premiums USDC", ry[:total_premiums_usdc] ])
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
              [ "Total Contracts", data[:total_contracts].to_s ]
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
          pdf.move_down 10

          pdf.table(
            [
              [ "Metric", "Value" ],
              [ "Total Minted SCC", ry[:total_minted_scc].to_s ],
              [ "Total Burned SCC", ry[:total_burned_scc].to_s ],
              [ "Total Premiums USDC", ry[:total_premiums_usdc].to_s ],
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
