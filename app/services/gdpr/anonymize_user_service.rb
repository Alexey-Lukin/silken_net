# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Gdpr
  # [SEC.18] Анонімізація субʼєкта (GDPR Art.17 erasure): рівно ті поверхні, чиє
  # стирання не потребує присуду АБО вже його дістало (журнал — 2026-11-04).
  #
  #   · sessions.destroy_all   — слід входу (ip/user_agent), не append-only;
  #     заразом гасить усі живі входи (той самий ефект, що change_password)
  #   · users-рядок            — PII-поля → tombstone/nil; після цього вхід
  #     неможливий за побудовою (email затерто, digest знято — `authenticate`
  #     має nil-гард, — сесії вбиті), тобто анонімізація
  #     Є ефективним offboarding-ом без окремого механізму деактивації
  #   · audit_logs ip/user_agent — стираються ЗНИЩЕННЯМ КЛЮЧА субʼєкта
  #     (`shred_audit_pii_key!`, та сама транзакція), ⚖️ форма B, founder 2026-11-04:
  #     журнал зберігав їх шифротекстом, і ланцюг хешує саме шифротекст — тож
  #     жоден рядок не переписується і `verify_chain_integrity` лишається зеленим.
  #     ⚠️ Стерто з БАЗИ, не з бекапів: копія ключа в знімку живе стільки, скільки
  #     сам знімок. `user_id` у рядках лишається — він тепер вказує на tombstone.
  #
  # 🔒 Стеля названа СВІДОМО й чекає власного присуду (`00_07` SEC.18):
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
        scrub_user_row!
        shred_audit_pii_key!
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
          sessions_destroyed: @user.sessions.count
        }
      )
    end

    def scrub_user_row!
      @user.update!(
        email_address: "erased-#{@user.id}@#{TOMBSTONE_DOMAIN}",
        first_name: nil,
        last_name: nil,
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

    # [SEC.18 форма B] Знищення ключа = стирання ip/ua з журналу. Окремим
    # `update_columns`, а НЕ ключем у `update!` вище: ключ народжує ІНШИЙ інстанс
    # субʼєкта (`AuditLog` вантажить його сам за `user_id`), тож у цьому він може
    # бути `nil` у памʼяті — і dirty-трекінг мовчки викинув би `audit_pii_key: nil`
    # з UPDATE, лишивши ключ у базі. `update_columns` пише безумовно.
    def shred_audit_pii_key!
      @user.update_columns(audit_pii_key: nil)
    end
  end
end
