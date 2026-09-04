require "test_helper"

class DirectoryPaginationTest < ActionDispatch::IntegrationTest
  PER_PAGE = HomeController::PER_PAGE

  setup do
    @publisher = Publisher.create!(name: "acme", kind: :org)
    # Equal downloads on every plugin: the worst case for OFFSET paging, where
    # only the id tiebreaker keeps the page boundary stable.
    (PER_PAGE + 5).times do |i|
      Plugin.create!(publisher: @publisher, name: "plugin-#{i.to_s.rjust(3, "0")}",
        summary: "Plugin #{i}", latest_version: "1.0.0", downloads_count: 100)
    end
  end

  test "first page shows PER_PAGE plugins and a next link, no prev" do
    get root_path
    assert_response :success
    assert_select ".index-picker__row", PER_PAGE
    assert_select ".index-picker__pagination a[aria-label='Next nine plugin results']:not([hidden])", 1
    assert_select ".index-picker__pagination a[aria-label='Previous nine plugin results'][hidden]", 1
    assert_select "input[aria-label='Jump to result page'][name='page'][min='1'][max='2'][value='1']", 1
    assert_select ".index-picker__pagination i", count: 0
    assert_select ".index-picker__pagination", text: /←.*\/.*2.*→/m, count: 1
  end

  test "second page shows the remainder and a prev link, no next" do
    get root_path(page: 2)
    assert_response :success
    assert_select ".index-picker__row", 5
    assert_select ".index-picker__pagination a[aria-label='Previous nine plugin results']:not([hidden])", 1
    assert_select ".index-picker__pagination a[aria-label='Next nine plugin results'][hidden]", 1
    assert_select "input[aria-label='Jump to result page'][value='2']", 1
  end

  test "pages never overlap or skip under a tied sort" do
    get root_path
    page_one = Nokogiri::HTML5(response.body).css(".index-picker__row").filter_map { |row| row.text[/plugin-\d{3}/] }
    get root_path(page: 2)
    page_two = Nokogiri::HTML5(response.body).css(".index-picker__row").filter_map { |row| row.text[/plugin-\d{3}/] }
    assert_empty page_one & page_two
    assert_equal PER_PAGE + 5, (page_one + page_two).uniq.size
  end

  test "pager preserves search and sort" do
    get root_path(q: "plugin", sort: "name")
    assert_response :success
    assert_match "q=plugin", response.body
    assert_match "sort=name", response.body
    assert_match "page=2", response.body
  end

  test "out of range page offers a way back" do
    get root_path(page: 99)
    assert_response :success
    assert_match "No plugins on this page", response.body
    assert_select "a.index-picker__card--empty[href='/']", text: /Back to the first page/
  end

  test "no pager when everything fits on one page" do
    Plugin.where(publisher: @publisher).order(:name).limit(6).destroy_all
    get root_path
    assert_response :success
    assert_select ".index-picker__pagination a[hidden]", 2
  end
end
