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

ActiveRecord::Schema[8.1].define(version: 2026_08_30_090001) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "last_used_at"
    t.string "plugin_name"
    t.json "provenance"
    t.integer "publisher_id"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_hint", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["publisher_id"], name: "index_api_tokens_on_publisher_id"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.boolean "public", default: false, null: false
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["public", "created_at"], name: "index_audit_events_on_public_and_created_at"
    t.index ["subject_type", "subject_id"], name: "index_audit_events_on_subject"
    t.index ["user_id"], name: "index_audit_events_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "hidden_at"
    t.integer "plugin_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["plugin_id", "created_at"], name: "index_comments_on_plugin_id_and_created_at"
    t.index ["plugin_id"], name: "index_comments_on_plugin_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "daily_downloads", force: :cascade do |t|
    t.integer "count", default: 0, null: false
    t.date "date", null: false
    t.integer "plugin_version_id", null: false
    t.index ["plugin_version_id", "date"], name: "index_daily_downloads_on_plugin_version_id_and_date", unique: true
    t.index ["plugin_version_id"], name: "index_daily_downloads_on_plugin_version_id"
  end

  create_table "device_authorizations", force: :cascade do |t|
    t.integer "api_token_id"
    t.datetime "created_at", null: false
    t.string "device_code_digest", null: false
    t.datetime "expires_at", null: false
    t.string "plugin_name"
    t.integer "publisher_id"
    t.string "requested_plugin_name"
    t.string "requested_publisher_name"
    t.integer "status", default: 0, null: false
    t.string "token_ciphertext"
    t.integer "token_kind", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "user_code", null: false
    t.integer "user_id"
    t.index ["api_token_id"], name: "index_device_authorizations_on_api_token_id"
    t.index ["device_code_digest"], name: "index_device_authorizations_on_device_code_digest", unique: true
    t.index ["publisher_id"], name: "index_device_authorizations_on_publisher_id"
    t.index ["user_code"], name: "index_device_authorizations_on_user_code", unique: true
    t.index ["user_id"], name: "index_device_authorizations_on_user_id"
  end

  create_table "login_codes", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.string "code", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "code"], name: "index_login_codes_on_user_id_and_code"
    t.index ["user_id"], name: "index_login_codes_on_user_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.boolean "founding", default: false, null: false
    t.integer "publisher_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["publisher_id", "user_id"], name: "index_memberships_on_publisher_id_and_user_id", unique: true
    t.index ["publisher_id"], name: "index_memberships_on_publisher_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "passkeys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname"
    t.string "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "plugin_versions", force: :cascade do |t|
    t.integer "api_token_id"
    t.datetime "approved_at"
    t.integer "approved_by_id"
    t.json "capability_fingerprint"
    t.datetime "created_at", null: false
    t.integer "downloads_count", default: 0, null: false
    t.datetime "hold_until"
    t.string "license"
    t.json "manifest", null: false
    t.string "min_omarchy_version"
    t.integer "plugin_id", null: false
    t.json "provenance"
    t.datetime "published_at"
    t.text "review_notes"
    t.json "scan_results"
    t.string "sha256", null: false
    t.integer "size_bytes", null: false
    t.integer "state", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "version", null: false
    t.string "version_sort_key", null: false
    t.string "yank_reason"
    t.datetime "yanked_at"
    t.index ["api_token_id"], name: "index_plugin_versions_on_api_token_id"
    t.index ["approved_by_id"], name: "index_plugin_versions_on_approved_by_id"
    t.index ["plugin_id", "version"], name: "index_plugin_versions_on_plugin_id_and_version", unique: true
    t.index ["plugin_id"], name: "index_plugin_versions_on_plugin_id"
    t.index ["user_id"], name: "index_plugin_versions_on_user_id"
  end

  create_table "plugins", force: :cascade do |t|
    t.string "category"
    t.integer "comments_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "downloads_count", default: 0, null: false
    t.string "homepage_url"
    t.json "kinds", default: [], null: false
    t.string "latest_version"
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.json "preview_meta", default: {}, null: false
    t.integer "publisher_id", null: false
    t.integer "ratings_count", default: 0, null: false
    t.integer "ratings_sum", default: 0, null: false
    t.text "readme"
    t.json "repo_stats", default: {}, null: false
    t.datetime "repo_stats_synced_at"
    t.string "repository_url"
    t.integer "state", default: 0, null: false
    t.string "summary"
    t.json "tags", default: [], null: false
    t.datetime "updated_at", null: false
    t.integer "views_count", default: 0, null: false
    t.index ["category"], name: "index_plugins_on_category"
    t.index ["normalized_name"], name: "index_plugins_on_normalized_name"
    t.index ["publisher_id", "name"], name: "index_plugins_on_publisher_id_and_name", unique: true
    t.index ["publisher_id"], name: "index_plugins_on_publisher_id"
  end

  create_table "publishers", force: :cascade do |t|
    t.text "bio"
    t.boolean "claimed", default: true, null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "seed_source_url"
    t.datetime "suspended_at"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false, null: false
    t.string "website"
    t.index ["name"], name: "index_publishers_on_name", unique: true
    t.index ["normalized_name"], name: "index_publishers_on_normalized_name", unique: true
  end

  create_table "ratings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "plugin_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "value", null: false
    t.index ["plugin_id", "user_id"], name: "index_ratings_on_plugin_id_and_user_id", unique: true
    t.index ["plugin_id"], name: "index_ratings_on_plugin_id"
    t.index ["user_id"], name: "index_ratings_on_user_id"
  end

  create_table "registry_counters", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "value", default: 0, null: false
    t.index ["name"], name: "index_registry_counters_on_name", unique: true
  end

  create_table "reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "reason", null: false
    t.integer "reportable_id", null: false
    t.string "reportable_type", null: false
    t.datetime "resolved_at"
    t.integer "resolved_by_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["reportable_type", "reportable_id"], name: "index_reports_on_reportable"
    t.index ["resolved_by_id"], name: "index_reports_on_resolved_by_id"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "revocations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.integer "plugin_id", null: false
    t.string "reason", null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["created_by_id"], name: "index_revocations_on_created_by_id"
    t.index ["plugin_id", "version"], name: "index_revocations_on_plugin_id_and_version", unique: true
    t.index ["plugin_id"], name: "index_revocations_on_plugin_id"
    t.index ["plugin_id"], name: "index_revocations_whole_plugin_uniqueness", unique: true, where: "version IS NULL"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "second_factor_verified_at"
    t.integer "step_up_failures", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "trusted_publishers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.string "environment", default: "release", null: false
    t.string "plugin_name", null: false
    t.string "provider", default: "github", null: false
    t.integer "publisher_id", null: false
    t.string "repository", null: false
    t.string "repository_id"
    t.string "repository_owner_id"
    t.datetime "updated_at", null: false
    t.string "workflow", null: false
    t.index ["created_by_id"], name: "index_trusted_publishers_on_created_by_id"
    t.index ["publisher_id", "plugin_name"], name: "index_trusted_publishers_on_publisher_id_and_plugin_name", unique: true
    t.index ["publisher_id"], name: "index_trusted_publishers_on_publisher_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name"
    t.json "otp_backup_codes"
    t.datetime "otp_enabled_at"
    t.string "otp_secret"
    t.datetime "recovery_requested_at"
    t.datetime "sensitive_change_at"
    t.datetime "suspended_at"
    t.boolean "system", default: false, null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.string "webauthn_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "publishers"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "audit_events", "users"
  add_foreign_key "comments", "plugins"
  add_foreign_key "comments", "users"
  add_foreign_key "daily_downloads", "plugin_versions"
  add_foreign_key "device_authorizations", "api_tokens"
  add_foreign_key "device_authorizations", "publishers"
  add_foreign_key "device_authorizations", "users"
  add_foreign_key "login_codes", "users"
  add_foreign_key "memberships", "publishers"
  add_foreign_key "memberships", "users"
  add_foreign_key "passkeys", "users"
  add_foreign_key "plugin_versions", "api_tokens"
  add_foreign_key "plugin_versions", "plugins"
  add_foreign_key "plugin_versions", "users"
  add_foreign_key "plugin_versions", "users", column: "approved_by_id"
  add_foreign_key "plugins", "publishers"
  add_foreign_key "ratings", "plugins"
  add_foreign_key "ratings", "users"
  add_foreign_key "reports", "users"
  add_foreign_key "reports", "users", column: "resolved_by_id"
  add_foreign_key "revocations", "plugins"
  add_foreign_key "revocations", "users", column: "created_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "trusted_publishers", "publishers"
  add_foreign_key "trusted_publishers", "users", column: "created_by_id"
end
