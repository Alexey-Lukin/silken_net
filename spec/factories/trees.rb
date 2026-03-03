# frozen_string_literal: true

FactoryBot.define do
  factory :tree do
    sequence(:did) { |n| "SNET-%08X" % n }
    latitude { 49.4285 }
    longitude { 32.0620 }
    status { :active }
    tree_family
    cluster
  end
end
