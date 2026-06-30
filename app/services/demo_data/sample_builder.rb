# frozen_string_literal: true

# Loads the demo catalog (boxes / photos / recorded recognition / manual items).
# It lives in db/ (the committed seed assets sit beside it) and is not autoloaded,
# so require it by absolute path. Both the dev seed (db/seeds.rb) and the runtime
# sample provisioner (DemoData::Provision) build through this one module, so the
# offline demo content stays in lockstep.
require Rails.root.join("db/seed_data/catalog").to_s

module DemoData
  # Builds a Move's contents — boxes, photos with replayed recognition + items, and
  # photo-less manual items — from the committed SeedData catalog, WITHOUT any AI
  # call (recognition is replayed from db/seed_data/recognition/*.json, images from
  # db/seed_images/*.jpg). Pass `box_numbers:` to build a curated subset (the signup
  # sample uses ~6 boxes); nil builds the whole catalog (the dev showcase seed).
  #
  # Idempotent: boxes are keyed on number, a box's photos are skipped once it has any
  # media, and manual items are keyed on name — so a re-run never duplicates.
  # The Move, its memberships and rooms are the caller's responsibility (Moves::Create
  # / Moves::DefaultVocabularies); this only fills the Move with belongings.
  class SampleBuilder
    def self.call(move:, box_numbers: nil)
      new(move, box_numbers).call
    end

    def initialize(move, box_numbers)
      @move = move
      @box_numbers = box_numbers && Array(box_numbers).map(&:to_s)
    end

    def call
      build_boxes
      build_photos_and_items
      build_manual_items
      index_items
      @move
    end

    private

    def included?(number)
      @box_numbers.nil? || @box_numbers.include?(number.to_s)
    end

    def rooms
      @rooms ||= @move.rooms.index_by(&:name)
    end

    def build_boxes
      SeedData::BOXES.each do |attrs|
        next unless included?(attrs[:number])

        backfill_box(upsert_box(attrs), attrs)
      end
    end

    def upsert_box(attrs)
      length, width, height, weight = attrs[:dims]
      @move.boxes.find_or_create_by!(number: attrs[:number]) do |b|
        b.qr_token = SecureRandom.urlsafe_base64(16)
        b.room = attrs[:room] && rooms[attrs[:room]]
        b.status = attrs[:status]
        b.description = attrs[:desc]
        b.length_cm = length
        b.width_cm = width
        b.height_cm = height
        b.weight_kg = weight
        b.fragile = attrs[:fragile] || false
      end
    end

    # Backfill onto a box seeded before a field existed (the create block runs once).
    def backfill_box(box, attrs)
      box.update!(description: attrs[:desc]) if attrs[:desc].present? && box.description.blank?
      box.update!(fragile: true) if attrs[:fragile] && !box.fragile?
    end

    def build_photos_and_items
      threshold = @move.auto_confirm_threshold.to_f
      photos_by_included_box.each do |box_number, photos|
        box = @move.boxes.find_by(number: box_number)
        next unless box&.media&.none?

        photos.each { |photo| build_photo(box, photo, threshold) }
      end
    end

    def photos_by_included_box
      SeedData::PHOTOS.group_by { |photo| photo[:box] }
                      .select { |box_number, _| included?(box_number) }
    end

    def build_photo(box, photo, threshold)
      recorded = photo[:status] == "succeeded" ? SeedData.recorded_recognition(photo[:slug]) : nil
      run_attrs = {
        move: @move, media: nil,
        provider: recorded&.dig("provider") || photo[:provider],
        provider_model: recorded&.dig("provider_model") || photo[:provider_model],
        started_at: 1.minute.ago, completed_at: Time.current
      }
      media = attach_media(box, photo)
      run_attrs[:media] = media

      if photo[:status] == "failed"
        box.recognition_runs.create!(run_attrs.merge(
                                       status: "failed", error_code: photo[:error_code],
                                       error_message: photo[:error_message]
                                     ))
        return
      end

      materialize_items(box, media, photo, run_attrs, threshold)
    end

    def attach_media(box, photo)
      media = box.media.new(
        move: @move, media_type: "image", captured_via: "web",
        captured_at: photo[:captured_at].seconds.ago
      )
      media.image.attach(SeedData.image_attachable(photo[:slug]))
      media.save!
      media
    end

    def materialize_items(box, media, photo, run_attrs, threshold)
      detections = SeedData.detections_for(photo, threshold: threshold)
      presence = photo[:presence] || "in_box"
      run = box.recognition_runs.create!(run_attrs.merge(
                                           status: "succeeded",
                                           metadata: { "item_count" => detections.size,
                                                       "provider" => run_attrs[:provider] }
                                         ))
      detections.each do |attrs|
        suggestion = run.recognition_suggestions.create!(
          move: @move, box: box, media: media, proposed_name: attrs[:name],
          confidence_score: attrs[:confidence],
          state: attrs[:review] == "auto_confirmed" ? "auto_accepted" : "pending"
        )
        item = box.items.create!(
          move: @move, source_media: media, source_recognition_suggestion_id: suggestion.id,
          name: attrs[:name], confidence_score: attrs[:confidence], created_via: "recognition",
          review_state: attrs[:review], presence_state: presence
        )
        suggestion.update!(item: item)
      end
    end

    def build_manual_items
      SeedData::MANUAL_ITEMS.each do |attrs|
        next unless included?(attrs[:box])

        box = @move.boxes.find_by(number: attrs[:box])
        next unless box

        item = box.items.find_or_initialize_by(name: attrs[:name])
        next unless item.new_record?

        item.assign_attributes(
          move: @move, created_via: "manual",
          review_state: attrs[:review], presence_state: attrs[:presence]
        )
        item.save!
      end
    end

    # Build the hybrid-search projection for every item synchronously (no background
    # worker runs during provisioning). The fake embedder is deterministic and makes
    # no network call, so search works the moment the sample appears.
    def index_items
      @move.items.includes(box: :room).find_each do |item|
        Search::RefreshDocument.new.call(item: item)
      end
    end
  end
end
