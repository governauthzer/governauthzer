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

ActiveRecord::Schema[8.1].define(version: 2026_05_20_084028) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "approved_at"
    t.uuid "approved_by_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.text "justification"
    t.uuid "requested_by_id"
    t.uuid "role_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["approved_by_id"], name: "index_accesses_on_approved_by_id"
    t.index ["requested_by_id"], name: "index_accesses_on_requested_by_id"
    t.index ["role_id"], name: "index_accesses_on_role_id"
    t.index ["status"], name: "index_accesses_on_status"
    t.index ["user_id", "role_id"], name: "index_accesses_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_accesses_on_user_id"
  end

  create_table "applications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_applications_on_slug", unique: true
  end

  create_table "audit_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_display"
    t.uuid "actor_id"
    t.string "actor_type", null: false
    t.jsonb "changes"
    t.uuid "correlation_id", null: false
    t.string "event_type", null: false
    t.inet "ip_address"
    t.text "justification"
    t.jsonb "metadata"
    t.datetime "occurred_at", null: false
    t.string "schema_version", default: "1.0", null: false
    t.jsonb "targets", default: [], null: false
    t.text "user_agent"
    t.index ["actor_id", "occurred_at"], name: "index_audit_events_on_actor_id_and_occurred_at"
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["correlation_id"], name: "index_audit_events_on_correlation_id"
    t.index ["event_type"], name: "index_audit_events_on_event_type"
    t.index ["occurred_at"], name: "index_audit_events_on_occurred_at", order: :desc
    t.index ["targets"], name: "index_audit_events_on_targets", opclass: :jsonb_path_ops, using: :gin
  end

  create_table "external_identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["source", "external_id"], name: "index_external_identities_on_source_and_external_id", unique: true
    t.index ["user_id"], name: "index_external_identities_on_user_id"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.boolean "protected", default: false, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["application_id", "slug"], name: "index_roles_on_application_id_and_slug", unique: true
    t.index ["application_id"], name: "index_roles_on_application_id"
  end

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

  add_foreign_key "accesses", "roles"
  add_foreign_key "accesses", "users"
  add_foreign_key "accesses", "users", column: "approved_by_id"
  add_foreign_key "accesses", "users", column: "requested_by_id"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "external_identities", "users"
  add_foreign_key "roles", "applications"
  add_foreign_key "users", "users", column: "manager_id"
end
