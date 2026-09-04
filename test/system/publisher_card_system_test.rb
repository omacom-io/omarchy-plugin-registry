require "application_system_test_case"

class PublisherCardSystemTest < ApplicationSystemTestCase
  setup do
    publisher = Publisher.create!(name: "card-publisher", kind: :org)
    @plugin = Plugin.create!(
      publisher:, name: "semantic-card", summary: "A progressively enhanced plugin card",
      latest_version: "1.0.0", state: :active, repository_url: "https://github.com/example/semantic-card"
    )
  end

  test "plugin cards keep direct navigation and expose their back face only on request" do
    visit publisher_path(@plugin.publisher.name)

    card = find("article.plugin-card")
    assert_nil card[:tabindex]
    assert_selector ".plugin-card__title-link[href='#{plugin_path(@plugin.publisher.name, @plugin.name)}']",
      text: @plugin.name
    assert_selector ".plugin-card__face--back[aria-hidden='true'][inert]"

    find("button.plugin-card__flip").click

    assert_selector "article.plugin-card.is-flipped"
    assert_selector ".plugin-card__face--front[aria-hidden='true'][inert]"
    assert_selector ".plugin-card__face--back[aria-hidden='false']:not([inert])"
    assert_equal "true", find("button.plugin-card__flip", visible: :all)["aria-expanded"]
    assert page.evaluate_script("document.activeElement.closest('.plugin-card__face--back') !== null")
    assert_selector "button.plugin-card__back-toggle", text: "← front"

    find("button.plugin-card__back-toggle").click

    assert_no_selector "article.plugin-card.is-flipped"
    assert_equal "false", find("button.plugin-card__flip")["aria-expanded"]
    assert page.evaluate_script("document.activeElement.matches('button.plugin-card__flip')")
  end
end
