# frozen_string_literal: true

namespace :seed_recognition do
  desc "Record REAL recognition output over the generated seed photos into " \
       "db/seed_data/recognition/<slug>.json (one-off; OPENAI_API_KEY set). " \
       "db:seed replays these so reseeding never re-pays for vision tokens."
  task record: :environment do
    require "json"
    require Rails.root.join("db/seed_data/catalog").to_s

    api_key = ENV["OPENAI_API_KEY"].presence
    abort "[seed_recognition] OPENAI_API_KEY is not set" unless api_key

    model = ENV["SEED_RECOGNITION_MODEL"].presence || RecognitionProviders::Openai::DEFAULT_MODEL
    provider = RecognitionProviders.resolve("openai", api_key: api_key, model: model)
    force = ENV["FORCE"].present?
    out_dir = Rails.root.join("db/seed_data/recognition")
    out_dir.mkpath

    # The demo's vocabularies, fed to the model as context so it fits detections
    # into the same categories/tags the seed uses (it may still propose new ones).
    categories = Moves::DefaultVocabularies::CATEGORIES
    item_tags = Moves::DefaultVocabularies::TAGS.reject { |_name, applies| applies == "box" }.keys + ["Everyday Use"]
    room_for = SeedData::BOXES.to_h { |box| [box[:number], box[:room]] }

    # Minimal stand-in for an ActiveStorage attachment: the provider's
    # #encoded_image only calls #download and #content_type, so no blob/storage
    # is needed to record. Struct readers supply both (no method defs in the task);
    # #download is constructed with the committed seed JPEG bytes.
    image_stub = Struct.new(:download, :content_type)

    recordable = SeedData::PHOTOS.select { |photo| photo[:status] == "succeeded" }
    generated = 0
    skipped = 0
    failed = 0
    recordable.each do |photo|
      target = out_dir.join("#{photo[:slug]}.json")
      image_path = Rails.root.join("db/seed_images/#{photo[:slug]}.jpg")
      if target.exist? && !force
        skipped += 1
        next
      end
      unless image_path.exist?
        warn "[seed_recognition] no image for #{photo[:slug]} — run seed_images:generate first; skipping"
        skipped += 1
        next
      end

      begin
        result = provider.identify(
          image: image_stub.new(image_path.binread, "image/jpeg"),
          context: { room: room_for[photo[:box]], categories: categories, tags: item_tags }
        )
        objects = result.objects.map do |object|
          { "label" => object.label, "confidence" => object.confidence, "count" => object.count,
            "category" => object.category, "tags" => object.tags }
        end
        target.write("#{JSON.pretty_generate(
          "slug" => photo[:slug], "provider" => result.provider,
          "provider_model" => result.provider_model, "objects" => objects
        )}\n")
        generated += 1
        line = "[seed_recognition] #{photo[:slug]}: #{objects.size} objects -> " \
               "#{target.relative_path_from(Rails.root)}"
        Rails.logger.info(line)
        puts line
      rescue StandardError => e # rubocop:disable Move/BroadRescue -- one bad slug must not strand a paid batch
        failed += 1
        warn "[seed_recognition] FAILED #{photo[:slug]}: #{e.class} (#{e.message})"
      end
    end

    summary = "[seed_recognition] done: #{generated} recorded, #{skipped} skipped, #{failed} failed. " \
              "Review db/seed_data/recognition/, commit, then `bin/rails db:seed`."
    Rails.logger.info(summary)
    puts summary
    abort "[seed_recognition] #{failed} recording(s) failed" if failed.positive?
  end
end
