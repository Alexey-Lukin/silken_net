# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class GatewayBlueprint < Blueprinter::Base
  identifier :id

  fields :uid, :state, :last_seen_at, :latitude, :longitude
end
