# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    module Codex
      class RealmsController < BaseController
        # GET /api/v1/codex/realms
        # Returns all 4 active realms with node counters. Cached briefly to
        # absorb sidebar/landing-page traffic without DB pressure.
        def index
          realms = policy_scope(::Codex::Realm).ordered.to_a
          authorize ::Codex::Realm
          counts = ::Codex::Node
                     .where(codex_realm_id: realms.map(&:id))
                     .group(:codex_realm_id)
                     .count

          respond_to do |format|
            format.json do
              render json: {
                data: ::Codex::RealmBlueprint.render_as_hash(realms, nodes_counts: counts)
              }
            end
            format.html do
              render_dashboard(
                title: "Codex · Realms",
                component: ::Codex::RealmTabs.new(realms: realms, nodes_counts: counts)
              )
            end
          end
        end
      end
    end
  end
end
