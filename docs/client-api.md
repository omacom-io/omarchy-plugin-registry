# Client API

What a signed-in app writes through. Reading a plugin is the anonymous,
cacheable [Browse API](browse-api.md); this is everything that depends on who
is asking — who you are, what you rated, and posting a rating or a comment.

The desktop [Omarchy plugin browser](https://github.com/jankeesvw/omarchy-plugin-browser)
is the client this exists for.

## Two kinds of token

A token that browses is not a token that publishes, and the distinction is
checked at the endpoint rather than inferred from scope.

| | `publish` | `client` |
|---|---|---|
| Minted by | `omarchy plugin publish` | a signed-in app |
| Can | publish new versions | read as you, rate, comment |
| Cannot | anything else | **publish**, yank, change owners, touch settings |
| Lifetime | 7 days | 30 days |
| Needs a recent second factor | yes | no |
| Budget per account | 25 | 10 |

A publish token posted to a client endpoint is a `403`, and so is the reverse.
Neither can be mistaken for the other by forgetting to look.

**Why a client token is not held to the second-factor bar.** Approving one
happens in a browser session that can already rate and comment without ever
proving a second factor. Demanding a passkey before you may leave a comment
would be theatre, and it would lock every account without MFA out of the app
entirely. Publishing is different: it ships code to other people's machines,
so it keeps the bar. The sensitive-change cooldown applies to both — it gates
credential-shaped actions, and minting either of these is one. Neither applies
to pressing **Deny**: that mints nothing, and an account in the cooldown is
exactly the one most likely to be looking at a code it did not ask for.

## Signing in

The device flow ([RFC 8628](https://datatracker.ietf.org/doc/html/rfc8628)
shape), with `scope=client`.

```sh
curl -X POST https://plugins.omarchy.org/api/v1/device/code -d scope=client
```

```json
{
  "device_code": "omd_…",
  "user_code": "WDJB-MJHT",
  "verification_uri": "https://plugins.omarchy.org/device",
  "verification_uri_complete": "https://plugins.omarchy.org/device?code=WDJB-MJHT",
  "scope": "client",
  "expires_in": 900,
  "interval": 5
}
```

Open `verification_uri_complete` in the user's browser — it carries the code,
so an app the user is looking at does not make them retype something it
already knows. Show `user_code` next to it anyway: it is what they check the
page against, and it is the only defence against being walked into approving
somebody else's sign-in. Then poll:

```sh
curl -X POST https://plugins.omarchy.org/api/v1/device/token -d device_code=omd_…
```

| Status | Body | Meaning |
|---|---|---|
| `202` | `{"error": "authorization_pending"}` | Keep polling, no faster than `interval`. |
| `429` | `{"error": "slow_down"}` | You are polling too fast. |
| `403` | `{"error": "access_denied"}` | They pressed Deny. Stop. |
| `400` | `{"error": "expired_token"}` | Expired, or already claimed. Start over. |
| `200` | the token | Store it. |

```json
{ "token": "omp_…", "token_type": "bearer", "kind": "client",
  "scope": "browse, rate and comment as you",
  "expires_at": "2026-09-29T09:00:00Z" }
```

The token is single-claim: the first poll to succeed gets it and every later
one gets `expired_token`. Store it somewhere only the user can read, and send
it as `Authorization: Bearer omp_…`.

An unrecognised `scope` asks for `publish`. A caller who asks for something the
registry does not understand gets the flow that is gated hardest, not the one
that is gated least.

## Responses

Every response here is `Cache-Control: no-store` — it depends on who is asking
and must never land in a shared cache. Errors are `{"error": "…"}`.

| Status | When |
|---|---|
| `401` | No token, or it is expired, revoked, or nonsense. |
| `403` | Wrong kind of token, or the account is suspended. |
| `404` | Unknown plugin — and a plugin that has never been public, which is indistinguishable by design. |
| `422` | The rating is out of range, or the comment did not validate. |
| `429` | Rate limited. |

## `GET /api/v1/me`

Who the app is talking as. Call it after sign-in and on every launch: it is
how a client finds out its stored token is still good without guessing from a
failed write.

```json
{
  "user": { "name": "Kim Rivera", "email": "kim@example.com", "admin": false },
  "publishers": [
    { "name": "acme", "kind": "org", "personal": false, "verified": false }
  ],
  "token": { "hint": "omp_abcd…wxyz", "expires_at": "2026-09-29T09:00:00Z",
             "scope": "browse, rate and comment as you" }
}
```

`publishers` are the namespaces this account publishes under, accepted
memberships only. The personal one is the account's own handle — a better
answer than anything a client can infer from what is installed locally.

## `GET /api/v1/me/plugins`

Which plugins this account publishes, as manifest ids.

```json
{ "plugins": ["acme.weather", "kimrivera.clock"] }
```

A client cannot work this out from a listing. An organisation's plugins carry
the organisation's name and not the names of its members, so matching a handle
against a byline gets an org's work wrong in both directions — it claims other
people's plugins for whoever shares a handle with the namespace, and disowns
the ones published under a name you share with colleagues. Asking is the only
way to be right.

Scoped to what the directory shows, so a plugin still in review is not in the
list. The ids exist to mark rows the client already has; one the listing cannot
contain is one it could never mark.

## `DELETE /api/v1/session`

Signing out. Revokes **this** token and answers `204`; other devices keep
theirs. Revoking rather than only forgetting matters: a token the client has
thrown away but the registry still honours is exactly the credential nobody
notices leaking.

## The social payload

Rating, commenting and deleting all answer with the same shape — the whole
social state of one plugin, after the write. A client applies one response and
never has to stitch two together or refetch to find out what happened.

```json
{
  "plugin": "acme.weather",
  "comments_count": 3,
  "rating": { "average": 4.5, "count": 10, "mine": 5 },
  "comments": [
    { "id": 12, "body": "Runs well on two monitors.",
      "created_at": "2026-08-30T09:00:00Z", "mine": true,
      "author": { "name": "Kim Rivera", "publisher_member": true } }
  ]
}
```

- `rating.mine` is `null` when this account has not rated the plugin.
- `mine` on a comment is whether this account can delete it. Hiding someone
  else's is moderation and lives in the admin surfaces, where it leaves an
  audit trail.
- `publisher_member` is the badge the web page shows for a comment from the
  plugin's own publisher.
- Hidden comments are not in the list. Newest first, fifty at most.
- `comments_count` is how long the thread actually is, which is not the length
  of `comments` once it has been truncated. Show that number, not the array's
  length, or a plugin with eighty comments starts claiming fifty the moment
  somebody opens it. It counts visible comments only, so it agrees with the
  list rather than with what moderation has hidden.

## `GET /api/v1/plugins/<publisher>/<plugin>`

The social payload, unchanged. This is the read; everything below writes.

## `PUT /api/v1/plugins/<publisher>/<plugin>/rating`

`value` is 1–5. Idempotent: rating something you have already rated moves your
rating rather than failing on the one-per-user constraint, which is what a
star control does when you click a different star.

```sh
curl -X PUT -H "Authorization: Bearer omp_…" \
  https://plugins.omarchy.org/api/v1/plugins/acme/weather/rating -d value=5
```

## `DELETE /api/v1/plugins/<publisher>/<plugin>/rating`

Clears your rating. It has its own verb because "I take it back" is not the
same claim as one star.

## `POST /api/v1/plugins/<publisher>/<plugin>/comments`

`body` is 3–2,000 characters. Answers `201` with the social payload.

Five an hour per **account** — the same budget the web form gets. A second door
onto the same table must not be the cheap way around the first one's limit, and
counting per token would make signing in again the cheap way around this one.

## `DELETE /api/v1/comments/<id>`

Deletes your own comment and answers with the thread it left. Someone else's
is a `404`: the lookup is scoped to your comments, so moderation cannot be
reached from here even by accident.
