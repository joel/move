# frozen_string_literal: true

# Removes the scaffold-leftover `posts` table. Reversible: the block mirrors the
# original `create_posts` columns so `down` recreates an equivalent table.
class DropPosts < ActiveRecord::Migration[8.1]
  def change
    drop_table :posts, id: :uuid do |t|
      t.string :title
      t.text :body
      t.references :user, null: false, type: :uuid, foreign_key: true

      t.timestamps
    end
  end
end
