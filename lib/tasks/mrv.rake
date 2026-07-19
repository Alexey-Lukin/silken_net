# frozen_string_literal: true

namespace :mrv do
  desc "ISO lineage-bundle (ARCH.12/MRV.1): mrv:lineage_bundle[org_id,from_iso,to_iso] → JSON на stdout"
  task :lineage_bundle, [ :organization_id, :from, :to ] => :environment do |_t, args|
    org = Organization.find(args.fetch(:organization_id))
    from = Time.iso8601(args.fetch(:from))
    to = Time.iso8601(args.fetch(:to))

    puts JSON.pretty_generate(Mrv::LineageReportService.call(organization: org, from: from, to: to))
  end
end
