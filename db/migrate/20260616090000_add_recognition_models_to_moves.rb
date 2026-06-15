# frozen_string_literal: true

# Per-Move Recognition model override (#187, follow-up to #185). Each provider
# adapter ships a hardcoded DEFAULT_MODEL; these columns let an admin override it
# per Move, per provider (accuracy/cost/speed). Nullable with no default — nil
# means "use the adapter's DEFAULT_MODEL". Plaintext (model names are not secret,
# unlike *_api_key), so NOT encrypted and NOT tracked by the Logidze trigger.
class AddRecognitionModelsToMoves < ActiveRecord::Migration[8.1]
  def change
    change_table :moves, bulk: true do |t|
      t.string :openai_model
      t.string :anthropic_model
      t.string :gemini_model
    end
  end
end
