# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

namespace :mrv do
  desc "ISO lineage-bundle (ARCH.12/MRV.1): mrv:lineage_bundle[org_id,from_iso,to_iso] → JSON на stdout"
  task :lineage_bundle, [ :organization_id, :from, :to ] => :environment do |_t, args|
    org = Organization.find(args.fetch(:organization_id))
    # Без зони Time.iso8601 бере ЛОКАЛЬНИЙ час сервера — межі ISO-звіту тихо
    # «пливуть» на TZ (fable №2); вимагаємо явну зону.
    from_s, to_s = args.fetch(:from), args.fetch(:to)
    [ from_s, to_s ].each do |s|
      abort "iso8601 З зоною обовʼязково (…Z або ±HH:MM): #{s.inspect}" unless s.match?(/(Z|[+-]\d{2}:?\d{2})\z/)
    end
    from = Time.iso8601(from_s)
    to = Time.iso8601(to_s)

    puts JSON.pretty_generate(Mrv::LineageReportService.call(organization: org, from: from, to: to))
  end
end
