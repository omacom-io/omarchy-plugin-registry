require "test_helper"

class CommunityTest < ActionDispatch::IntegrationTest
  setup do
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end
    @plugin = Plugin.find_by!(name: "weather")
    @visitor = User.create!(email_address: "visitor@example.com", name: "Visitor")
  end

  test "ratings upsert and aggregate" do
    sign_in_as @visitor
    post plugin_rating_path("acme", "weather"), params: { value: 4 }
    previous_update = @plugin.reload.updated_at
    travel 1.second do
      post plugin_rating_path("acme", "weather"), params: { value: 5 }
    end
    assert_operator @plugin.reload.updated_at, :>, previous_update
    assert_equal 1, @plugin.ratings_count
    assert_equal 5.0, @plugin.average_rating

    sign_in_as @dev
    post plugin_rating_path("acme", "weather"), params: { value: 2 }
    assert_equal 2, @plugin.reload.ratings_count
    assert_equal 3.5, @plugin.average_rating

    get directory_json_path(q: "plugin:weather")
    assert_equal 1, response.parsed_body["plugins"].sole.dig("card", "upvotes")
  end

  test "comments post, publisher badge shows, views count" do
    sign_in_as @visitor
    post plugin_comments_path("acme", "weather"), params: { body: "Love this widget." }
    sign_in_as @dev
    post plugin_comments_path("acme", "weather"), params: { body: "Thanks! v2 soon." }

    get plugin_path("acme", "weather")
    assert_response :success
    assert_match "Love this widget.", response.body
    assert_match "publisher</span>", response.body
    assert_operator @plugin.reload.views_count, :>=, 1
  end

  test "anonymous users cannot rate or comment" do
    post plugin_comments_path("acme", "weather"), params: { body: "drive-by" }
    assert_redirected_to new_session_path
    post plugin_rating_path("acme", "weather"), params: { value: 5 }
    assert_redirected_to new_session_path
    assert_equal 0, @plugin.comments.count
  end

  test "report -> admin hide -> comment disappears" do
    sign_in_as @visitor
    post plugin_comments_path("acme", "weather"), params: { body: "spammy nonsense" }
    comment = Comment.last

    sign_in_as @dev
    post reports_path, params: { reportable_type: "Comment", reportable_id: comment.id, reason: "spam" }
    report = Report.last
    assert_nil report.resolved_at

    admin = User.create!(email_address: "admin@example.com", name: "Admin", admin: true,
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    sign_in_as admin
    post resolve_admin_report_path(report, hide: 1)
    assert comment.reload.hidden?
    assert report.reload.resolved_at

    get plugin_path("acme", "weather")
    assert_no_match "spammy nonsense", response.body
  end
end
