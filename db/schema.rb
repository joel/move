# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_03_160000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "posts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "user_email_auth_keys", id: :uuid, default: nil, force: :cascade do |t|
    t.datetime "deadline", null: false
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "key", null: false
  end

  create_table "user_omniauth_identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "provider", null: false
    t.string "uid", null: false
    t.uuid "user_id", null: false
    t.index ["provider", "uid"], name: "idx_omniauth_identities_uniqueness", unique: true
    t.index ["user_id"], name: "index_user_omniauth_identities_on_user_id"
  end

  create_table "user_remember_keys", id: :uuid, default: nil, force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
  end

  create_table "user_verification_keys", id: :uuid, default: nil, force: :cascade do |t|
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "key", null: false
    t.datetime "requested_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "user_webauthn_keys", primary_key: ["user_id", "webauthn_id"], force: :cascade do |t|
    t.datetime "last_use", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "name", limit: 80
    t.string "public_key", null: false
    t.integer "sign_count", null: false
    t.uuid "user_id", null: false
    t.string "webauthn_id", null: false
    t.index ["user_id"], name: "index_user_webauthn_keys_on_user_id"
  end

  create_table "user_webauthn_user_ids", id: :uuid, default: nil, force: :cascade do |t|
    t.string "webauthn_id", null: false
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "name"
    t.integer "roles_mask", default: 0, null: false
    t.integer "status", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true, where: "(status = ANY (ARRAY[1, 2]))"
  end

  add_foreign_key "posts", "users"
  add_foreign_key "user_email_auth_keys", "users", column: "id", on_delete: :cascade
  add_foreign_key "user_omniauth_identities", "users", on_delete: :cascade
  add_foreign_key "user_remember_keys", "users", column: "id", on_delete: :cascade
  add_foreign_key "user_verification_keys", "users", column: "id", on_delete: :cascade
  add_foreign_key "user_webauthn_keys", "users", on_delete: :cascade
  add_foreign_key "user_webauthn_user_ids", "users", column: "id", on_delete: :cascade
end
