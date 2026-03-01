# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      # Дозволяємо доступ до входу без автентифікації
      skip_before_action :authenticate_user!, only: [ :new, :create ]

      # --- ПОРТАЛ ВХОДУ ---
      # GET /api/v1/login
      def new
        respond_to do |format|
          format.html do
            # Для логіну ми не використовуємо render_dashboard, 
            # бо нам не потрібен Sidebar до входу.
            render Views::Components::Sessions::New.new
          end
        end
      end

      # --- ВХІД (Login) ---
      # POST /api/v1/login
      def create
        user = User.find_by(email_address: params[:email])

        if user&.authenticate(params[:password])
          # Генеруємо токен доступу (Rails 8)
          token = user.generate_token_for(:api_access)

          # Оновлюємо сесію для Web-дашборду
          session[:user_id] = user.id
          user.touch_visit!

          respond_to do |format|
            format.json do
              render json: {
                token: token,
                user: { id: user.id, email: user.email_address, full_name: user.full_name, role: user.role }
              }, status: :created
            end
            format.html { redirect_to api_v1_dashboard_index_path, notice: "Neural Link Established." }
          end
        else
          respond_to do |format|
            format.json { render json: { error: "Невірні координати доступу." }, status: :unauthorized }
            format.html do
              flash.now[:alert] = "Access Denied: Invalid Credentials."
              render Views::Components::Sessions::New.new, status: :unauthorized
            end
          end
        end
      end

      # --- ВИХІД (Logout) ---
      # DELETE /api/v1/logout
      def destroy
        session[:user_id] = nil
        
        respond_to do |format|
          format.json { render json: { message: "Вихід успішний. Брама закрита." }, status: :ok }
          format.html { redirect_to api_v1_login_path, notice: "Neural Link Severed." }
        end
      end
    end
  end
end
