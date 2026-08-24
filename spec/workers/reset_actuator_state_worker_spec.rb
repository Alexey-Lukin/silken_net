# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResetActuatorStateWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:gateway) { create(:gateway, cluster: cluster) }
  let(:actuator) { create(:actuator, gateway: gateway, state: :active) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "when actuator is active" do
      let(:command) do
        silence_side_effects!(:actuator_dispatch)
        cmd = create(:actuator_command, actuator: actuator, status: :acknowledged, sent_at: 1.minute.ago)
        cmd.update_column(:status, :acknowledged)
        cmd
      end

      it "resets actuator to idle state" do
        described_class.new.perform(command.id)

        actuator.reload
        expect(actuator.state).to eq("idle")
      end

      it "marks command as confirmed with completed_at" do
        described_class.new.perform(command.id)

        command.reload
        expect(command.status).to eq("confirmed")
        expect(command.completed_at).to be_present
      end

      # Дзеркало «skips confirmation if command is not acknowledged» з неактивної
      # вітки — але тут актуатор ЖИВИЙ, тож гілка інша. `perform` ідемпотентний
      # (Sidekiq ретраїть після часткового збою), і повторний прохід не сміє
      # впасти на вже-неможливому confirm!.
      it "still returns the actuator to idle when the command can no longer confirm" do
        command.update_column(:status, :failed)

        expect { described_class.new.perform(command.id) }.not_to raise_error

        expect(actuator.reload.state).to eq("idle")
        expect(command.reload.status).to eq("failed")
      end

      # Пін на ЦІЛЬ, не лише на факт виклику: усі специ цієї поверхні асертили
      # `have_received(:broadcast_replace_to)` без таргета — саме тому промах
      # `actuator_card_{id}` замість `actuator_{id}` прожив місяці (UI.4).
      #
      # [UI.4/I18N.2] Тепер пін тримає ОБИДВІ осі, бо кожна ламається окремо:
      # ЦІЛЬ — turbo-frame (`command_status_frame_{id}`), а не бейдж усередині;
      # СТРІМ — вузький `[actuator, :commands]`, а не голий `Organization`, якого
      # не слухала жодна сторінка.
      it "broadcasts to the actuator-scoped stream, targeting the frame" do
        described_class.new.perform(command.id)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
          .with([ command.actuator, :commands ],
                hash_including(target: "command_status_frame_#{command.id}")).once
      end

      # Payload мусить лишатись locale-ВІЛЬНИМ: заглушка зі `src`, нуль перекладеної
      # прози. Без цього піна міграція класу 2 могла б тихо відкотитись назад до
      # рендеру бейджа в процесі-продюсера.
      it "ships a locale-free stub, not the translated badge" do
        described_class.new.perform(command.id)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
          .with(anything, hash_including(html: /turbo-frame[^>]+src=/)).once
      end
    end

    context "when actuator is not active" do
      let(:command) do
        silence_side_effects!(:actuator_dispatch)
        cmd = create(:actuator_command, actuator: actuator, status: :acknowledged)
        cmd.update_column(:status, :acknowledged)
        cmd
      end

      it "does not reset actuator but confirms acknowledged command" do
        actuator.update_column(:state, :maintenance_needed)

        described_class.new.perform(command.id)

        command.reload
        expect(command.status).to eq("confirmed")
        expect(actuator.reload.state).to eq("maintenance_needed")
      end

      it "skips confirmation if command is not acknowledged" do
        actuator.update_column(:state, :idle)
        command.update_column(:status, :failed)

        described_class.new.perform(command.id)

        command.reload
        expect(command.status).to eq("failed")
      end
    end

    # [ARCH.58] Під poll-семантикою кілька наказів на один актуатор видаються
    # підряд, кожен переозброює власний Reset — і найстаріший таймер приходить
    # ПЕРШИМ. Без гарду він обривав вікно найновішого.
    describe "наказ, витіснений пізнішим" do
      let(:superseded) do
        silence_side_effects!(:actuator_dispatch)
        cmd = create(:actuator_command, actuator: actuator, duration_seconds: 60)
        cmd.update_columns(status: ActuatorCommand.statuses[:acknowledged], sent_at: 10.minutes.ago)
        cmd
      end

      let!(:newer) do
        silence_side_effects!(:actuator_dispatch)
        cmd = create(:actuator_command, actuator: actuator, duration_seconds: 60)
        cmd.update_columns(status: ActuatorCommand.statuses[:acknowledged], sent_at: 1.minute.ago)
        cmd
      end

      it "НЕ закриває актуатор — вікном володіє пізніший наказ" do
        described_class.new.perform(superseded.id)

        expect(actuator.reload.state).to eq("active")
      end

      it "все одно закриває САМ витіснений наказ" do
        described_class.new.perform(superseded.id)

        expect(superseded.reload.status).to eq("confirmed")
      end

      it "власник вікна закриває актуатор, коли надходить його черга" do
        described_class.new.perform(newer.id)

        expect(actuator.reload.state).to eq("idle")
      end

      # Рівні мітки — не «пізніший». При включному порівнянні кожен вважав би
      # одне одного витісненим, і актуатор не закрив би ЖОДЕН.
      it "однакові sent_at не роблять накази взаємно витісненими" do
        newer.update_columns(sent_at: superseded.sent_at)

        described_class.new.perform(superseded.id)

        expect(actuator.reload.state).to eq("idle")
      end
    end

    it "returns early when command not found" do
      allow(Rails.logger).to receive(:warn).with(/не знайдено/)

      described_class.new.perform(-1)

      expect(Rails.logger).to have_received(:warn).with(/не знайдено/)
    end
  end
end
