# frozen_string_literal: true

# The append-only activity log behind the Activity Feed Wall (Technical
# Foundation §8.2). One row per recorded domain event, written synchronously by
# Activity::RecordSubscriber. Lives in the tenant schema (Move-scoped, no
# organization_id). `subject` is polymorphic with no FK (it may already be
# discarded); `actor_id` references public.users across schemas, so no FK either.
class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities, id: :uuid do |t|
      t.references :move, type: :uuid, null: false, foreign_key: true
      t.uuid :actor_id # public.users, cross-schema — no FK
      t.string :action, null: false
      t.string :subject_type
      t.uuid :subject_id
      t.jsonb :metadata, null: false, default: {}
      t.integer :source, null: false, default: 0 # web:0, mcp:1, system:2
      t.boolean :low_signal, null: false, default: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    # Feed query: newest-first within a Move (id breaks ties on equal timestamps).
    add_index :activities, %i[move_id occurred_at id], order: { occurred_at: :desc, id: :desc }
    # Reverse lookup: "what happened to this record".
    add_index :activities, %i[subject_type subject_id]
  end
end
