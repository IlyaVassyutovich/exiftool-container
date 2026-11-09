# exiftool-container — design

Date: 2026-11-09
Owner: Ilya Vassyutovich (GitHub `IlyaVassyutovich`)

## Intent

A small, public container image that lets its owner run exiftool by hand as if
it were installed locally:

```sh
podman run --rm -v "$PWD:/data" ghcr.io/ilyavassyutovich/exiftool -All photo.jpg
```

The point of building it rather than using an existing image is supply-chain
hygiene: every input (base image, Perl, exiftool, CI actions) is pinned to an
exact, reviewable value, every change to those pins arrives as a PR that CI
builds and smoke-tests, and every published image can be verified back to the
commit and workflow that built it.

## Goals

- Image runs exiftool by hand on local files, as a non-root user.
- Engine-agnostic: builds with Docker, Podman, Buildah alike. The build file is
  named `Containerfile`.
- Alpine base, pinned by tag **and** digest.
- exiftool at the latest release, pinned exactly.
- Every image input pinned; Renovate keeps the pins current and auto-merges
  once CI is green.
- CI publishes to GHCR with provenance attestation, SBOM, and a cosign
  signature.
- Multi-arch is easy to add later (one-line change), but only amd64 ships now.
- Public GitHub repo under Apache-2.0.

## Non-goals

- arm64 or any other architecture in this version.
- A Podman build job in CI (the `Containerfile` simply must not use
  Docker-only syntax).
- Immutable per-build tags (see decisions).
- Registry retention / cleanup of old image versions.
- Tracking only exiftool "production releases".
- Use as a CI-step image (shell-friendly entrypoint, etc.).

## Anti-goals (would make this a failure even if it works)

- Any unpinned input to the image: a floating base tag, an unversioned
  `apk add` in the final stage, a branch-name checkout of exiftool, or a
  tag-pinned GitHub Action. (Build-only tooling in a throwaway stage is
  covered by D13.)
- Renovate auto-merging a PR before the build-and-smoke-test check has run.
- Running as root inside the container.
- A Docker-only build file (e.g. relying on `Dockerfile` naming, BuildKit-only
  syntax that Buildah rejects).

## Constraints and facts (verified 2026-11-09)

| Input | Value |
|---|---|
| Base image | `alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf` (this is the multi-arch index digest) |
| Perl | Alpine `v3.24/main` package `perl=5.42.3-r0` |
| Archive::Zip | Alpine `v3.24/main` package `perl-archive-zip=1.68-r3` |
| exiftool | `13.61`, tag in `github.com/exiftool/exiftool` → commit `9b8664dfcf2c609d3cc8925d380e98ad2a379f9b` |
| Repo | `github.com/IlyaVassyutovich/exiftool-container` (to be created, public) |
| Image | `ghcr.io/ilyavassyutovich/exiftool` (GHCR lowercases owner) |
| License | Apache-2.0 for the repo's own files |

The local working folder is named `exiftool-docker`; renaming it is the
owner's call and not part of this work.

## Decisions (made by the owner unless marked "builder's call")

Every decision below must also be recorded, with its rationale, in
`docs/decisions.md` in the repo (owner asked for this explicitly). The
rationale text here is the source for that file.

### D1. `Containerfile`, not `Dockerfile`
Keeps the repo engine-neutral. Verified that Renovate's `dockerfile` manager
matches `Containerfile` by default. Dependabot does not reliably (open issue
dependabot-core#6067), which is one reason for D2.

### D2. Renovate, not Dependabot
Dependabot cannot track exiftool (no supported registry) and may not read a
`Containerfile`. Renovate covers all three pin types with one tool: Alpine
digest, Alpine Perl package (via Repology), exiftool (via GitHub tags), plus
GitHub Actions SHAs. Cost: installing the Renovate GitHub App (owner does
this; it needs their browser consent).

### D3. Perl from Alpine, pinned to an exact package version
exiftool is pure Perl, so the image needs a Perl interpreter. Pinning the base
by digest does not pin what `apk add` installs, so the package version is
pinned (`perl=5.42.3-r0`) and Renovate bumps it via the Repology datasource.
Known trade-off accepted by owner: Alpine removes superseded package versions
from its mirrors, so a stale pin makes the build fail until the Renovate PR
merges. Loud and quick to fix is preferred over silent drift.
Rejected: unpinned `apk add perl` (silent drift); building Perl from source or
using the Debian-based official `perl` image (heavy / not Alpine).

### D4. exiftool from the Git tag at a pinned commit, not the release tarball
The official tarball (SourceForge, SHA-256 in `exiftool.org/checksums.txt`)
cannot be auto-bumped: Renovate can change a version number but cannot
recompute a SHA-256 on the hosted app, so every exiftool PR would fail and
auto-merge would be pointless. Pinning `github.com/exiftool/exiftool` at the
tag's commit SHA lets Renovate update version and commit together.

Evidence gathered for 13.61 (owner asked how the tarball is published):
- The tarball's SHA-256 matched `checksums.txt`
  (`df7f42c1…0baa`).
- The GitHub repo is exiftool's own (homepage exiftool.org, since 2018); each
  release is a single "Update to X" commit by
  `exiftool@users.sourceforge.net`, tagged on release day.
- Diffing tarball vs tag (ignoring line endings): the `exiftool` script and
  the entire `lib/` tree are identical. Differences are docs, CPAN metadata,
  Windows build helpers only.
- Neither source is signed (unsigned commits/tags; checksum is a plain file on
  exiftool.org), so trust is equivalent: both rest on the author's accounts.

Rejected: tarball + helper workflow to fill in checksums (needs write access
and a GitHub App/PAT so its push triggers CI); tarball with manual checksum
updates (breaks auto-merge on every release).

### D5. Track every exiftool release, not only "production" ones
Owner asked for the latest. 13.61 is not flagged "production" (latest
production is 13.55); GitHub tags carry no production marker, so filtering
would mean scraping the history page. Releases come in irregular bursts
(13.56–13.59 Apr–May 2026, then 13.60 late Oct).

### D6. Renovate auto-merges, with a 7-day wait on exiftool releases
All Renovate PRs auto-merge once required checks pass. exiftool updates wait
7 days after the upstream release (`minimumReleaseAge`) so that a pulled or
re-tagged release never reaches the image; consequence: the image normally
trails upstream by about a week. The initial pin is 13.61 (4 days old at
design time) because the owner asked for "latest" now; the wait applies to
later bumps.
Builder's call: the 7-day wait applies to exiftool only; Alpine digest/Perl
and Actions updates are not delayed, because they are usually security fixes.

**Required safeguard:** `master` must have a ruleset/branch protection making
the build-and-smoke-test check *required*. Without a required check, GitHub
native auto-merge can merge before CI runs.

### D7. Moving tags only: `latest` and `<exiftool version>`
Every merge to `master` publishes and moves `latest` and e.g. `13.61`. No
immutable per-build tag; the digest is the immutable reference and the README
says so. This matches Docker Official Images and Chainguard. Considered and
rejected: Bitnami-style `13.61-rN` (needs a GHCR lookup to compute N), short
SHA (does not sort), run number (noisy), date+run (too long).

### D8. No registry retention
Public GHCR storage is free, and deleting untagged versions would break users
who pin by digest, the very thing D7 tells them to do. Also: once multi-arch
exists, per-arch manifests and signature/SBOM artifacts are untagged too, so a
naive "delete untagged" job would break live images. If cleanup is ever
needed, use a multi-arch-aware tool (e.g. `dataaxiom/ghcr-cleanup-action`).

### D9. Provenance attestation, SBOM, and cosign signature
- Provenance verifiable with `gh attestation verify`.
- SBOM attached to the image in the registry.
- Keyless cosign signature on the pushed digest, verifiable with
  `cosign verify --certificate-identity=… --certificate-oidc-issuer=https://token.actions.githubusercontent.com`.
Cosign overlaps with provenance; owner chose to include it anyway given its
low cost (it helps tooling that only understands cosign signatures).

### D10. amd64 only, multi-arch scaffolded
The build already takes a platform list (single entry `linux/amd64`); adding
`linux/arm64` must be a one-line change plus enabling QEMU. The base digest
is already the multi-arch index digest; nothing in the `Containerfile` may be
architecture-specific.

### D11. Build engine in CI: Docker Buildx (builder's call)
Chosen for native SBOM/provenance output and trivial multi-platform builds.
The `Containerfile` must remain buildable by Podman/Buildah (see anti-goals).

### D12. Apache-2.0
Covers the repo's own files. The published image also contains exiftool and
Perl under Perl's terms (GPL or Artistic); the README notes this.

### D13. `git` in the throwaway clone stage is not version-pinned (builder's call, owner accepted)
The build verifies the cloned `HEAD` equals the pinned commit, so the git
version cannot change what reaches the image. Pinning it would add another
package that breaks the build whenever Alpine drops an old version, for no
gain. The "every input pinned" rule applies to what ships in the final image.

### D14. Optional Perl modules: ship `Archive::Zip`, skip the unpackaged ones
`Archive::Zip` (`perl-archive-zip`, ~200 KB, Alpine `main`) lets exiftool read
ZIP-based formats (DOCX, XLSX, ODT, EPUB…); without it "as if installed
locally" fails silently for those. It is pinned exactly and bumped by
Renovate like Perl (D3), with the same accepted breakage risk.
`IO::Compress::Brotli` and `POSIX::strptime` are not packaged in Alpine 3.24;
shipping them would mean compiling from CPAN, so they are out of scope. The
README lists them as known gaps.

### D15. Required check on `master`; repo admin may bypass
The ruleset requires the build-and-smoke-test check so Renovate can never
merge untested changes (D6). The repo admin (owner) is on the bypass list so
hand fixes to broken CI/Renovate config stay easy. The ruleset is created
after the initial push so the first commit is not blocked.

### D16. Agent instructions: `AGENTS.md` canonical, `CLAUDE.md` imports it
`AGENTS.md` holds the content (read natively by Codex, Cursor and others);
`CLAUDE.md` is the single line `@AGENTS.md`, which Claude Code resolves as an
import. One source, no drift.
Rejected: `AGENTS.md` as a symlink to `CLAUDE.md` (Git on Windows checks
symlinks out as plain text files by default, `core.symlinks=false`); two
independent copies (drift, and agents follow the stale one).

## Shape of the solution

### Containerfile
- Multi-stage. A throwaway stage clones exiftool at the pinned commit and
  verifies that `HEAD` equals the pinned SHA (fail the build otherwise). Only
  the `exiftool` script and `lib/` reach the final stage; git does not.
- Final stage: pinned Alpine; `apk add --no-cache perl=<pinned>`; exiftool in
  `/opt/exiftool`, on `PATH`.
- Version pins as `ARG`s with Renovate comment annotations, e.g.:
  ```
  # renovate: datasource=github-tags depName=exiftool/exiftool
  ARG EXIFTOOL_VERSION=13.61
  ARG EXIFTOOL_COMMIT=9b8664dfcf2c609d3cc8925d380e98ad2a379f9b
  # renovate: datasource=repology depName=alpine_3_24/perl versioning=loose
  ARG PERL_VERSION=5.42.3-r0
  # renovate: datasource=repology depName=alpine_3_24/perl-archive-zip versioning=loose
  ARG PERL_ARCHIVE_ZIP_VERSION=1.68-r3
  ```
- Final stage installs `perl=<pinned>` and `perl-archive-zip=<pinned>`.
  The clone stage installs `git` unpinned (D13).
- Non-root user, numeric UID/GID 1000 (builder's call: matches the typical
  first Linux user, so writes to bind-mounted host folders work by default).
- `WORKDIR /data`, `ENTRYPOINT ["exiftool"]`.
- OCI labels (source, licenses, version, revision) — builder may set them via
  the workflow instead.

### Renovate (`renovate.json`)
- Pins GitHub Actions to SHAs.
- `dockerfile` manager for the Alpine tag+digest.
- Custom regex manager(s) for the `ARG` pins above; exiftool updates both
  version and commit digest in one PR.
- Auto-merge everything; `minimumReleaseAge: "7 days"` for exiftool.
- Known manual case: an Alpine minor bump (3.24 → 3.25) also needs every
  Repology repo name and pin changed (`alpine_3_25/perl`,
  `alpine_3_25/perl-archive-zip`). Renovate cannot do that alone; that PR
  will fail CI and need a human. Builder should make that PR non-auto-merged
  or at least clearly documented.

### CI (GitHub Actions)
- On pull request: build (no push), load locally, smoke-test.
- On push to `master`: same build + smoke test, then push to GHCR with tags
  `latest` and `<EXIFTOOL_VERSION>` (read from the `Containerfile`, single
  source of truth), attach provenance + SBOM, cosign-sign the digest.
- The check that gates PRs must have a stable name so the ruleset can require
  it.
- Every action pinned to a full commit SHA. Least-privilege `permissions`:
  read-only by default; `packages: write`, `id-token: write`,
  `attestations: write` only on the publish job.
- Platform list scaffolding per D10.

### Smoke test
- `exiftool -ver` prints exactly the pinned version.
- Container runs as non-root (`id -u` ≠ 0).
- Read **and write** tags on a small JPEG fixture committed to the repo
  (builder generates it; do not copy third-party images) mounted from the
  host; the write must succeed as the non-root user.
- Perl modules exiftool uses are loadable: at minimum `Compress::Zlib`,
  `Digest::MD5`, `Digest::SHA` and `Archive::Zip` (D14). Builder to check
  exiftool's docs for any other module that is in Perl core upstream but
  split out by Alpine.

### Repo setup (builder performs, owner authorised it)
- Create public repo `IlyaVassyutovich/exiftool-container`, push.
- After the initial push, add a ruleset on `master` requiring the smoke-test
  check, with repo admin on the bypass list (D15).
- After first publish, confirm the GHCR package is public and linked to the
  repo; if it defaulted to private, ask the owner to flip it (GitHub has no
  API for package visibility).
- Owner installs the Renovate GitHub App on the repo.

### Docs
- `README.md`: usage (Docker and Podman, including `--userns=keep-id` for
  rootless Podman and `--user "$(id -u):$(id -g)"` when host UID ≠ 1000),
  tags policy (moving tags, pin by digest for immutability), verify commands
  for provenance and cosign, update policy (Renovate, 7-day wait), known
  gaps (D14), licensing note.
- `docs/decisions.md`: D1–D16 with rationale.
- `AGENTS.md` + `CLAUDE.md` per D16. `AGENTS.md` content, short and
  repo-specific:
  - one-paragraph purpose; pointer to `docs/decisions.md`;
  - invariants: every image input pinned, `Containerfile` engine-neutral,
    Actions SHA-pinned, moving tags only, no retention;
  - manual bump procedures: exiftool (version + commit together), Perl and
    Archive::Zip, and the full Alpine minor-bump procedure (3.24 → 3.25,
    including Repology names);
  - how to build and smoke-test locally;
  - rule: changing a decision updates `docs/decisions.md` in the same PR.
- `LICENSE`: Apache-2.0.

## Left to the builder
- Exact workflow/job structure and file names.
- How the fixture JPEG is generated.
- BuildKit attestations vs GitHub `actions/attest-*` mix, as long as D9's
  verify commands work.
- Exact Renovate config syntax and presets.

## Amendments (2026-11-09, after implementation)

1. Publish pushes by digest, moves tags only after attest, sign, verify and
   smoke, and runs a tip-of-default-branch guard. See D17 in
   `docs/decisions.md`.
2. Default branch is `master` (D18).
3. Commit subjects are plain imperative sentences. This reverses the
   conventional-commit subjects the plan prescribed, which were the planner's
   own default with no owner rationale. See D18 in `docs/decisions.md`.
