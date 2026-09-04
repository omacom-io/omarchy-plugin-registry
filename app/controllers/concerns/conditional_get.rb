# Conditional GET for the public read surfaces. Rails builds the ETag and
# answers a matching If-None-Match with 304 — which matters most for a native
# Omarchy client polling a directory or plugin it already has cached.
#
# Deliberately NOT in the key: downloads_count and views_count. Both are
# incremented with `touch: false`, so a fuzzy counter is allowed to go one
# revalidation stale rather than invalidating every page on every view.
module ConditionalGet
  extend ActiveSupport::Concern

  private

  # `sources` may hold records, relations, or plain values (a sort mode, a
  # query string) — anything that changes the response belongs in the key.
  #
  # Only anonymous JSON is marked publicly cacheable. Signed-in responses vary
  # by viewer, and HTML is never shareable at all: csrf_meta_tags writes a
  # token into the session, so every HTML render carries a Set-Cookie that a
  # shared cache must not store.
  def freshen(*sources, last_modified: true)
    parts = sources.flatten.compact
    viewer_specific = authenticated?
    shareable = request.format.json? && !viewer_specific
    etag = parts.map { |part| part.try(:cache_key_with_version) || part }
    etag << Current.user&.id if viewer_specific
    # Some projections include aggregate values that have no reliable shared
    # timestamp. They opt out rather than let If-Modified-Since return a stale 304.
    modified_at = parts.filter_map { |part| part.try(:updated_at) }.max if last_modified
    fresh_when etag: etag,
      last_modified: modified_at,
      public: shareable,
      cache_control: shareable ? SHARED_CACHE_CONTROL : {}
  end

  # A bare "public" would leave a CDN free to invent its own TTL from
  # Last-Modified. Pin it instead: revalidate every minute, and keep serving
  # the last good copy for five while that revalidation happens.
  SHARED_CACHE_CONTROL = { max_age: 1.minute.to_i, stale_while_revalidate: 5.minutes.to_i }.freeze
end
