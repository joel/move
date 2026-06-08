# frozen_string_literal: true

FactoryBot.define do
  factory :item_search_document do
    item
    move { item.move }
    search_text { "Coffee maker kitchen" }

    # A deterministic embedding for semantic specs.
    trait :embedded do
      embedding { Array.new(1536) { 0.01 } }
      embedding_model { "fake-1" }
      embedded_at { Time.current }
    end

    # Item#after_commit already auto-creates a search_document, so upsert the
    # existing row instead of inserting a duplicate (one-doc-per-item).
    to_create do |doc|
      record = ItemSearchDocument.find_or_initialize_by(item_id: doc.item_id)
      record.assign_attributes(
        move_id: doc.move_id, search_text: doc.search_text,
        embedding: doc.embedding, embedding_model: doc.embedding_model, embedded_at: doc.embedded_at
      )
      record.save!
      doc.id = record.id
      doc.instance_variable_set(:@new_record, false)
    end
  end
end
