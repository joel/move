# frozen_string_literal: true

FactoryBot.define do
  factory :item_cluster do
    move
    sequence(:leader_key) { |n| "cluster #{n}" }
    label { "Cluster" }
    embedding_model { "fake-embed-1" }
  end

  factory :item_cluster_membership do
    item_cluster
    item
  end
end
