# rbs_rails configuration — schema-derived model signatures.
# See doc/project/type-checking.md; regenerate with `bin/rails rbs_rails:all`.
RbsRails.configure do |config|
  config.signature_root_dir = "sig/rbs_rails"

  # Engine models (ActiveStorage) generate ENVIRONMENT-DEPENDENT output paths —
  # rbs_rails derives them from the model's source location, which is the gem
  # install dir (vendor/bundle in CI, the system gem dir in the dev container),
  # so their generated sigs can never be freshness-stable. Their constants come
  # from the community activestorage sigs instead; the AR query surface the
  # community sigs lack is bridged in sig/rails_gaps.rbs.
  config.ignore_model_if do |klass|
    klass.name.to_s.start_with?("ActiveStorage::")
  end
end
