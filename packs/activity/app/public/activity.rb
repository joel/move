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
  # Keyset cursor matching `recent`'s (occurred_at DESC, id DESC) ordering. The
  # `id` half is essential: cascade ops emit several events with the same
  # occurred_at, so a time-only cursor (`occurred_at < t`) would drop every row
  # sharing the page-boundary timestamp (#194). The tuple comparison advances past
  # exactly the last row seen. `id` is cast to uuid so the bound string compares.
  scope :before, lambda { |time, id = nil|
    next self if time.nil?

    where("(occurred_at, id) < (?, ?::uuid)", time, id)
  }

  # Immutable: the log is append-only.

  #: () -> bool
  def readonly?
    persisted?
  end
end
