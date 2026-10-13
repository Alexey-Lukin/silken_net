# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActuatorCommandWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:gateway) { create(:gateway, cluster: cluster, ip_address: "192.168.1.100") }
  let(:actuator) { create(:actuator, gateway: gateway) }

  # Пригнічуємо after_commit :dispatch_to_edge!, щоб не тригерити Phlex-компоненти
  let(:command) do
    silence_side_effects!(:actuator_dispatch)
    cmd = create(:actuator_command, actuator: actuator, expires_at: 30.minutes.from_now)
    cmd.update_column(:status, :issued)
    cmd
  end

  before { allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) }

  # Push-доставки наказу немає: Королева вхідного слухача не має, а retry-хук такої джоби
  # fail!'ив би наказ ДО першого poll'а (FW.60). Пін тримає це за побудовою — і заміняє
  # колишні `not_to have_received(:perform_async)` у викликачів, які без джоби вакуумні.
  it "is not a Sidekiq job — CMD delivery is the Queen's poll, never a push" do
    expect(described_class.ancestors).not_to include(Sidekiq::Job)
    expect(described_class).not_to respond_to(:perform_async)
  end

  describe ".broadcast_command_state_static" do
    it "replaces the command's status frame on the actuator's commands stream" do
      described_class.broadcast_command_state_static(command)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        [ actuator, :commands ],
        hash_including(target: Actuators::CommandStatusFrame.dom_id(command.id))
      )
    end

    it "swallows a cable failure — UI decoration must not lose the command" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "cable down")
      allow(Rails.logger).to receive(:warn)

      expect { described_class.broadcast_command_state_static(command) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/broadcast не пройшов для наказу ##{command.id}: cable down/)
    end
  end
end
