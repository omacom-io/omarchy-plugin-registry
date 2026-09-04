# The shared plugin entry — the directory listing, a publisher's plugin list,
# and the head of a detail response all render this, so a native client parses
# one shape everywhere. Detail-only material (readme, versions, capabilities,
# comments) is layered on by plugins/show.
json.id plugin.manifest_id
json.publisher plugin.publisher.name
json.name plugin.name
json.full_name plugin.full_name
json.summary(plugin.summary&.each_char&.take(Registry::ManifestValidator::MAX_DESCRIPTION_LENGTH)&.join)
json.kinds plugin.kinds
json.category plugin.category
json.category_label plugin.category && Registry::Taxonomy.label(plugin.category)
json.tags plugin.tags

json.state plugin.state
json.installable plugin.installable?
json.latest_version plugin.latest_version

json.downloads plugin.downloads_count
json.views plugin.views_count
json.rating do
  json.average plugin.average_rating
  json.count plugin.ratings_count
end

# Selected only by the directory queries — absent elsewhere rather than faked.
json.first_published_at plugin.try(:first_published_at)
json.last_published_at plugin.try(:last_published_at)

if (source = source_repo(plugin.repository_url))
  json.repository do
    json.url source[:url]
    json.label source[:label]
    json.stars plugin.repo_stars
    json.pushed_at plugin.repo_pushed_at
    if (release = plugin.repo_release)
      json.release_tag release["release_tag"]
      json.release_url release["release_url"]
    end
  end
else
  json.repository nil
end

# Renditions of the preview shipped in the latest published tarball. Served
# through the Active Storage proxy — a stable, long-cached, absolute URL a
# non-browser client can fetch directly.
if plugin.preview?
  json.preview do
    json.animated plugin.preview_animated?
    json.card do
      json.url absolute_url(rails_storage_proxy_path(plugin.preview_card))
      json.width plugin.preview_card_meta["width"]
      json.height plugin.preview_card_meta["height"]
    end
    if plugin.preview_detail.attached?
      json.detail do
        json.url absolute_url(rails_storage_proxy_path(plugin.preview_detail))
        json.width plugin.preview_detail_meta["width"]
        json.height plugin.preview_detail_meta["height"]
      end
    else
      json.detail nil
    end
  end
else
  json.preview nil
end

json.url absolute_url(plugin_path(plugin.publisher.name, plugin.name))
json.install_command(plugin.installable? ? "omarchy plugin add #{plugin.full_name}" : nil)
