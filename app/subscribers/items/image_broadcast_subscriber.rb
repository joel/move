# frozen_string_literal: true

module Items
  # Pushes the box-contents card live as image generation resolves (#416), the
  # same ActionCable / Turbo Stream mechanism as the capture panel (#241). The
  # GenerateImageJob emits item.image_generated / item.image_generation_failed;
  # this re-renders just that item's ItemCard and replaces it on the box's
  # contents stream — placeholder/generating → image, or → a retryable failed
  # state — without a reload.
  class ImageBroadcastSubscriber
    EVENTS = %w[item.image_generated item.image_generation_failed].freeze

    def emit(event)
      return unless EVENTS.include?(event[:name])

      item_id = event[:payload]&.dig(:item_id)
      return if item_id.blank?

      item = Item.includes(:move, :box, source_media: { image_attachment: :blob }).find_by(id: item_id)
      return if item.nil?

      broadcast(item, failed: event[:name] == "item.image_generation_failed")
    end

    private

    # Runs synchronously inside GenerateImageJob (it emits the events) under the
    # job's restored tenant, so the signed box stream + the card render resolve.
    # A broadcast failure must never propagate (it would fail the job): isolate it
    # — worst case is a missed live swap that a reload corrects.
    def broadcast(item, failed:)
      # editable: false — one HTML payload reaches every box subscriber regardless
      # of role, so it must never carry a mutating affordance (a viewer would see a
      # dead "generate" button). The success card has an image (no button anyway);
      # after a failure an editor reloads to get the retry button back.
      Turbo::StreamsChannel.broadcast_replace_to(
        item.box, :contents,
        target: Components::Boxes::ItemCard.dom_id(item),
        html: ApplicationController.render(
          Components::Boxes::ItemCard.new(
            item: item, move: item.move, editable: false,
            image_ready: item.move.image_generation_ready?, failed: failed
          ),
          layout: false
        )
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 broadcast must not break the emitting job
      Rails.logger.warn("[items] image card broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
