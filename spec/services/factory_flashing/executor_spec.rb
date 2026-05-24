# frozen_string_literal: true

require "rails_helper"

RSpec.describe FactoryFlashing::Executor do
  let(:io) { StringIO.new }
  let(:commands) do
    [
      "STM32_Programmer_CLI -c port=SWD",
      "STM32_Programmer_CLI -w32 0x0803E000 0x4B45594C"
    ]
  end

  describe "dry-run (default)" do
    subject(:executor) { described_class.new(io: io) }

    it "is dry_run? by default" do
      expect(executor.dry_run?).to be true
    end

    it "prints each command with a [dry-run] prefix and does not spawn" do
      expect(Open3).not_to receive(:capture3)
      executor.run(commands)
      expect(io.string.lines.map(&:chomp)).to eq([
        "[dry-run] STM32_Programmer_CLI -c port=SWD",
        "[dry-run] STM32_Programmer_CLI -w32 0x0803E000 0x4B45594C"
      ])
    end

    it "captures empty stdout/stderr/status results" do
      executor.run(commands)
      expect(executor.results.size).to eq(2)
      expect(executor.results.first.status).to be_nil
      expect(executor.results.first.stdout).to eq("")
    end
  end

  describe "execute mode" do
    subject(:executor) { described_class.new(io: io, dry_run: false) }

    it "raises ProgrammerMissingError when STM32_Programmer_CLI is not in PATH" do
      allow(described_class).to receive(:programmer_available?).and_return(false)
      expect { executor.run(commands) }
        .to raise_error(described_class::ProgrammerMissingError, /STM32_Programmer_CLI not found/)
    end

    it "spawns each command via Open3.capture3 when programmer is present" do
      allow(described_class).to receive(:programmer_available?).and_return(true)
      ok_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      expect(Open3).to receive(:capture3).twice.and_return([ "OK", "", ok_status ])
      executor.run(commands)
      expect(executor.results.map(&:stdout)).to eq([ "OK", "OK" ])
    end

    it "raises CommandFailedError and stops on the first non-zero exit" do
      allow(described_class).to receive(:programmer_available?).and_return(true)
      ok = instance_double(Process::Status, success?: true, exitstatus: 0)
      bad = instance_double(Process::Status, success?: false, exitstatus: 7)
      expect(Open3).to receive(:capture3).twice.and_return(
        [ "OK", "", ok ],
        [ "", "device locked", bad ]
      )
      expect { executor.run(commands) }
        .to raise_error(described_class::CommandFailedError, /exit=7.*device locked/)
      expect(executor.results.size).to eq(2)
    end
  end
end
