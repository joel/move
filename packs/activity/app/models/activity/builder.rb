# frozen_string_literal: true

class Activity
  # Translates a Rails.event domain event into Activity attributes (or nil to skip).
  # Knows which events are worth recording and how to find each one's subject; the
  # payload is otherwise normalised generically (actor key, source, kept metadata)
  # so adding an event is a one-line table entry, not a new method.
  class Builder
    # event name => [subject model name, payload key holding its id].
    SUBJECTS = {
      "box.created" => ["Box", :box_id], "box.updated" => ["Box", :box_id],
      "box.status_changed" => ["Box", :box_id], "box.deleted" => ["Box", :box_id],
      "box.restored" => ["Box", :box_id],
      "item.created" => ["Item", :item_id], "item.updated" => ["Item", :item_id],
      "item.moved" => ["Item", :item_id], "item.removed" => ["Item", :item_id],
      "item.restored" => ["Item", :item_id], "item.deleted" => ["Item", :item_id],
      "item.undeleted" => ["Item", :item_id],
      "media.captured" => ["Media", :media_id],
      "media.moved" => ["Media", :media_id],
      "media.discarded" => ["Media", :media_id], "media.undiscarded" => ["Media", :media_id],
      "media.retaken" => ["Media", :media_id],
      "move.created" => ["Move", :move_id],
      "move.unit_system_changed" => ["Move", :move_id],
      "move.auto_confirm_threshold_changed" => ["Move", :move_id],
      "move.recognition_provider_changed" => ["Move", :move_id],
      "move.recognition_model_changed" => ["Move", :move_id],
      "move.provider_key_set" => ["Move", :move_id],
      "move.provider_key_removed" => ["Move", :move_id],
      "move.embedding_provider_changed" => ["Move", :move_id],
      "move.labels_per_box_changed" => ["Move", :move_id],
      "move_membership.added" => ["Move", :move_id],
      "move_membership.role_changed" => ["Move", :move_id],
      "move_membership.removed" => ["Move", :move_id],
      "integration_token.created" => ["Move", :move_id],
      "integration_token.revoked" => ["Move", :move_id],
      "manifest.viewed" => ["Box", :box_id], "qr.resolved" => ["Box", :box_id],
      "move.summary_viewed" => ["Move", :move_id]
    }.freeze
    # Vocabulary events resolve their subject from the `kind` segment.
    VOCAB = %w[vocabulary.created vocabulary.updated vocabulary.removed].freeze
    VOCAB_MODELS = { "room" => "Room" }.freeze
    # Reads that should not clutter the default feed (kept behind a filter).
    LOW_SIGNAL = %w[manifest.viewed qr.resolved move.summary_viewed].freeze
    # First present key wins — payloads name the actor inconsistently.
    ACTOR_KEYS = %i[actor_id editor_id creator_id created_by_id mover_id captured_by_id].freeze
    # Payload keys preserved in metadata (drives the rendered summary/diff).
    META_KEYS = %i[to to_box_id created_via unit_system auto_confirm_threshold role
                   user_id kind detached_count detached_item_count discard_batch_id
                   token_name provider model labels_per_box].freeze

    # Whether the subscriber should bother building this event at all.

    # @rbs skip
    def self.records?(name)
      SUBJECTS.key?(name) || VOCAB.include?(name)
    end

    #: (untyped event) -> void
    def initialize(event)
      @name = event[:name]
      @payload = (event[:payload] || {}).symbolize_keys
    end

    # Returns the Activity attribute hash, or nil to skip (no mapping / no Move).

    #: () -> Hash[Symbol, untyped]?
    def call
      return nil unless self.class.records?(@name)

      move_id = @payload[:move_id]
      return nil if move_id.nil?

      subject_type, subject_id = subject
      {
        move_id:, actor_id:, action: @name,
        subject_type:, subject_id:, metadata:, source:,
        low_signal: LOW_SIGNAL.include?(@name), occurred_at: Time.current
      }
    end

    private

    #: () -> Array[untyped]
    def subject
      if VOCAB.include?(@name)
        [VOCAB_MODELS[@payload[:kind].to_s], @payload[:record_id]]
      else
        type, key = SUBJECTS[@name]
        [type, @payload[key]]
      end
    end

    #: () -> untyped
    def actor_id
      ACTOR_KEYS.filter_map { |k| @payload[k] }.first
    end

    #: () -> Hash[Symbol, untyped]
    def metadata
      META_KEYS.each_with_object({}) do |key, acc|
        value = @payload[key]
        acc[key] = value unless value.nil?
      end
    end

    #: () -> String
    def source
      (@payload[:source] || Current.source || :web).to_s
    end
  end
end
