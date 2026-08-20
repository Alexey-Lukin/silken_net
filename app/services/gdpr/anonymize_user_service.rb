# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Gdpr
  # [SEC.18] Анонімізація субʼєкта (GDPR Art.17 erasure) — БЕЗСУПЕРЕЧНА половина:
  # рівно ті поверхні, чиє стирання не потребує жодного присуду.
  #
  #   · sessions.destroy_all   — слід входу (ip/user_agent), не append-only;
  #     заразом гасить усі живі входи (той самий ефект, що change_password)
  #   · identities.destroy_all — OAuth-профіль разом із шифрованими секретами
  #   · users-рядок            — PII-поля → tombstone/nil; після цього вхід
  #     неможливий за побудовою (email затерто, digest знято — `authenticate`
  #     має nil-гард, — сесії вбиті, identities знищені), тобто анонімізація
  #     Є ефективним offboarding-ом без окремого механізму деактивації
  #
  # 🔒 Стелі названі СВІДОМО, і кожна чекає власного присуду (`00_07` SEC.18):
  #   · audit_logs НЕ чіпаються: ip_address/user_agent ВХОДЯТЬ у chain_payload
  #     append-only ланцюга (ARCH.57), тож псевдонімізація поля вимагає
  #     перехешування ланцюга від рядка до хвоста — форма (re-hash ⊥
  #     crypto-shredding ⊥ Art.17(3)-виняток) є ⚖️-рішенням, не кодом
  #   · maintenance_records НЕ чіпаються: Evidence Protocol (гард
  #     `guard_evidence_purge!`) тримає фотодокази незнищенними для
  #     repair/installation — напруга «доказ ⊥ erasure» теж ⚖️.
  #     Авторство при цьому перестає ідентифікувати САМЕ ЦИМ сервісом:
  #     `User#full_name` фолбекає на email, а email уже tombstone
  #
  # Слід акту — синхронний AuditLog.create! ПЕРЕД мутаціями (прецедент
  # `record_audit_trail_for_purge!`): анонімізація незворотна, тож запис мусить
  # бути ПЕРСИСТОВАНИЙ до неї, а не поставлений у чергу. Metadata свідомо НЕ
  # несе жодного старого PII — інакше слід про стирання сам став би копією.
  class AnonymizeUserService < ApplicationService
    TOMBSTONE_DOMAIN = "anonymized.invalid"

    # @param user  [User] субʼєкт анонімізації
    # @param actor [User, nil] хто ініціював акт; nil → сам субʼєкт (типова
    #   форма DSAR — запит іде ВІД особи; оператор передає себе явно, системний
    #   виконавець — `User.oracle_executioner`, прецедент Auditable)
    def initialize(user, actor: nil)
      @user = user
      @actor = actor || user
    end

    def perform
      ActiveRecord::Base.transaction do
        record_anonymization_trail!
        @user.sessions.destroy_all
        @user.identities.destroy_all
        scrub_user_row!
      end
      @user
    end

    private

    def record_anonymization_trail!
      AuditLog.create!(
        user_id: @actor.id,
        organization_id: @user.organization_id,
        action: "user_anonymized",
        auditable_type: "User",
        auditable_id: @user.id,
        # Лише структурні факти: скільки чого стерто — жодного значення PII.
        metadata: {
          subject_user_id: @user.id,
          sessions_destroyed: @user.sessions.count,
          identities_destroyed: @user.identities.count
        }
      )
    end

    def scrub_user_row!
      @user.update!(
        email_address: "erased-#{@user.id}@#{TOMBSTONE_DOMAIN}",
        first_name: nil,
        last_name: nil,
        phone_number: nil,
        telegram_chat_id: nil,
        push_token: nil,
        locale: nil,
        otp_secret: nil,
        otp_last_used_at: nil,
        otp_required_for_login: false,
        recovery_codes: nil,
        password_digest: nil,
        organization_id: nil
      )
    end
  end
end
