# frozen_string_literal: true

FactoryBot.define do
  factory :naas_contract do
    organization
    cluster
    total_funding { 50_000 }
    start_date { 1.month.ago }
    end_date { 11.months.from_now }
    status { :active }
  end
end
