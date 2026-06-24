# frozen_string_literal: true

# A managed item tag scoped to a Move (Domain §4.12 / D5). Tags are a
# selection-only vocabulary, joined to items via item_tags; the picker offers
# only existing names. D7 adds admin management + the applies-to facet (which
# records can carry the tag — metadata for now; box-tagging is future). Lives in
# the tenant schema.
class Tag < ApplicationRecord
  # Field-level history (Logidze) over `name` and `applies_to` — powers the
  # activity feed's rename revert (PR3).
  has_logidze
  APPLIES_TO = %w[item box both].freeze

  belongs_to :move
  has_many :item_tags, dependent: :destroy
  has_many :items, through: :item_tags

  validates :name, presence: true
  validates :name, uniqueness: { scope: :move_id, case_sensitive: false }
  validates :applies_to, inclusion: { in: APPLIES_TO }

  scope :ordered, -> { order(:name) }

  # Most-used first, then alphabetical — so the tags a Move actually applies are
  # quickest to reach in the item picker (#337). Unused tags stay selectable (you
  # must be able to apply a not-yet-used tag, and a fresh Move has none used),
  # they just sort last. Usage is counted in SQL via a correlated subquery (no
  # GROUP BY, so the relation still behaves like a normal one for the view's
  # any?/each; AGENTS.md §1 #5). Joins `items` and filters `discarded_at IS NULL`
  # so a tag left only on soft-deleted inventory doesn't rank as in-use (Item's
  # `default_scope { kept }` doesn't reach a raw subquery). Both tables are
  # per-tenant — no schema prefix.
  scope :by_usage, lambda {
    order(
      Arel.sql(
        "(SELECT COUNT(*) FROM item_tags " \
        "JOIN items ON items.id = item_tags.item_id " \
        "WHERE item_tags.tag_id = tags.id AND items.discarded_at IS NULL) DESC"
      ),
      :name
    )
  }

  # Tags assignable to items. Box-only tags are excluded — the applies-to facet
  # governs which records can carry a tag, and box tagging is not built yet
  # (D7). Item pickers and item tag resolution scope through this.
  scope :for_items, -> { where(applies_to: %w[item both]) }
end
