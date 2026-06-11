# frozen_string_literal: true

# Reclaims Active Storage blobs reserved by a Direct Upload presign
# (MoveMcp::Tools::CreateMediaUpload, #110) but never attached — e.g. the client
# never completed the PUT or never called add_media_to_box. Scheduled daily (see
# config/recurring.yml). Blobs are Apartment-excluded (shared `public` schema),
# so one run covers every Organization.
#
# RETENTION protects in-flight uploads: a presign should be consumed within
# minutes, so a day-old still-unattached blob is abandoned.
class PurgeAbandonedUploadsJob < ApplicationJob
  RETENTION = 1.day

  def perform
    ActiveStorage::Blob.unattached
                       .where(created_at: ..RETENTION.ago)
                       .find_each(&:purge_later)
  end
end
