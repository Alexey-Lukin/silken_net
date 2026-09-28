# SPDX-License-Identifier: AGPL-3.0-or-later
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

    # Дані `-w32` — ключі зі справжнього master key, а dry-run — дефолт factory:execute:
    # план показує адресу й кількість слів, не самі слова.
    it "prints each command with a [dry-run] prefix, -w32 data redacted, and does not spawn" do
      allow(Open3).to receive(:capture3)
      executor.run(commands)
      expect(Open3).not_to have_received(:capture3)
      expect(io.string.lines.map(&:chomp)).to eq([
        "[dry-run] STM32_Programmer_CLI -c port=SWD",
        "[dry-run] STM32_Programmer_CLI -w32 0x0803E000 <1 words>"
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
      allow(Open3).to receive(:capture3).and_return([ "OK", "", ok_status ])
      executor.run(commands)
      expect(Open3).to have_received(:capture3).twice
      expect(executor.results.map(&:stdout)).to eq([ "OK", "OK" ])
    end

    it "raises CommandFailedError and stops on the first non-zero exit" do
      allow(described_class).to receive(:programmer_available?).and_return(true)
      ok = instance_double(Process::Status, success?: true, exitstatus: 0)
      bad = instance_double(Process::Status, success?: false, exitstatus: 7)
      allow(Open3).to receive(:capture3).and_return(
        [ "OK", "", ok ],
        [ "", "device locked", bad ]
      )
      expect { executor.run(commands) }
        .to raise_error(described_class::CommandFailedError, /exit=7.*device locked/)
      expect(Open3).to have_received(:capture3).twice
      expect(executor.results.size).to eq(2)
    end

    # Session персистить повідомлення в provisioning_sessions.error_message, а
    # дані `-w32` — це ключі: туди йде лише адреса й кількість слів.
    it "keeps -w32 data (key words) out of the error message" do
      allow(described_class).to receive(:programmer_available?).and_return(true)
      bad = instance_double(Process::Status, success?: false, exitstatus: 7)
      allow(Open3).to receive(:capture3).and_return([ "", "Error: Data mismatch", bad ])
      cmd = "STM32_Programmer_CLI -c port=SWD mode=UR -w32 0x0803E000 0x4B45594C 0x01234567 0x89ABCDEF 0xFFFFFFFF"

      expect { executor.run([ cmd ]) }.to raise_error(described_class::CommandFailedError) { |error|
        expect(error.message).to include("-w32 0x0803E000 <4 words>")
        expect(error.message).not_to include("0x01234567")
      }
    end

    # CLI може відлунити дані у stderr (verify, помилка аргументу) — маскується кожне 8-hex-слово.
    it "masks hex words the CLI echoes into stderr" do
      allow(described_class).to receive(:programmer_available?).and_return(true)
      bad = instance_double(Process::Status, success?: false, exitstatus: 7)
      allow(Open3).to receive(:capture3).and_return([ "", "Error: expected 0x01234567, found 89ABCDEF", bad ])

      expect { executor.run([ "STM32_Programmer_CLI -c port=SWD mode=UR -w32 0x0803E000 0x4B45594C" ]) }
        .to raise_error(described_class::CommandFailedError) { |error|
          expect(error.message).to include("stderr=Error: expected <hex>, found <hex>")
        }
    end
  end

  # The run/execute specs above stub .programmer_available?; these exercise the
  # real pure-Ruby PATH probe so its branches (nil/empty, explicit path, PATH
  # search, PATHEXT) are covered without shelling out.
  describe ".programmer_available?" do
    it "returns false for a nil binary name" do
      expect(described_class.programmer_available?(nil)).to be(false)
    end

    it "returns false for an empty binary name" do
      expect(described_class.programmer_available?("")).to be(false)
    end

    context "with an explicit path (contains a separator)" do
      it "returns true for an existing executable file" do
        expect(described_class.programmer_available?("/bin/sh")).to be(true)
      end

      it "returns false when the path does not exist" do
        expect(described_class.programmer_available?("/nonexistent/dir/stm32prog")).to be(false)
      end
    end

    context "with a bare name (PATH search)" do
      it "returns true when the binary resolves on PATH" do
        original_path = ENV["PATH"]
        begin
          Dir.mktmpdir do |dir|
            exe = File.join(dir, "stm32prog")
            File.write(exe, "#!/bin/sh\n")
            File.chmod(0o755, exe)
            ENV["PATH"] = dir
            expect(described_class.programmer_available?("stm32prog")).to be(true)
          end
        ensure
          ENV["PATH"] = original_path
        end
      end

      it "returns false when no PATH entry contains the binary" do
        expect(described_class.programmer_available?("nonexistent-stm32-binary-xyz")).to be(false)
      end

      it "honours PATHEXT extensions when set (Windows-style probing)" do
        original_path = ENV["PATH"]
        original_pathext = ENV["PATHEXT"]
        begin
          Dir.mktmpdir do |dir|
            exe = File.join(dir, "stm32prog.EXE")
            File.write(exe, "#!/bin/sh\n")
            File.chmod(0o755, exe)
            ENV["PATH"] = dir
            ENV["PATHEXT"] = ".EXE"
            expect(described_class.programmer_available?("stm32prog")).to be(true)
          end
        ensure
          ENV["PATH"] = original_path
          ENV["PATHEXT"] = original_pathext
        end
      end
    end
  end
end
