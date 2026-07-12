# frozen_string_literal: true

# The shared single-use-token scheme (#608): a 256-bit urlsafe-base64 raw value
# shown to the holder exactly once, with only its SHA-256 hex digest persisted —
# so a leaked row can never be replayed. Third adopter (MoveInvitation) turned
# the two hand-copied methods on SessionHandoffToken and MoveIntegrationToken
# into this concern; the generate/digest pair must never drift per-model.
module DigestedToken
  extend ActiveSupport::Concern

  class_methods do
    # Generate a fresh raw token. Returned to the caller once; never stored.
    def generate_raw_token
      SecureRandom.urlsafe_base64(32)
    end

    # SHA-256 hex digest of a raw token — persisted on mint, recomputed on
    # lookup for a single indexed query (not a per-row compare).
    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token.to_s)
    end
  end
end
