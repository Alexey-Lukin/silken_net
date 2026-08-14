# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Notifications
  # [UI.10] Дім ОДНОГО питання: чи має платформа ТРАНСПОРТ для цього каналу.
  #
  # Питання не про користувача. Те, що людина вписала телефон, не робить SMS
  # каналом доставки — і саме це злиття екран налаштувань стверджував роками:
  # він рахував «активним» будь-який канал, під яким заповнене поле, тоді як
  # SMTP закоментований, Twilio/FCM закоментовані, а Telegram-клієнта немає
  # взагалі ([`00_07`](../../../docs/00_07_Action_Plan_Tracker.md) ARCH.60/ARCH.78).
  #
  # 🔴 Чому це ОГОЛОШЕННЯ, а не дерівація — і чому спроба «вивести розумніше»
  # тут була б рецидивом того самого дефекту. Дефолтний `smtp_settings` Rails
  # (`localhost:25`, без автентифікації) за ФОРМОЮ не відрізняється від
  # справжнього ESP-конфіга, тож предикат «адреса заповнена» повертав би `true`
  # на незайманому скаффолді — тобто знову напис без джерела, лише виведений.
  # Для SMS/Telegram/Push конфіг-поверхні не існує зовсім: імена ENV назве
  # ARCH.60, і вигадувати їх наперед означало б завести другий дім чужого
  # рішення.
  #
  # Але оголошення, яке треба перемикати руками, протухає мовчки — тому пошта
  # має ДВА спостережуваних, обидва сьогодні хибні й обидва входять у першу ногу
  # ARCH.60 (sender-identity + транспорт). Щойно та нога приїде, екран скаже
  # правду без правки цього файлу; носій проти зворотного дрейфу —
  # `spec/services/notifications/delivery_channels_spec.rb`.
  module DeliveryChannels
    ALL = %i[email sms telegram push].freeze

    # Незмінений Rails-скаффолд. Лист від цієї адреси не долітає нікуди.
    SCAFFOLD_SENDER = "from@example.com"
    # Дефолт `ActionMailer`, коли `smtp_settings` не задавали взагалі.
    UNCONFIGURED_SMTP_HOST = "localhost"

    module_function

    # @return [Boolean] чи існує транспорт, здатний доставити цим каналом
    def available?(channel)
      case channel.to_sym
      when :email then email_transport_configured?
      # ARCH.60 — адаптерів немає в дереві; тут же їх і оголосять живими.
      when :sms, :telegram, :push then false
      else false
      end
    end

    # @return [Array<Symbol>] канали, що сьогодні реально доставляють
    def available
      ALL.select { |channel| available?(channel) }
    end

    def email_transport_configured?
      sender_configured? && smtp_host_configured?
    end

    def sender_configured?
      ApplicationMailer.default[:from].to_s.presence.present? &&
        ApplicationMailer.default[:from].to_s != SCAFFOLD_SENDER
    end

    def smtp_host_configured?
      ActionMailer::Base.smtp_settings[:address].to_s.presence.present? &&
        ActionMailer::Base.smtp_settings[:address].to_s != UNCONFIGURED_SMTP_HOST
    end
  end
end
