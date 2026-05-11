# frozen_string_literal: true

module Api
  module V1
    module Codex
      module Admin
        # CRUD for `Codex::DiscoveryRule` — admin+ only.
        class DiscoveryRulesController < BaseController
          before_action :set_rule, only: %i[show update destroy]

          def index
            authorize ::Codex::DiscoveryRule, :index?
            scope = ::Codex::DiscoveryRule.includes(:node, :created_by_user)
                                          .order(created_at: :desc)
            render json: { data: ::Codex::DiscoveryRuleBlueprint.render_as_hash(scope) }
          end

          def show
            authorize @rule
            render json: { data: ::Codex::DiscoveryRuleBlueprint.render_as_hash(@rule) }
          end

          def create
            authorize ::Codex::DiscoveryRule, :create?
            rule = ::Codex::DiscoveryRule.new(rule_params)
            rule.created_by_user = current_user
            if rule.save
              render json: { data: ::Codex::DiscoveryRuleBlueprint.render_as_hash(rule) },
                     status: :created
            else
              render json: { errors: rule.errors.full_messages }, status: :unprocessable_content
            end
          end

          def update
            authorize @rule
            if @rule.update(rule_params)
              render json: { data: ::Codex::DiscoveryRuleBlueprint.render_as_hash(@rule) }
            else
              render json: { errors: @rule.errors.full_messages }, status: :unprocessable_content
            end
          end

          def destroy
            authorize @rule
            @rule.destroy!
            head :no_content
          end

          private

          def set_rule
            @rule = ::Codex::DiscoveryRule.find(params[:id])
          end

          def rule_params
            permitted = params.permit(:name, :codex_node_id, :condition_type,
                                      :threshold_value, :active)
            if params[:params].is_a?(ActionController::Parameters)
              permitted[:params] = params[:params].to_unsafe_h
            elsif params[:params].is_a?(Hash)
              permitted[:params] = params[:params]
            end
            permitted
          end
        end
      end
    end
  end
end
