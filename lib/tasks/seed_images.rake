# frozen_string_literal: true

namespace :seed_images do
  desc "Generate the demo seed photos (1:1 per item) via OpenAI gpt-image-1 into " \
       "db/seed_images/. One-off: run with OPENAI_API_KEY set, then commit the JPEGs."
  task generate: :environment do
    require "net/http"
    require "json"
    require "base64"
    require "stringio"
    require Rails.root.join("db/seed_data/catalog").to_s

    api_key = ENV["OPENAI_API_KEY"].presence
    abort "[seed_images] OPENAI_API_KEY is not set" unless api_key

    endpoint = URI("https://api.openai.com/v1/images/generations")
    model    = ENV["SEED_IMAGE_MODEL"].presence || "gpt-image-1"
    size     = ENV["SEED_IMAGE_SIZE"].presence || "1024x1024"
    quality  = ENV["SEED_IMAGE_QUALITY"].presence || "medium"
    force    = ENV["FORCE"].present?
    out_dir  = Rails.root.join("db/seed_images")
    out_dir.mkpath

    # POST the prompt to the Images API and return the raw image bytes. gpt-image-1
    # always answers with base64 (no URL option), so decode data[0].b64_json. A
    # non-2xx raises with the vendor message (status + message only — never the key).
    request_image = lambda do |prompt|
      req = Net::HTTP::Post.new(endpoint)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"]  = "application/json"
      req.body = { model: model, prompt: prompt, n: 1, size: size,
                   quality: quality, output_format: "jpeg" }.to_json
      res = Net::HTTP.start(
        endpoint.host, endpoint.port, use_ssl: true, open_timeout: 10, read_timeout: 180
      ) { |http| http.request(req) }
      body = begin
        JSON.parse(res.body)
      rescue JSON::ParserError
        {}
      end
      raise "image request failed (#{res.code}): #{body.dig("error", "message") || "HTTP #{res.code}"}" unless res.code.to_i.between?(200, 299)

      b64 = body.dig("data", 0, "b64_json")
      raise "image request returned no image data" if b64.blank?

      Base64.decode64(b64)
    end

    # Downscale to a small, bounded JPEG so the committed seed image stays tiny
    # (~30-80KB). Mirrors ImageNormalizer but to a 512px long edge for thumbnails.
    # Degrades to the raw bytes (already JPEG) when libvips is unavailable.
    optimize = lambda do |bytes|
      require "vips"
      img = Vips::Image.new_from_buffer(bytes, "", access: :sequential).autorot
      scale = 512.0 / [img.width, img.height].max
      img = img.resize(scale) if scale < 1.0
      img = img.flatten(background: 255) if img.has_alpha?
      img.jpegsave_buffer(Q: 80, strip: true)
    rescue LoadError
      warn "[seed_images] libvips unavailable — writing full-size image for this slug"
      bytes
    end

    generated = 0
    skipped   = 0
    failed    = 0
    SeedData::PHOTOS.each do |photo|
      target = out_dir.join("#{photo[:slug]}.jpg")
      if target.exist? && !force
        skipped += 1
        next
      end

      begin
        bytes = request_image.call(photo[:prompt])
        target.binwrite(optimize.call(bytes))
        generated += 1
        line = "[seed_images] #{photo[:slug]} -> #{target.relative_path_from(Rails.root)} " \
               "(#{ActiveSupport::NumberHelper.number_to_human_size(target.size)})"
        Rails.logger.info(line)
        puts line
      rescue StandardError => e # rubocop:disable Move/BroadRescue -- one bad slug must not strand the rest of a paid batch
        failed += 1
        warn "[seed_images] FAILED #{photo[:slug]}: #{e.class} (#{e.message})"
      end
    end

    summary = "[seed_images] done: #{generated} generated, #{skipped} skipped (exists), #{failed} failed. " \
              "Review db/seed_images/, then commit and run `bin/rails db:seed`."
    Rails.logger.info(summary)
    puts summary
    abort "[seed_images] #{failed} image(s) failed" if failed.positive?
  end
end
