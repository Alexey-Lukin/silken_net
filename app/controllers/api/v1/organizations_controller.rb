# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class OrganizationsController < BaseController
      # Тільки Адміни Океану (super_admin) мають доступ до глобального реєстру Кланів
      before_action :authorize_super_admin!

      # --- ПЕРЕЛІК КЛАНІВ (The Hierarchy View) ---
      def index
        @pagy, @organizations = pagy(Organization.includes(:clusters, :naas_contracts).all)

        respond_to do |format|
          format.json do
            render json: {
              data: OrganizationBlueprint.render_as_hash(@organizations, view: :index),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("organizations.index_title"),
              component: Organizations::Index.new(organizations: @organizations, pagy: @pagy)
            )
          end
        end
      end

      # --- ПРОФІЛЬ ОРГАНІЗАЦІЇ (Deep Audit) ---
      def show
        @organization = Organization.find(params[:id])
        @clusters = @organization.clusters

        @performance = {
          total_trees: @organization.cached_trees_count,
          carbon_minted: @organization.naas_contracts.sum(:emitted_tokens).to_f.round(2)
        }

        respond_to do |format|
          format.json do
            render json: {
              organization: OrganizationBlueprint.render_as_hash(@organization, view: :show),
              clusters: ClusterBlueprint.render_as_hash(@clusters),
              performance: @performance
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("organizations.show_title", name: @organization.name),
              component: Organizations::Show.new(
                organization: @organization,
                clusters: @clusters,
                performance: @performance
              )
            )
          end
        end
      end

      # --- ПЕРЕМИКАННЯ КОНТЕКСТУ (SEC.25 Ф2) ---
      # POST /api/v1/organizations/:id/switch
      #
      # Привілейована дія: super_admin входить у контекст чужої організації й далі
      # працює в ньому як звичайний її адміністратор. Права при цьому НЕ ростуть —
      # росте видимість, і саме тому слід обов'язковий.
      def switch
        # Перемикання має сенс лише на сесійному (браузерному) запиті: носій контексту —
        # cookie-сесія, якої Bearer-клієнт не носить за побудовою. Без цього гарду виклик
        # через Bearer тихо завів би нову сесію, віддав 200 — і не змінив НІЧОГО, бо
        # клієнт її не понесе. No-op, що виглядає як успіх, гірший за чесну відмову.
        return render_forbidden if bearer_token_request?

        organization = Organization.find(params[:id])

        record_switch!(organization)
        session[:acting_org_id] = organization.id
        drop_open_sockets!

        respond_to do |format|
          format.json { render json: { acting_organization_id: organization.id } }
          format.html { redirect_to root_path }
        end
      end

      private

      # 🔴 Запис ЗАВЖДИ передує мутації сесії — і саме тому тут `AuditLog.create!`, а
      # не `record_audit_trail!`. Штатний хелпер іде через `AuditLog.record_async!` →
      # `AuditLogWorker.perform_async`, тобто ставить джобу в чергу: «перед мутацією»
      # там означало б лише порядок ВИКЛИКУ, а не порядок ПЕРСИСТЕНЦІЇ — при зупиненому
      # Sidekiq перемикання відбулось би, а сліду не лишилось би взагалі. `create!`
      # пише рядок синхронно, і `before_create :compute_chain_hash` вбудовує його в
      # tamper-evident ланцюг тут-таки.
      #
      # `organization_id` — та організація, КУДИ входять: ланцюг будується per-org
      # (`AuditLog.verify_chain_integrity`), тож слід має лежати в журналі саме тієї
      # організації, чиї дані читатимуть. Інакше вона побачила б наслідки дій без
      # запису про те, хто і звідки прийшов.
      def record_switch!(organization)
        AuditLog.create!(
          user_id: current_user.id,
          organization_id: organization.id,
          action: "acting_organization_switched",
          auditable_type: "Organization",
          auditable_id: organization.id,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          metadata: { from_organization_id: acting_organization&.id }
        )
      end

      # Рве відкриті вебсокети ЦЬОГО пристрою (пара «користувач + сесія» — гранулярність
      # per-device з Ф1), щоб вкладки, відкриті до перемикання, не тягли далі стріми
      # попередньої організації.
      #
      # ⚠️ `reconnect: false` свідомо: дефолт гема — `true`, а перепідключений сокет
      # ре-підписався б на ТІ САМІ імена, бо вони живуть у ще не перезавантаженому DOM.
      # Тобто з дефолтом виклик був би косметикою. Ціна названа чесно: інші вкладки
      # цього браузера завмирають до перезавантаження — але жертва тут та сама людина,
      # що щойно натиснула «перемкнутись», а не сторонній глядач.
      #
      # 🔴 І чого це НЕ робить: підписане ім'я стріму лишається дійсним (детермінований
      # HMAC без TTL, ActionCable підписку не ре-авторизує). Хто зберіг токен,
      # слухатиме стару організацію й після перемикання.
      # ⚠️ Механізм відкликання тепер Є (`Organization#rotate_stream_epoch!`, [SEC.25 Ф3]),
      # але САМЕ ТУТ він свідомо НЕ смикається, і це не недогляд: ротація — подія
      # рівня організації, тож перемикання одного адміна перезавантажило б усіх її
      # глядачів заради гігієни одного. Плюс межа привілею тут не перетинається —
      # super_admin і далі має легітимний доступ до обох організацій і може
      # перемкнутись назад. Тобто це context-hygiene, а не витік (`04_03 §3.1`).
      def drop_open_sockets!
        # `session.id.public_id` — рівно те значення, яке `CookieStore#write_session`
        # кладе в `session_data["session_id"]` і яке `ApplicationCable::Connection`
        # читає в `identified_by :session_id`. Розходження тут означало б не помилку,
        # а ТИШУ: `connection_gid` не збігся б, і disconnect полетів би в порожнечу —
        # рівно те, чим цей примітив був до Ф1.
        # `session.id` тут не може бути nil: Bearer-гард на вході лишив тільки
        # сесійні запити, а `authenticate_user!` пропустив їх саме за `session[:user_id]`.
        # Тому без `&.` — safe-navigation створила б nil-плече, недосяжне за побудовою.
        ActionCable.server.remote_connections
                   .where(current_user: current_user, session_id: session.id.public_id)
                   .disconnect(reconnect: false)
      end
    end
  end
end
