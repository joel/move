# frozen_string_literal: true

# Per-Move Recognition provider configuration (#185). Moves recognition from a
# single app-wide ENV setting to per-Move bring-your-own-key:
#   - recognition_provider: which adapter is active for this Move. Defaults to
#     "fake" (network-free, no key) so existing Moves never silently bill a shared
#     account after the cutover — an admin must opt into a real provider + key.
#   - *_api_key: the Move's own provider key, encrypted at rest via
#     ActiveRecord::Encryption (Move#encrypts). Stored as text — ciphertext is
#     longer than the raw key. NOT tracked by the Logidze trigger (its include-list
#     stays {name, unit_system, auto_confirm_threshold}), so no key ever lands in
#     log_data.
class AddRecognitionProviderToMoves < ActiveRecord::Migration[8.1]
  def change
    change_table :moves, bulk: true do |t|
      t.string :recognition_provider, null: false, default: "fake"
      t.text :openai_api_key
      t.text :anthropic_api_key
      t.text :gemini_api_key
    end
  end
end
