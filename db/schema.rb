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

ActiveRecord::Schema[8.1].define(version: 2026_05_12_092627) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "department"
    t.string "email", null: false
    t.date "end_date"
    t.uuid "manager_id"
    t.string "name", null: false
    t.date "start_date"
    t.string "status", default: "pending_start", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true, where: "((status)::text <> 'terminated'::text)"
    t.index ["manager_id"], name: "index_users_on_manager_id"
    t.index ["status"], name: "index_users_on_status"
  end

  add_foreign_key "users", "users", column: "manager_id"
end
