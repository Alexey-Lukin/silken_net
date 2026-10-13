# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Не джоба: єдиний дім броадкасту статусу наказу актуатора. Push-доставки CMD немає —
# Королева вхідного слухача не має, наказ чекає в .pending і їде її poll'ом
# (Downlink::PendingQueueService, 03_02 §4а); кінець недоставного наказу — сторож
# ARCH.75 і safety-sweep ARCH.58. Кличуть poll-тракт, Reset і свіпери.
class ActuatorCommandWorker
  # 📈 Статичний метод для broadcast з денормалізованим organization_id
  # Rescue-ізоляція: викликається і з синхронного poll-тракту coap-демона
  # (Downlink::PendingQueueService CMD-видача) — збій cable-транспорту там
  # губив би acknowledged-команду (сирену) назавжди; UI-декорація ≠ доставка.
  # [UI.4] Стрім — `[actuator, :commands]`, а НЕ голий `Organization`: сторінка
  # показує команди одного актуатора, ширший стрім = зайва адресна книга. Голий
  # `Organization` до 2026-07-27 не слухала жодна сторінка взагалі.
  #
  # [I18N.2 · клас 2] Payload — locale-ВІЛЬНА заглушка зі `src`; бейдж несе `t()`,
  # тож рендер тут віддав би локаль процесу-продюсера всім підписникам одразу.
  def self.broadcast_command_state_static(command)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ command.actuator, :commands ],
      target: Actuators::CommandStatusFrame.dom_id(command.id),
      html: Actuators::CommandStatusFrameStub.new(
        command_id: command.id,
        src: Rails.application.routes.url_helpers.actuator_command_status_path(command)
      ).call
    )
  rescue StandardError => e
    # 🔒 Стеля, названа свідомо (UI.4): цей rescue тепер накриває і Reset-шлях,
    # який РАНІШЕ мав власний, не-ізольований броадкаст. Різниця в поведінці
    # реальна: там `raise` піднімався в Sidekiq, джоба ретраїлась, а `perform`
    # ідемпотентний по стейту й наприкінці ре-броадкастив — тобто збій cable
    # чесно повторював доставку UI-пульсу. Тепер втрачений пульс НЕ повторюється:
    # бейдж висить у старому стані до перезавантаження сторінки.
    # Обрано свідомо (UI-декорація ≠ доставка команди — сирена не сміє загинути
    # через cable), але це трейд, а не безкоштовне покращення.
    Rails.logger.warn "⚠️ CMD-статус broadcast не пройшов для наказу ##{command.id}: #{e.message}"
  end
end
