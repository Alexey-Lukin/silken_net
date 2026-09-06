# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Gdpr
  # [SEC.18] DSAR-експорт (GDPR Art.15 право доступу + Art.20 портованість):
  # структурований машиночитний зліпок УСІХ user-owned персональних даних.
  #
  # Периметр = User-owned вісь PII-реєстру (`04_01 §11`): сам рядок users,
  # sessions (слід входу), audit_logs де субʼєкт
  # є АКТОРОМ, maintenance_records авторства (+ мета фотодоказів). Org-owned
  # дані (clusters/trees/wallets/gateways) свідомо ПОЗА експортом — вони
  # належать організації, а «у дерев немає GDPR-даних» (`03_04 §6.3`).
  #
  # КРЕДЕНШЕЛИ НЕ віддаються (password_digest · otp_secret · recovery_codes):
  # DSAR віддає дані ПРО особу, а не секрети
  # автентифікації — їх віддача створила б нову витікову поверхню, і жоден
  # DSAR-прецедент (експорти великих платформ) секретів не включає.
  #
  # 🔒 Стеля названа: фотодокази їдуть МЕТАДАНИМИ (filename/byte_size/…), не
  # байтами — оригінали (свідомо з EXIF, ⚖️ 2026-08-20) доступні штатним
  # авторизованим шляхом; JSON із вбудованими блобами був би і крихкий, і
  # марний для портованості.
  class DataExportService < ApplicationService
    FORMAT_VERSION = 1

    def initialize(user)
      @user = user
    end

    def perform
      {
        format_version: FORMAT_VERSION,
        generated_at: Time.current.iso8601,
        user: user_payload,
        sessions: sessions_payload,
        audit_trail: audit_logs_payload,
        maintenance_records: maintenance_records_payload
      }
    end

    private

    def user_payload
      {
        id: @user.id,
        email_address: @user.email_address,
        first_name: @user.first_name,
        last_name: @user.last_name,
          push_token: @user.push_token,
        locale: @user.locale,
        role: @user.role,
        organization_name: @user.organization&.name,
        mfa_enabled: @user.mfa_enabled?,
        created_at: @user.created_at.iso8601,
        last_seen_at: @user.last_seen_at&.iso8601
      }
    end

    def sessions_payload
      @user.sessions.order(:created_at).map do |s|
        {
          ip_address: s.ip_address,
          user_agent: s.user_agent,
          created_at: s.created_at.iso8601,
          last_active_at: s.updated_at.iso8601
        }
      end
    end

    # Субʼєкт як АКТОР журналу: «хто і звідки прийшов» — персональні дані
    # саме актора, тож рядки віддаються цілком (append-only ланцюг при
    # ЧИТАННІ не зачіпається — це erasure-половина має з ним напругу).
    def audit_logs_payload
      @user.audit_logs.order(:created_at).map do |log|
        {
          action: log.action,
          auditable_type: log.auditable_type,
          auditable_id: log.auditable_id,
          metadata: log.metadata,
          ip_address: log.ip_address,
          user_agent: log.user_agent,
          created_at: log.created_at.iso8601
        }
      end
    end

    def maintenance_records_payload
      @user.maintenance_records.includes(photos_attachments: :blob).order(:performed_at).map do |mr|
        {
          id: mr.id,
          action_type: mr.action_type,
          maintainable_type: mr.maintainable_type,
          maintainable_id: mr.maintainable_id,
          performed_at: mr.performed_at&.iso8601,
          notes: mr.notes,
          photos: mr.photos.map do |photo|
            {
              filename: photo.filename.to_s,
              byte_size: photo.byte_size,
              content_type: photo.content_type,
              created_at: photo.created_at.iso8601
            }
          end
        }
      end
    end
  end
end
