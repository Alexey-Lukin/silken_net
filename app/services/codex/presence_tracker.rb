# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::PresenceTracker — Redis-backed observer registry.
#
# Goal: the Discovery hook in `TelemetryUnpackerService` should fire only
# when at least one user is *actively observing* the tree (e.g. has its
# Show page open). Otherwise we'd spawn a Sidekiq job per packet × per
# user × per tree — and we'd evaluate rules against an audience of zero.
#
# Storage: a Redis Set per tree under `codex:presence:tree:<tree_id>`
# whose members are user_ids. The set has a TTL of 10 min — refreshed
# on every `touch` from the user's browser (e.g. via a Stimulus
# heartbeat that beats every 60 s while the page is visible).
#
# Why a Set (not a Sorted Set with timestamps): we don't need per-user
# TTL granularity; the Sidekiq fan-out is cheap, and a stale 9-minute
# observer just gets one Discovery probe that's almost certainly a no-op
# at the Engine level. Simplicity > precision.
#
# Reliability: every method rescues a Redis outage and returns a safe
# default (empty/false) so a Redis hiccup never blocks `uplink` queue.
module Codex
  class PresenceTracker
    PREFIX = "codex:presence:tree:"
    TTL    = 10.minutes

    def self.touch(user_id:, tree_id:)
      return false if user_id.blank? || tree_id.blank?

      r = redis
      key = key_for(tree_id)
      r.sadd(key, user_id.to_s)
      r.expire(key, TTL.to_i)
      true
    rescue StandardError => e
      Rails.logger.warn "[Codex::PresenceTracker] touch failed: #{e.class}: #{e.message}"
      false
    end

    def self.leave(user_id:, tree_id:)
      return false if user_id.blank? || tree_id.blank?

      redis.srem(key_for(tree_id), user_id.to_s)
      true
    rescue StandardError
      false
    end

    # @return [Array<Integer>]
    def self.observers_for_tree(tree_id)
      return [] if tree_id.blank?

      redis.smembers(key_for(tree_id)).map(&:to_i).reject(&:zero?)
    rescue StandardError
      []
    end

    def self.observed?(tree_id)
      observers_for_tree(tree_id).any?
    end

    def self.redis
      Kredis.redis(config: :shared)
    end

    def self.key_for(tree_id)
      "#{PREFIX}#{tree_id}"
    end

    private_class_method :redis, :key_for
  end
end
