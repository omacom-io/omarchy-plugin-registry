# Omarchy Plugin Registry

The hosted plugin registry for [Omarchy](https://omarchy.org) Quattro —
`plugins.omarchy.org`. A Rails control plane serving a crates.io-style static
data plane: append-only JSON index + immutable, checksummed tarballs, with
registry-native accounts, automated review, and a kill-bit for revoking
already-installed plugins.

Full design: [docs/design.md](docs/design.md). Branding: [docs/branding.md](docs/branding.md)
(matches Omacom / [omacon.org](https://www.omacon.org)).

## Architecture in one paragraph

The Rails app handles accounts (passwordless — emailed one-time codes like
Cortex/Herald, with a mandatory second factor for publishers: passkeys with
required user verification, or TOTP), namespaces
(`publisher/name`, first-claim), publishing (short-lived scoped tokens; OIDC
trusted publishing later), review, and admin (quarantine / yank / kill-bit).
On every accepted publish it regenerates static index files and freezes the
tarball — installs never touch Rails in the hot path. Clients
(`omarchy plugin add publisher/name`) fetch index + tarball from the CDN,
verify checksums, and check a tiny signed `revocations.json` kill list.

## Development

```sh
bin/setup          # install gems, prepare DB
bin/dev            # run the app at localhost:3000
bin/rails test     # run tests
```

Ruby 3.4.7 (`.ruby-version`, mise-managed), Rails 8.1, SQLite everywhere by
default (production needs a persistent volume; Postgres is an optional swap —
see docs/deploy.md), Solid Queue/Cache/Cable, Propshaft + importmap — no Node
build step.

## Status

The **registry side** of `docs/design.md` §11's three phases is built: publish
pipeline with deterministic scanning, capability fingerprints + delta holds,
escalate-only AI review hook, publish hold window, Ed25519-signed index + kill
list, device-flow CLI login, OIDC trusted publishing with provenance, passkeys,
community (ratings/comments/views/reports + moderation), seeding + repo-proof
claims, the admin console, and the two JSON APIs a native in-desktop plugin
browser reads and writes: `docs/browse-api.md` (anonymous, cacheable browse
data — never an install path) and `docs/client-api.md` (device-flow sign-in
and the ratings and comments a signed-in app posts, on a token that can never
publish).

**Not yet done, and required before launch**: the Quattro-side client
(`omarchy plugin add/update/publish`, signature + freshness verification,
receipts, the kill-bit check — contract in `docs/client-spec.md`), deployment
(`docs/deploy.md`), the real omarchyplugins.com catalog for seeding, and the
governance roster names.

Verify the current state locally — no claim here substitutes for running the
gates yourself (CI runs once the repo has a remote):

```bash
bin/rails test               # unit + integration + conformance corpus
bin/rails test:system        # WebAuthn browser test (headless Chrome)
bin/rubocop                  # lint
bin/brakeman -q              # static security analysis
bin/bundler-audit            # gem CVE audit
bin/importmap audit          # JS dependency audit
```
