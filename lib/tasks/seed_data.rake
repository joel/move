# frozen_string_literal: true

namespace :seed_data do
  desc "Refresh BOTH recorded demo artifacts (images + recognition) from real, " \
       "paid runs, then re-seed. One-off: OPENAI_API_KEY set. Review + commit the " \
       "results so plain `db:seed` replays them for free."
  task refresh: :environment do
    puts "[seed_data:refresh] 1/2 generating images (gpt-image-1)…"
    Rake::Task["seed_images:generate"].invoke
    puts "[seed_data:refresh] 2/2 recording recognition (gpt-5-mini)…"
    Rake::Task["seed_recognition:record"].invoke
    puts "[seed_data:refresh] done. Review + commit db/seed_images/ and " \
         "db/seed_data/recognition/, then run `bin/rails db:seed`."
  end
end
