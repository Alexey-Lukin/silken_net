# frozen_string_literal: true

require "csv"

module Api
  module V1
    class ReportsController < BaseController
      # GET /api/v1/reports
      # Список доступних звітів та зведена інформація для інвесторів
      def index
        org = current_user.organization

        @summary = {
          total_trees: org.cached_trees_count,
          total_clusters: org.total_clusters,
          health_score: org.health_score,
          total_carbon_points: org.total_carbon_points,
          total_invested: org.total_invested,
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
              title: "Reports Archive",
              component: Reports::Index.new(organization: org, summary: @summary)
            )
          end
        end
      end

      # GET /api/v1/reports/carbon_absorption
      # Звіт про поглинання CO₂ для екологічних аудитів
      def carbon_absorption
        org = current_user.organization
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
            send_data generate_carbon_csv(org, @data),
                      filename: "carbon_absorption_#{org.id}_#{Date.current}.csv",
                      type: "text/csv"
          end
          format.pdf do
            send_data generate_carbon_pdf(org, @data),
                      filename: "carbon_absorption_#{org.id}_#{Date.current}.pdf",
                      type: "application/pdf",
                      disposition: "inline"
          end
          format.html do
            render_dashboard(
              title: "Carbon Absorption Report",
              component: Reports::CarbonAbsorption.new(organization: org, data: @data)
            )
          end
        end
      end

      # GET /api/v1/reports/financial_summary
      # Фінансовий звіт для інвесторів Series C
      def financial_summary
        org = current_user.organization

        transactions = BlockchainTransaction
                         .joins(wallet: { tree: :cluster })
                         .where(clusters: { organization_id: org.id })

        @data = {
          total_invested: org.total_invested,
          active_contracts: org.naas_contracts.active.count,
          total_contracts: org.naas_contracts.count,
          blockchain_transactions: {
            total: transactions.count,
            confirmed: transactions.where(status: :confirmed).count,
            pending: transactions.where(status: :pending).count,
            failed: transactions.where(status: :failed).count
          }
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
            send_data generate_financial_csv(org, @data),
                      filename: "financial_summary_#{org.id}_#{Date.current}.csv",
                      type: "text/csv"
          end
          format.pdf do
            send_data generate_financial_pdf(org, @data),
                      filename: "financial_summary_#{org.id}_#{Date.current}.pdf",
                      type: "application/pdf",
                      disposition: "inline"
          end
          format.html do
            render_dashboard(
              title: "Financial Summary Report",
              component: Reports::FinancialSummary.new(organization: org, data: @data)
            )
          end
        end
      end

      private

      # --- CSV Generators ---

      def generate_carbon_csv(org, data)
        CSV.generate do |csv|
          csv << [ "Carbon Absorption Report" ]
          csv << [ "Organization", org.name ]
          csv << [ "Generated At", Time.current.iso8601 ]
          csv << []
          csv << %w[Metric Value]
          csv << [ "Total Carbon Points", data[:total_carbon_points] ]
          csv << [ "Active Wallets", data[:wallets_count] ]
          csv << [ "Active Trees", data[:trees_active] ]
          csv << [ "Total Trees", data[:trees_total] ]
        end
      end

      def generate_financial_csv(org, data)
        tx = data[:blockchain_transactions]

        CSV.generate do |csv|
          csv << [ "Financial Summary Report" ]
          csv << [ "Organization", org.name ]
          csv << [ "Generated At", Time.current.iso8601 ]
          csv << []
          csv << %w[Metric Value]
          csv << [ "Total Invested", data[:total_invested] ]
          csv << [ "Active Contracts", data[:active_contracts] ]
          csv << [ "Total Contracts", data[:total_contracts] ]
          csv << []
          csv << [ "Blockchain Transactions" ]
          csv << [ "Total", tx[:total] ]
          csv << [ "Confirmed", tx[:confirmed] ]
          csv << [ "Pending", tx[:pending] ]
          csv << [ "Failed", tx[:failed] ]
        end
      end

      # --- PDF Generators (Prawn) ---

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

        Prawn::Document.new do |pdf|
          pdf.text "Financial Summary Report", size: 20, style: :bold
          pdf.move_down 10
          pdf.text "Organization: #{org.name}", size: 12
          pdf.text "Generated: #{Time.current.strftime('%d.%m.%Y %H:%M UTC')}", size: 10, color: "666666"
          pdf.move_down 20

          pdf.table(
            [
              [ "Metric", "Value" ],
              [ "Total Invested", data[:total_invested].to_s ],
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
        end.render
      end
    end
  end
end
