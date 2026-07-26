# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# INF.24 drift guard. The Akash `signedBy.anyOf` auditor address gates audited bids — a corrupt
# one (INF.24 shipped a 43-char string that failed bech32-checksum) means ZERO audited bids on the
# first deploy (deploy-availability failure, silent: bids just don't arrive). bech32 is offline-
# checkable, so a copy-typo (wrong length / bad char) fails CI, not deploy-day. This validates
# length+prefix+charset (the INF.24 slip was 43-vs-44 length); full polymod-checksum is over-
# engineering for a static address that already has an on-chain backstop (`akash query audit`, the
# 👤-checkbox). Covers static SDL + the tf-var default + the tfvars example (all committed).
RSpec.describe "Akash signedBy auditor addresses are valid bech32 (INF.24)" do # rubocop:disable RSpec/DescribeClass
  # akash1 (HRP + separator) + 38 data/checksum chars from the bech32 charset = 44 total.
  # Charset excludes 1/b/i/o (the INF.24 corruption dropped a char → 43).
  let(:addresses) do
    %w[
      deploy/akash/deploy.yaml
      terraform/akash/variables.tf
      terraform/akash/terraform.tfvars.example
    ].flat_map { |p| File.read(Rails.root.join(p)).scan(/akash1[0-9a-z]+/) }.uniq
  end

  it "finds at least one committed auditor address (guard is not vacuous)" do
    expect(addresses).not_to be_empty
  end

  it "every committed akash1 address is valid bech32 (akash1 + 38 charset chars = 44)" do
    invalid = addresses.reject { |a| a.match?(/\Aakash1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{38}\z/) }
    expect(invalid).to be_empty,
                       "corrupt Akash auditor address (bad length/charset → zero audited bids, INF.24): " \
                       "#{invalid.map { |a| "#{a} (#{a.length} chars)" }.join(', ')}"
  end
end
