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

ActiveRecord::Schema[8.1].define(version: 2026_05_21_130504) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.text "justification"
    t.uuid "requested_by_id"
    t.uuid "role_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
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

  create_table "approval_decisions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_id", null: false
    t.uuid "approval_step_id", null: false
    t.uuid "approver_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "decision", null: false
    t.datetime "updated_at", null: false
    t.index ["access_id"], name: "index_approval_decisions_on_access_id"
    t.index ["approval_step_id"], name: "index_approval_decisions_on_approval_step_id"
    t.index ["approver_id"], name: "index_approval_decisions_on_approver_id"
  end

  create_table "approval_steps", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "approval_workflow_id", null: false
    t.uuid "approver_user_id"
    t.datetime "created_at", null: false
    t.uuid "fallback_user_id", null: false
    t.integer "position", null: false
    t.string "strategy", null: false
    t.datetime "updated_at", null: false
    t.index ["approval_workflow_id", "position"], name: "index_approval_steps_on_approval_workflow_id_and_position", unique: true
    t.index ["approval_workflow_id"], name: "index_approval_steps_on_approval_workflow_id"
    t.index ["approver_user_id"], name: "index_approval_steps_on_approver_user_id"
    t.index ["fallback_user_id"], name: "index_approval_steps_on_fallback_user_id"
  end

  create_table "approval_workflows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.boolean "protected", default: false, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_approval_workflows_on_slug", unique: true
  end

  create_table "audit_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_display"
    t.uuid "actor_id"
    t.string "actor_type", null: false
    t.jsonb "attribute_changes"
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

  create_table "auth_providers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "claim_mappings", default: [], null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.string "oidc_client_id", null: false
    t.string "oidc_client_secret"
    t.string "oidc_issuer_url", null: false
    t.string "oidc_scope", default: "openid email profile", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_auth_providers_on_enabled"
    t.index ["slug"], name: "index_auth_providers_on_slug", unique: true
  end

  create_table "emergency_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.uuid "issued_by_id"
    t.text "reason", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.uuid "user_id", null: false
    t.index ["issued_by_id"], name: "index_emergency_tokens_on_issued_by_id"
    t.index ["token_digest"], name: "index_emergency_tokens_on_token_digest", unique: true
    t.index ["user_id", "used_at"], name: "index_emergency_tokens_on_user_id_and_used_at"
    t.index ["user_id"], name: "index_emergency_tokens_on_user_id"
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

  create_table "omniauth_identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "auth_provider_id", null: false
    t.datetime "created_at", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["auth_provider_id", "subject"], name: "index_omniauth_identities_on_auth_provider_id_and_subject", unique: true
    t.index ["auth_provider_id"], name: "index_omniauth_identities_on_auth_provider_id"
    t.index ["user_id"], name: "index_omniauth_identities_on_user_id"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.uuid "approval_workflow_id"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.boolean "protected", default: false, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["application_id", "slug"], name: "index_roles_on_application_id_and_slug", unique: true
    t.index ["application_id"], name: "index_roles_on_application_id"
    t.index ["approval_workflow_id"], name: "index_roles_on_approval_workflow_id"
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
  add_foreign_key "accesses", "users", column: "requested_by_id"
  add_foreign_key "approval_decisions", "accesses"
  add_foreign_key "approval_decisions", "approval_steps"
  add_foreign_key "approval_decisions", "users", column: "approver_id"
  add_foreign_key "approval_steps", "approval_workflows"
  add_foreign_key "approval_steps", "users", column: "approver_user_id"
  add_foreign_key "approval_steps", "users", column: "fallback_user_id"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "emergency_tokens", "users"
  add_foreign_key "emergency_tokens", "users", column: "issued_by_id"
  add_foreign_key "external_identities", "users"
  add_foreign_key "omniauth_identities", "auth_providers"
  add_foreign_key "omniauth_identities", "users"
  add_foreign_key "roles", "applications"
  add_foreign_key "roles", "approval_workflows"
  add_foreign_key "users", "users", column: "manager_id"
end
