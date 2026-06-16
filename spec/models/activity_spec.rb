# frozen_string_literal: true

require "rails_helper"

RSpec.describe Activity do
  let(:move) { create(:move) }

  def activity(occurred_at:)
    described_class.create!(
      move:, action: "box.created", source: :web,
      subject_type: "Box", subject_id: SecureRandom.uuid, occurred_at:
    )
  end

  # #194 — the keyset cursor must carry id, not just occurred_at: cascade ops emit
  # several events with the same timestamp, so a time-only cursor would drop every
  # row sharing the page boundary.
  describe ".before (keyset pagination)" do
    it "walks every row across pages even when timestamps tie at the boundary" do
      t = ->(sec) { Time.utc(2026, 1, 1, 12, 0, sec) }
      all = [activity(occurred_at: t.call(2)),
             activity(occurred_at: t.call(1)),
             activity(occurred_at: t.call(1)), # ties with the previous row
             activity(occurred_at: t.call(0))]

      page = ->(cur) { described_class.where(move:).recent.before(*cur).limit(2).to_a }
      p1 = page.call([nil])
      p2 = page.call([p1.last.occurred_at, p1.last.id])

      expect((p1 + p2).map(&:id).uniq).to match_array(all.map(&:id))
    end

    it "returns the unfiltered relation when the cursor time is nil" do
      activity(occurred_at: Time.utc(2026, 1, 1))

      expect(described_class.where(move:).before(nil)).to eq([described_class.last])
    end
  end
end
