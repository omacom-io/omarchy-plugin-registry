module Registry
  # The curated browse taxonomy. Manifests declare at most one category and up
  # to three tags, all from these lists — free-form values would fragment the
  # directory into single-use labels nobody can filter by. Additions are a
  # governance decision (suggest one in a publishing issue), not a publish-time
  # side effect.
  module Taxonomy
    CATEGORIES = %w[
      appearance bar-widgets bars desktop developer-tools hardware kids menus
      overlays panels productivity services system widgets other
    ].freeze

    TAGS = %w[
      ai audio bar clock games hyprland launcher media monitoring network
      notifications power-management quickshell security weather workspaces
    ].freeze

    MAX_TAGS = 3
    CATEGORY_LABELS = { "developer-tools" => "Development" }.freeze

    module_function

    def category?(value) = CATEGORIES.include?(value)
    def tag?(value) = TAGS.include?(value)

    def label(slug)
      CATEGORY_LABELS.fetch(slug.to_s) { slug.to_s.split("-").map(&:capitalize).join(" ") }
    end
  end
end
