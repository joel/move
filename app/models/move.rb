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
  # Search embeddings are per-Move bring-your-own-key too (#232/#237). `fake` is
  # the network-free default (token-hashed pseudo-vectors); the real providers
  # each conform their native vector to the fixed 1536-d column (Base#fit_dimensions).
  # OpenAI/Gemini reuse the same key as recognition; Voyage is search-only (its own
  # key — Anthropic has no embeddings API, so Anthropic stays recognition-only).
  EMBEDDING_PROVIDERS = %w[fake openai gemini voyage].freeze
  REAL_EMBEDDING_PROVIDERS = (EMBEDDING_PROVIDERS - %w[fake]).freeze
  # Every provider that holds an encrypted key — the union of the real recognition
  # and embedding providers. The shared "AI Capability" panel manages exactly these
  # (#242); a key entered once powers whichever features list that provider.
  PROVIDER_KEYS = (REAL_RECOGNITION_PROVIDERS | REAL_EMBEDDING_PROVIDERS).freeze

  # Per-Move provider API keys, encrypted at rest (ActiveRecord::Encryption — keys
  # in credentials.active_record_encryption). Never tracked by Logidze (its
  # include-list excludes them), never rendered back (write-only in the UI).
  encrypts :openai_api_key, :anthropic_api_key, :gemini_api_key, :voyage_api_key

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
  # G-search — whole-Move re-embedding passes, for live indexing progress (#239).
  has_many :indexing_runs, dependent: :destroy
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
  validates :embedding_provider, inclusion: { in: EMBEDDING_PROVIDERS }
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

  # This Move's stored key for any key-holding +provider+ (recognition or
  # embedding), or nil for an unknown/keyless one. Used by the shared AI Capability
  # panel + its key actions (#242), which are vendor- rather than feature-scoped.
  def api_key_for(provider)
    return nil unless PROVIDER_KEYS.include?(provider.to_s)

    public_send("#{provider}_api_key").presence
  end

  # The features a stored +provider+ key powers, for the AI Capability badges.
  def provider_powers(provider)
    powers = []
    powers << :recognition if REAL_RECOGNITION_PROVIDERS.include?(provider.to_s)
    powers << :search if REAL_EMBEDDING_PROVIDERS.include?(provider.to_s)
    powers
  end

  # This Move's stored key for the search-embedding +provider+, or nil for
  # fake/unknown (which need no key). OpenAI/Gemini reuse the recognition key
  # columns; Voyage has its own. Used by EmbeddingProviders.for_move (#237).
  def embedding_api_key_for(provider)
    return nil unless REAL_EMBEDDING_PROVIDERS.include?(provider.to_s)

    public_send("#{provider}_api_key").presence
  end

  # Whether semantic search can run as configured: only when a real provider is
  # selected AND this Move has that provider's own key (strict BYO — never a
  # shared key). Otherwise EmbeddingProviders.for_move hands back the network-free
  # Fake embedder and search degrades gracefully to lexical + trigram (#232/#237).
  def embedding_provider_ready?
    embedding_api_key_for(embedding_provider).present?
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
