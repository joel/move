# frozen_string_literal: true

namespace :images do
  desc "Regenerate missing display variants for all Media (v0.71 hotfix)"
  task regenerate: :environment do
    total_count = 0
    error_count = 0
    warmed_count = 0

    puts "Regenerating variants for all Media across all tenants..."

    Apartment::Tenant.each do |tenant|
      next if tenant == "public"

      Apartment::Tenant.switch(tenant) do
        media_list = Media.joins(:image_attachment).distinct
        media_count = media_list.count
        puts "\n[#{tenant}] Found #{media_count} media"

        media_list.find_each do |media|
          total_count += 1
          next unless media.image.attached?

          result = MediaVariants::Prewarm.call(media)
          warmed_count += result
          print "."
        rescue StandardError => e # rubocop:disable Move/BroadRescue -- backfill task best-effort
          error_count += 1
          puts "\nERROR media #{media.id}: #{e.class} #{e.message}"
        end
      end
    end

    puts "\n\n✓ Regeneration complete"
    puts "  Total media processed: #{total_count}"
    puts "  Variants warmed: #{warmed_count}/#{total_count * 2}"
    puts "  Errors: #{error_count}"
  end
end
