# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeAbandonedUploadsJob do
  def blob(name)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("bytes-#{name}"), filename: name)
  end

  it "purges old unattached blobs but keeps recent and attached ones" do
    old_abandoned = blob("old.bin").tap { |b| b.update!(created_at: 2.days.ago) }
    recent_pending = blob("recent.bin") # just reserved — in-flight
    attached = create(:media).image.blob.tap { |b| b.update!(created_at: 2.days.ago) }

    described_class.new.perform # purge_later runs inline in test

    expect(ActiveStorage::Blob.exists?(old_abandoned.id)).to be(false)
    expect(ActiveStorage::Blob.exists?(recent_pending.id)).to be(true)
    expect(ActiveStorage::Blob.exists?(attached.id)).to be(true)
  end
end
