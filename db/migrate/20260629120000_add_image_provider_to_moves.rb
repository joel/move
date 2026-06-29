# frozen_string_literal: true

# Per-Move image-generation provider (#416, mirrors recognition #185 / embeddings
# #232). The opt-in "✨ generate image" action for photo-less manual items builds
# its adapter from this column + the Move's own key — strict BYO, no shared/ENV
# key. Defaults to "openai": image generation has one real provider, so a Move
# that already holds an OpenAI key (for recognition/search) can generate without
# any extra setup, while a Move without a key simply never shows the affordance.
# There is NO new key column — generation reuses the existing encrypted
# openai_api_key. The demo seed flips this to "fake" to showcase the flow keylessly.
class AddImageProviderToMoves < ActiveRecord::Migration[8.1]
  def change
    add_column :moves, :image_provider, :string, null: false, default: "openai"
  end
end
