# frozen_string_literal: true

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
              component: Views::Components::Reports::Index.new(organization: org, summary: @summary)
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
          format.html do
            render_dashboard(
              title: "Carbon Absorption Report",
              component: Views::Components::Reports::CarbonAbsorption.new(organization: org, data: @data)
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
          format.html do
            render_dashboard(
              title: "Financial Summary Report",
              component: Views::Components::Reports::FinancialSummary.new(organization: org, data: @data)
            )
          end
        end
      end
    end
  end
end
