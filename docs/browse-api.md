# Browse API

The read-only JSON behind the plugin directory. It exists so a native client —
an in-desktop plugin browser, a TUI, a dashboard — can show everything the
website shows without scraping HTML.

Every public page answers JSON at the same URL. There is no separate `/api/v1`
namespace for browsing and no key, token, or registration.

```sh
curl https://plugins.omarchy.org/plugins.json
curl https://plugins.omarchy.org/plugins/acme/weather.json
```

## What this is not

**Do not install from this API.** It is unsigned and served by the application
rather than the CDN origin. The install path is the signed static data plane —
`config.json`, `index/<publisher>/<name>.json`, `revocations.json`, and the
immutable tarballs under `dl/` — each with a detached Ed25519 signature and a
monotonic `generation`. That contract is [client-spec.md](client-spec.md).

Browse with this. Then resolve the version, verify the SHA-256, and check the
kill list through the signed data plane. A client that installs from a browse
response has no integrity guarantee and no rollback protection.

## Conventions

- Keys are `snake_case`. Every response carries `schema_version` (currently `1`).
- Absent data is `null`, never omitted and never an error — `preview`,
  `repository`, `readme`, and `latest` are all nullable.
- URLs (`url`, `preview.card.url`) are absolute and safe to fetch directly.
- Timestamps are ISO 8601 UTC.
- New fields may be added within a `schema_version`. Parse tolerantly: ignore
  keys you do not recognise rather than failing.

---

## `GET /plugins.json`

The directory. Same query parameters as the website, so a client and the web
page can never disagree about what a search returns.

| Parameter | Default | Notes |
|---|---|---|
| `q` | — | Free text over name and summary. Also understands typed operators (below). |
| `sort` | `downloads` | One of `downloads`, `trending`, `rating`, `updated`, `newest`, `name`. Unknown values fall back to the default. |
| `category` | — | A curated category slug. Unknown values are ignored, not an error. |
| `tag` | — | A curated tag slug. |
| `page` | `1` | 1-indexed. Out-of-range pages return an empty list, not a 404. |
| `per_page` | `24` | **JSON only**, capped at `100`. Junk or non-positive values fall back to `24`. |

Typed operators inside `q`, combinable with free text:

```
@acme            plugins in the acme namespace
tag:weather      curated tag
kind:bar-widget  plugin kind
category:system  curated category
```

### Response

```json
{
  "schema_version": 1,
  "query":    { "q": "", "sort": "downloads", "category": null, "tag": null },
  "page":     { "number": 1, "per_page": 24, "total": 1323, "more": true },
  "stats":    { "plugins": 1305, "publishers": 8, "downloads": 224514 },
  "taxonomy": {
    "sorts": ["downloads", "trending", "rating", "updated", "newest", "name"],
    "categories": [{ "slug": "widgets", "label": "Widgets", "count": 454 }],
    "tags": ["ai", "audio", "bar"],
    "max_tags": 3
  },
  "plugins": [ ... ],
  "recent":  [ ... ]
}
```

`comments_count` is how many **visible** comments a plugin has — hidden ones
are not counted, so it agrees with the thread rather than with what moderation
has taken down. It is there so a grid can show the count without fetching a
thread per card. The thread itself is `comments` on the plugin response, which
is an array; the count keeps its own name so one key never means a number in
one response and a list in another.

`taxonomy` is the curated browse vocabulary with live counts. Render facets
from it rather than hardcoding a copy — categories and tags are a governance
decision and the list changes without warning.

`recent` holds plugins first released in the last fortnight. It is populated
only on the unfiltered first page; otherwise it is `[]`.

`page.total` is the number of matches for the current filters. `page.more`
tells you another page exists — prefer it to computing `total / per_page`.

### Paging the whole catalog

```sh
page=1
while :; do
  body=$(curl -s "https://plugins.omarchy.org/plugins.json?per_page=100&page=$page")
  echo "$body" | jq -r '.plugins[].id'
  [ "$(echo "$body" | jq -r '.page.more')" = "true" ] || break
  page=$((page + 1))
done
```

Sort order is stable across pages (every sort breaks ties on plugin id), so a
plugin will not repeat or vanish between requests to the same query.

**If you want the entire catalog, do not page for it.** Fetch the signed
`all.json` from the data plane instead — one request, every listed plugin,
CDN-cached and signature-verifiable:

```sh
curl https://plugins.omarchy.org/all.json
```

It carries `publisher`, `name`, `id`, `summary`, `kinds`, `category`, `tags`,
`latest`, and `downloads` per plugin. It does **not** carry ratings, preview
images, repository stats, or publication dates — use `/plugins.json` when you
need those, and `all.json` when you need completeness cheaply.

---

## `GET /plugins/<publisher>/<name>.json`

One plugin, with everything the web page renders.

```json
{
  "schema_version": 1,
  "plugin": {
    "id": "acme.weather",
    "publisher": "acme",
    "publisher_claimed": true,
    "publisher_verified": false,
    "name": "weather",
    "full_name": "acme/weather",
    "summary": "Forecast in the bar",
    "kinds": ["bar-widget"],
    "category": "widgets",
    "category_label": "Widgets",
    "tags": ["weather"],
    "state": "active",
    "installable": true,
    "latest_version": "1.1.0",
    "downloads": 500,
    "views": 12,
    "rating":  { "average": 4.5, "count": 10 },
    "comments_count": 3,
    "repository": {
      "url": "https://github.com/acme/weather",
      "label": "GitHub", "stars": 42,
      "pushed_at": "2026-08-01T00:00:00Z",
      "release_tag": "v1.1.0", "release_url": "https://..."
    },
    "preview": {
      "animated": false,
      "card":   { "url": "https://...", "width": 800, "height": 500 },
      "detail": { "url": "https://...", "width": 1600, "height": 1000 }
    },
    "url": "https://plugins.omarchy.org/plugins/acme/weather",
    "install_command": "omarchy plugin add acme/weather",
    "readme": "# Weather\n\n...",
    "notices": [],
    "latest":   { ...version object, plus capabilities and provenance... },
    "versions": [ ...version objects, newest first... ],
    "comments": [ { "id": 1, "body": "...", "created_at": "...",
                    "author": { "name": "kim", "publisher_member": false } } ]
  },
  "publisher": { ... },
  "viewer":    { "rating": 4, "privileged": false }
}
```

- `readme` is Markdown **source**, not HTML. Render it yourself; the registry
  does not sanitise it for you here.
- `install_command` is `null` when the plugin is not installable. Use
  `installable` to decide whether to offer an install button — a security hold
  or a plugin with nothing through review must not present one.
- `publisher_claimed` / `publisher_verified` are the namespace's standing, not
  the plugin's, and they are on every plugin entry — including in the
  directory listing, so a grid can render a trust badge without fetching a
  publisher per card. `publisher_claimed: false` means the listing was seeded
  from the legacy marketplace and no author has proven control of the source
  repo; say so rather than implying the namespace is endorsed.
- `viewer` appears only for an authenticated session. Anonymous clients never
  see it, and those responses are the publicly cacheable ones.
- `first_published_at` / `last_published_at` are populated on directory
  responses only; they are `null` here.

### Version objects

```json
{ "version": "1.1.0", "state": "published", "yanked": false,
  "yank_reason": null, "license": "MIT", "min_omarchy_version": "3.0.0",
  "kinds": ["bar-widget"], "size_bytes": 2048, "sha256": "…",
  "published_at": "…", "created_at": "…", "url": "https://…" }
```

`sha256` and `size_bytes` are here for **display**. Verifying a download
against them is not a substitute for the signed index.

The public sees `published` and `yanked` versions. Publisher members and admins
additionally see in-flight pipeline states (`processing`, `held`, `quarantined`,
`rejected`) — so the same URL legitimately returns different lists to different
callers, and those responses are marked private.

### `capabilities`

The privacy-label read of static analysis — what a version runs, connects to,
and touches. Show this before an install.

```json
{ "empty": false,
  "rows": [ { "label": "Runs", "code": true, "items": ["curl"] },
            { "label": "Connects to", "code": true, "items": ["api.example"] } ] }
```

`empty: true` is a positive claim — nothing was detected — not missing data.
`code: true` means the items are literals worth rendering in a monospace face.

### `notices` — render these

The warning banners the website shows, from the same code path, so a takedown
cannot be visible on the site and invisible in your client.

```json
{ "kind": "security_holding", "tone": "danger",
  "title": "Security holding.", "body": "This plugin was removed for malware…" }
```

| `kind` | Meaning |
|---|---|
| `security_holding` | Removed for malware; the name is permanently retired. |
| `quarantined` | Under investigation, not installable right now. |
| `revoked` | One or more versions are on the signed revocation list. |
| `yanked_versions` | Some versions were withdrawn. |
| `not_public` | Publisher-only: nothing has cleared review yet. |

`tone` is `danger` or `warning`. Treat the list as open — render an unknown
`kind` using its `title` and `body` rather than dropping it.

---

## `GET /plugins/<publisher>/<name>/<version>.json`

One version, with the readme extracted from that version's own frozen tarball,
so an old version documents itself as it was.

Returns `plugin` (the summary object), `version` (a version object plus
`latest`, `summary`, `readme`, `capabilities`, `provenance`), and `notices`.

Dotted versions work as you would expect — `/plugins/acme/weather/1.2.0.json`,
including prereleases like `2.0.0-rc.1.json`.

## `GET /publishers/<name>.json`

```json
{ "schema_version": 1,
  "publisher": { "name": "acme", "display_name": "Acme Co", "kind": "org",
                 "bio": "…", "website": null, "claimed": true,
                 "verified": false, "plugin_count": 12, "url": "https://…" },
  "plugins": [ ... ] }
```

`claimed: false` means the listing was seeded from the legacy marketplace and
no author has proven control of the source repo. Say so in your UI rather than
implying the namespace is endorsed.

---

## Caching

Anonymous responses are conditionally cacheable and carry an `ETag`:

```
Cache-Control: max-age=60, public, stale-while-revalidate=300
ETag: W/"97f6e7861223588a4fd0e330f774a8d7"
```

Store the ETag and send `If-None-Match` when you refresh. A `304` costs you and
the registry almost nothing:

```sh
curl -H 'If-None-Match: W/"97f6…"' https://plugins.omarchy.org/plugins/acme/weather.json
```

Authenticated responses are `private` and must not be shared between users.

Download and view counters are deliberately **not** part of the ETag — they
change constantly and would defeat caching entirely. They may therefore lag by
one revalidation. Do not treat them as exact.

## Errors

- `404` — unknown publisher, plugin, or version. Also returned for a plugin
  that exists but has never been public, which is indistinguishable by design
  from a name that never existed.
- `304` — your `If-None-Match` still matches.
- Out-of-range `page` returns `200` with an empty `plugins` array.

## Etiquette

There is no rate limit today; please do not make one necessary. Respect the
60-second freshness window, use `If-None-Match`, prefer `all.json` for whole-
catalog work, and identify your client in a `User-Agent`.
