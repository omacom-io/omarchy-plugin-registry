require "test_helper"

class RepoStatsTest < ActionDispatch::IntegrationTest
  setup do
    @publisher = Publisher.create!(name: "acme", kind: :org)
    @plugin = Plugin.create!(publisher: @publisher, name: "weather", summary: "Forecast",
      latest_version: "1.0.0", repository_url: "https://github.com/acme/omarchy-weather")
    @plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: "0" * 64, size_bytes: 1,
      state: :published, published_at: 1.week.ago)
  end

  def with_stats_lookup(result)
    original = Rails.application.config.x.repo_stats_lookup
    Rails.application.config.x.repo_stats_lookup = ->(repository) { result.is_a?(Proc) ? result.call(repository) : result }
    yield
  ensure
    Rails.application.config.x.repo_stats_lookup = original
  end

  test "parses github repository urls and ignores other hosts" do
    assert_equal "acme/omarchy-weather", Registry::RepoStats.github_repository("https://github.com/acme/omarchy-weather")
    assert_equal "acme/x", Registry::RepoStats.github_repository("https://github.com/acme/x.git")
    assert_nil Registry::RepoStats.github_repository("https://gitlab.com/acme/x")
    assert_nil Registry::RepoStats.github_repository("http://github.com/acme/x")
    assert_nil Registry::RepoStats.github_repository(nil)
  end

  test "sync stores stats and the plugin surfaces render them" do
    with_stats_lookup({ "stars" => 42, "pushed_at" => 2.days.ago.iso8601,
                        "release_tag" => "v1.0.0", "release_url" => "https://github.com/acme/omarchy-weather/releases/tag/v1.0.0" }) do
      Registry::RepoStats.sync!(@plugin)
    end

    assert_equal 42, @plugin.reload.repo_stars
    assert @plugin.repo_stats_synced_at.present?

    get directory_json_path
    assert_equal 42, response.parsed_body["plugins"].sole.dig("repository", "stars")
    get "/plugins/acme/weather"
    assert_match "★ 42", response.body
    assert_match "v1.0.0", response.body
    assert_select "a[href=?]", "https://github.com/acme/omarchy-weather/releases/tag/v1.0.0"
  end

  test "non-github repos sync to empty stats without a fetch" do
    @plugin.update!(repository_url: "https://codeberg.org/acme/weather")
    with_stats_lookup(->(_) { raise "must not fetch" }) do
      Registry::RepoStats.sync!(@plugin)
    end
    assert_equal({}, @plugin.reload.repo_stats)
    assert @plugin.repo_stats_synced_at.present?
  end

  test "sweep enqueues only stale github-backed plugins" do
    fresh = Plugin.create!(publisher: @publisher, name: "fresh", latest_version: "1.0.0",
      repository_url: "https://github.com/acme/fresh", repo_stats_synced_at: 1.hour.ago)
    Plugin.create!(publisher: @publisher, name: "bare", latest_version: "1.0.0")

    assert_enqueued_jobs 1, only: Registry::RepoStatsJob do
      Registry::RepoStatsSweepJob.perform_now
    end
  end
end
