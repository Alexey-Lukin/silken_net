# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods
      include ActionController::MimeResponds
      include ActionController::Helpers
      include Pagy::Method
      include Pundit::Authorization

      # --- ПОРЯДОК ЗАХИСТУ ---
      before_action :authenticate_user!

      # --- ОБРОБКА ПОМИЛОК (The Safety Net) ---
      # Ми не даємо хакеру зрозуміти природу помилки, але даємо розробнику чіткий JSON
      # StandardError defined first, so it is checked last (Rails rescue_from: reverse order).
      # This lets specific handlers below (RecordNotFound, etc.) take priority.
      rescue_from StandardError, with: :render_internal_server_error unless Rails.env.development?
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
      rescue_from ActiveModel::ValidationError, with: :render_validation_error
      rescue_from Pundit::NotAuthorizedError, with: :render_forbidden_pundit

      # --- ХЕЛПЕРИ ДОСТУПУ ---
      # Робимо методи доступними в Phlex-компонентах через хелпери Rails
      helper_method :current_user, :signed_in?

      private

      # 1. АВТЕНТИФІКАЦІЯ (The Handshake)
      # Підтримуємо як сесійні куки (для Дашборду), так і Bearer Tokens (для Мобільного додатка)
      def authenticate_user!
        # Спроба 1: Перевірка через HTTP Token (для API-запитів)
        @current_user = authenticate_with_http_token do |token, _options|
          User.find_by_token_for(:api_access, token)
        end

        # Спроба 2: Перевірка через сесію Rails 8 (для Дашборду в браузері)
        @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]

        return render_unauthorized unless @current_user

        @current_user.touch_visit! # Оновлюємо "пульс" активності користувача
      end

      def current_user
        @current_user
      end

      # Pundit використовує pundit_user для визначення поточного користувача.
      # За замовчуванням це current_user, але ми визначаємо явно для ясності.
      alias_method :pundit_user, :current_user

      def signed_in?
        current_user.present?
      end

      # 2. ПРАВА ДОСТУПУ (RBAC) — Legacy хелпери для поступової міграції
      # TODO: Перенести всі контролери на Pundit і видалити ці методи
      def authorize_admin!
        render_forbidden unless current_user&.role_admin? || current_user&.role_super_admin?
      end

      def authorize_super_admin!
        render_forbidden unless current_user&.role_super_admin?
      end

      def authorize_forester!
        render_forbidden unless current_user&.forest_commander?
      end

      # 3. PHLEX INTEGRATION (The Visual Oracle)
      # Метод для рендерингу Phlex-компонентів всередині нашого DashboardLayout.
      # Використовується, коли контролер відповідає на .html запит.
      def render_dashboard(title:, component:)
        render DashboardLayout.new(
          title: title,
          current_user: current_user,
          current_path: request.path,
          ews_alert_count: ews_alert_count_cached
        ) do
          render component
        end
      end

      # 4. СТАНДАРТИ ВІДПОВІДЕЙ (The Oracle's Voice)
      def render_unauthorized
        render json: { error: "Необхідна автентифікація. Брама закрита." }, status: :unauthorized
      end

      def render_forbidden
        render json: { error: "Недостатньо прав для цієї еволюції." }, status: :forbidden
      end

      def render_forbidden_pundit(_exception)
        render json: { error: "Недостатньо прав для цієї еволюції." }, status: :forbidden
      end

      def render_not_found(exception)
        render json: { error: "#{exception.model} не знайдено в матриці лісу." }, status: :not_found
      end

      def render_parameter_missing(exception)
        render json: { error: "Відсутній обов'язковий параметр: #{exception.param}" }, status: :bad_request
      end

      def render_validation_error(record)
        render json: { errors: record.errors.full_messages }, status: :unprocessable_content
      end

      def render_internal_server_error(exception)
        # Логуємо детальну помилку в консоль/файл, але не показуємо її клієнту
        Rails.logger.fatal "🚨 [API CRITICAL] #{exception.message}\n#{exception.backtrace.first(5).join("\n")}"
        render json: { error: "Збій у ядрі Океану. Повідомте Архітектора." }, status: :internal_server_error
      end

      # 5. PAGINATION METADATA (Pagy Helper)
      def pagy_metadata(pagy)
        { page: pagy.page, limit: pagy.limit, count: pagy.count, pages: pagy.last }
      end

      # 6. EWS ALERT COUNT (pre-computed for Sidebar — Rule 3: Zero DB queries in views)
      def ews_alert_count_cached
        Rails.cache.fetch("ews_alert_count_unresolved", expires_in: 1.minute) do
          EwsAlert.unresolved.count
        end
      rescue StandardError
        0
      end
    end
  end
end
