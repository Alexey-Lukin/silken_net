# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "open3"

# [SEC.3] Factory Flashing — subprocess executor with dry-run default.
#
# In `dry_run: true` mode (default for this iteration) Executor only prints
# each command to the configured IO. Real subprocess spawning requires
# `dry_run: false` plus a STM32_Programmer_CLI binary in PATH; otherwise it
# raises immediately rather than silently skipping writes.
#
# Captured per-command stdout/stderr/exit-status is exposed via #results so
# callers (Session) can persist a transcript in AuditLog metadata.
module FactoryFlashing
  class Executor
    Result = Struct.new(:command, :stdout, :stderr, :status, keyword_init: true)

    class ProgrammerMissingError < StandardError; end
    class CommandFailedError < StandardError; end

    attr_reader :results

    def initialize(dry_run: true, io: $stdout, programmer_path: nil)
      @dry_run = dry_run
      @io = io
      @programmer_path = programmer_path
      @results = []
    end

    def dry_run?
      @dry_run
    end

    # @param commands [Array<String>]
    def run(commands)
      ensure_programmer_available! unless dry_run?
      commands.each { |cmd| execute_single(cmd) }
      results
    end

    private

    def execute_single(command)
      if dry_run?
        @io.puts("[dry-run] #{command}")
        @results << Result.new(command: command, stdout: "", stderr: "", status: nil)
        return
      end

      stdout, stderr, status = Open3.capture3(command)
      result = Result.new(command: command, stdout: stdout, stderr: stderr, status: status.exitstatus)
      @results << result
      return if status.success?

      raise CommandFailedError, "exit=#{status.exitstatus} cmd=#{command} stderr=#{stderr.strip}"
    end

    def ensure_programmer_available!
      bin = @programmer_path || CommandBuilder::PROGRAMMER
      return if self.class.programmer_available?(bin)

      raise ProgrammerMissingError,
            "#{bin} not found in PATH — install STM32CubeProgrammer CLI or run with dry_run: true"
    end

    # Class-level probe so specs can stub it without violating RSpec/SubjectStub
    # (stubbing the subject under test). Returns true if the binary is in PATH.
    # Pure-Ruby lookup avoids shelling out (no command injection surface).
    def self.programmer_available?(bin)
      return false if bin.nil? || bin.empty?

      if bin.include?(File::SEPARATOR) || (File::ALT_SEPARATOR && bin.include?(File::ALT_SEPARATOR))
        return File.file?(bin) && File.executable?(bin)
      end

      exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(File::PATH_SEPARATOR) : [ "" ]
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        exts.any? do |ext|
          candidate = File.join(dir, "#{bin}#{ext}")
          File.file?(candidate) && File.executable?(candidate)
        end
      end
    end
  end
end
