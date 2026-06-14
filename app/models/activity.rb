# frozen_string_literal: true

# One append-only entry in a Move's activity feed (Technical Foundation §8.2).
# Written by Activity::RecordSubscriber from a domain event; never updated or
# destroyed (the log is immutable). Rendering reads `action` + `metadata` and
# resolves the (possibly discarded) subject lazily — nothing here is denormalized
# into English, so the feed stays i18n-driven via ActivityPresenter.
class Activity < ApplicationRecord
  belongs_to :move
  # subject is polymorphic and optional; it may be discarded (resolve with
  # with_discarded at the call site), so there is no belongs_to scope reliance.
  belongs_to :subject, polymorphic: true, optional: true

  enum :source, { web: 0, mcp: 1, system: 2 }

  validates :action, :occurred_at, presence: true

  # Newest first; id breaks ties when several events share a timestamp.
  scope :recent, -> { order(occurred_at: :desc, id: :desc) }
  # The default feed hides low-signal reads (manifest views, QR scans, summary
  # views); they remain queryable for an "everything" toggle.
  scope :high_signal, -> { where(low_signal: false) }
  scope :before, ->(time) { where(occurred_at: ...time) if time }

  # Immutable: the log is append-only.
  def readonly?
    persisted?
  end
end
