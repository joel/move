# frozen_string_literal: true

# A relocation project. Moves live inside a tenant (Organization) schema, so
# there is no organization_id column — the active Apartment schema *is* the
# tenant. `created_by` and members reference public.users across schemas via
# AR associations (no database foreign key).
#
# State transitions and membership creation belong in app/actions, not here.
class Move < ApplicationRecord
  # Field-level history (Logidze) over the editable settings (name, unit_system,
  # auto_confirm_threshold) — powers the activity feed's revert (PR3).
  has_logidze
  STATUSES = %w[planned started finished archived].freeze
  UNIT_SYSTEMS = %w[metric imperial].freeze
  # Recognition is per-Move bring-your-own-key (#185). `fake` is the network-free
  # default (no key, canned detections); the rest require this Move's own key.
  RECOGNITION_PROVIDERS = %w[fake openai anthropic gemini].freeze
  REAL_RECOGNITION_PROVIDERS = (RECOGNITION_PROVIDERS - %w[fake]).freeze

  # Per-Move provider API keys, encrypted at rest (ActiveRecord::Encryption — keys
  # in credentials.active_record_encryption). Never tracked by Logidze (its
  # include-list excludes them), never rendered back (write-only in the UI).
  encrypts :openai_api_key, :anthropic_api_key, :gemini_api_key

  belongs_to :created_by, class_name: "User"
  has_many :move_memberships, dependent: :destroy
  has_many :users, through: :move_memberships
  has_many :rooms, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :boxes, dependent: :destroy
  has_many :media, dependent: :destroy
  has_many :recognition_runs, dependent: :destroy
  has_many :recognition_suggestions, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :integration_tokens, class_name: "MoveIntegrationToken", dependent: :destroy
  # G1 — append-only activity feed entries (Technical Foundation §8.2).
  has_many :activities, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :unit_system, inclusion: { in: UNIT_SYSTEMS }
  validates :auto_confirm_threshold,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :recognition_provider, inclusion: { in: RECOGNITION_PROVIDERS }
  # Free-text model overrides (#187): any string the provider accepts. Kept
  # permissive so a brand-new model works the day it ships — the cap just guards
  # against junk. Blank = use the adapter's DEFAULT_MODEL.
  validates :openai_model, :anthropic_model, :gemini_model,
            length: { maximum: 100 }, allow_blank: true

  # This Move's stored key for +provider+, or nil for fake/unknown (which need no
  # key). Used by RecognitionProviders.for_move to configure the adapter.
  def recognition_api_key_for(provider)
    return nil unless REAL_RECOGNITION_PROVIDERS.include?(provider.to_s)

    public_send("#{provider}_api_key").presence
  end

  # This Move's stored model override for +provider+, or nil to fall back to the
  # adapter's DEFAULT_MODEL. Used by RecognitionProviders.for_move (#187).
  def recognition_model_for(provider)
    return nil unless REAL_RECOGNITION_PROVIDERS.include?(provider.to_s)

    public_send("#{provider}_model").presence
  end

  # Whether recognition can run as configured: fake always can; a real provider
  # needs this Move's own key (strict BYO — never falls back to a shared key).
  def recognition_ready?
    return true if recognition_provider == "fake"

    recognition_api_key_for(recognition_provider).present?
  end

  def archived?
    status == "archived"
  end

  def writable?
    !archived?
  end

  # The membership joining +user+ to this Move, or nil if they are not a
  # member. Used by MovePolicy/BoxPolicy to gate reads and mutations on
  # move-level role (D11).
  def membership_for(user)
    return nil if user.nil?

    move_memberships.find_by(user_id: user.id)
  end
end
