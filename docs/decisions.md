# Decisions

Each entry records what was decided, why, and what was rejected. Changing a
decision updates this file in the same change. Dates are 2026-11-09 unless
noted. Entries marked "builder's call" were made by the implementer and
accepted by the owner.

## D1. `Containerfile`, not `Dockerfile`

Decision: the build file is named `Containerfile`.

Why: it keeps the repo engine-neutral. Renovate's `dockerfile` manager matches
`Containerfile` by default. Dependabot does not reliably (open issue
dependabot-core#6067), which is one reason for D2.

Rejected: `Dockerfile` (ties the repo to one engine's naming).

## D2. Renovate, not Dependabot

Decision: Renovate keeps every pin current.

Why: Dependabot cannot track exiftool (no supported registry) and may not read
a `Containerfile`. Renovate covers all pin types with one tool: the Alpine
digest, the Alpine Perl packages (via Repology), exiftool (via GitHub tags) and
GitHub Actions SHAs. Cost: the Renovate GitHub App must be installed, which
needs the owner's browser consent.

Rejected: Dependabot (gaps above); several tools side by side (more config,
more drift).

## D3. Perl from Alpine, pinned to an exact package version

Decision: `perl=5.42.3-r0`, bumped by Renovate through the Repology datasource.

Why: exiftool is pure Perl, so the image needs an interpreter. Pinning the base
by digest does not pin what `apk add` installs, so the package version is
pinned too. Accepted trade-off: Alpine removes superseded package versions from
its mirrors, so a stale pin makes the build fail until the Renovate PR merges.
Loud and quick to fix is preferred over silent drift.

Rejected: unpinned `apk add perl` (silent drift); building Perl from source or
using the Debian-based official `perl` image (heavy, not Alpine).

## D4. exiftool from the Git tag at a pinned commit, not the release tarball

Decision: clone `github.com/exiftool/exiftool` at the tag's commit SHA and
verify both the SHA and `exiftool -ver`.

Why: the official tarball (SourceForge, SHA-256 in `exiftool.org/checksums.txt`)
cannot be auto-bumped. Renovate can change a version number but cannot
recompute a SHA-256 on the hosted app, so every exiftool PR would fail and
auto-merge would be pointless. Pinning the GitHub repo at the tag's commit SHA
lets Renovate update version and commit together.

Evidence gathered for 13.61:
- The tarball's SHA-256 matched `checksums.txt` (`df7f42c1…0baa`).
- The GitHub repo is exiftool's own (homepage exiftool.org, since 2018); each
  release is a single "Update to X" commit by `exiftool@users.sourceforge.net`,
  tagged on release day.
- Diffing tarball vs tag (ignoring line endings): the `exiftool` script and the
  entire `lib/` tree are identical. Differences are docs, CPAN metadata and
  Windows build helpers only.
- Neither source is signed (unsigned commits and tags; the checksum is a plain
  file on exiftool.org), so trust is equivalent: both rest on the author's
  accounts.

Rejected: tarball plus a helper workflow to fill in checksums (needs write
access and a GitHub App or PAT so its push triggers CI); tarball with manual
checksum updates (breaks auto-merge on every release).

## D5. Track every exiftool release, not only "production" ones

Decision: follow the latest tag.

Why: the owner asked for the latest. 13.61 is not flagged "production" (the
latest production release is 13.55), and GitHub tags carry no production
marker, so filtering would mean scraping the history page. Releases come in
irregular bursts (13.56 to 13.59 in Apr to May 2026, then 13.60 in late
October).

Rejected: tracking production releases only (needs scraping, lags far behind).

## D6. Renovate auto-merges, with a 7-day wait on exiftool releases

Decision: all Renovate PRs auto-merge once required checks pass. exiftool
updates wait 7 days after the upstream release (`minimumReleaseAge`).

Why: a pulled or re-tagged release must never reach the image. Consequence: the
image normally trails upstream by about a week. The initial pin is 13.61 (4
days old at design time) because the owner asked for "latest" at that moment;
the wait applies to later bumps. Builder's call: the wait applies to exiftool
only. Alpine digest, Perl and Actions updates are not delayed because they are
usually security fixes.

Required safeguard: `main` must have a ruleset making `build-and-smoke-test`
required (D15). Without a required check, GitHub native auto-merge can merge
before CI runs.

An Alpine minor or major bump is the exception and is not auto-merged: the
Repology package names and Perl pins must be moved by hand (see `AGENTS.md`).

Rejected: delaying every update (delays security fixes); no wait on exiftool
(exposes the image to pulled releases).

## D7. Moving tags only: `latest` and `<exiftool version>`

Decision: every merge to `main` moves `latest` and e.g. `13.61`. There is no
immutable per-build tag; the digest is the immutable reference and the README
says so.

Why: this matches Docker Official Images and Chainguard.

Rejected: Bitnami-style `13.61-rN` (needs a GHCR lookup to compute N); short
SHA (does not sort); run number (noisy); date plus run (too long).

## D8. No registry retention

Decision: old image versions are never deleted.

Why: public GHCR storage is free, and deleting untagged versions would break
users who pin by digest, the very thing D7 tells them to do. Once multi-arch
exists, per-arch manifests and signature/SBOM artifacts are untagged too, so a
naive "delete untagged" job would break live images. If cleanup is ever needed,
use a multi-arch-aware tool (e.g. `dataaxiom/ghcr-cleanup-action`).

Rejected: a scheduled "delete untagged versions" job.

## D9. Provenance attestation, SBOM, and cosign signature

Decision:
- Provenance verifiable with `gh attestation verify`.
- SBOM attached to the image in the registry.
- Keyless cosign signature on the pushed digest, verifiable with `cosign verify`
  against the workflow identity and the GitHub OIDC issuer.

Why: cosign overlaps with provenance, but the owner chose to include it given
its low cost; it helps tooling that only understands cosign signatures.

Rejected: provenance only (see above); a long-lived signing key (key custody
for no gain over keyless).

## D10. amd64 only, multi-arch scaffolded

Decision: the build takes a platform list with one entry, `linux/amd64`, set in
exactly one place (`PLATFORMS` in `ci.yml`).

Why: adding `linux/arm64` must be a one-line change plus QEMU, which the publish
job already enables when the list gains a non-native architecture. The base
digest is already the multi-arch index digest, and nothing in the `Containerfile`
may be architecture-specific.

Rejected: shipping arm64 now (out of scope for this version).

## D11. Build engine in CI: Docker Buildx (builder's call)

Decision: CI builds with Docker Buildx.

Why: native SBOM and provenance output and trivial multi-platform builds. The
`Containerfile` must remain buildable by Podman and Buildah (no BuildKit-only
syntax).

Rejected: a Podman build job (extra CI surface for no shipped benefit).

## D12. Apache-2.0

Decision: the repo's own files are Apache-2.0.

Why: a permissive, widely understood license. The published image also contains
exiftool and Perl under Perl's terms (GPL or Artistic); the README notes this.

Rejected: none considered.

## D13. `git` in the throwaway clone stage is not version-pinned (builder's call, owner accepted)

Decision: the clone stage installs `git` and `perl` unpinned.

Why: the build verifies that the cloned `HEAD` equals the pinned commit and that
`exiftool -ver` equals the pinned version, so the git version cannot change what
reaches the image. Pinning it would add another package that breaks the build
whenever Alpine drops an old version, for no gain. The "every input pinned" rule
applies to what ships in the final image.

Rejected: pinning build-only tools.

## D14. Optional Perl modules: ship `Archive::Zip`, skip the unpackaged ones

Decision: install `perl-archive-zip`; do not ship `IO::Compress::Brotli` or
`POSIX::strptime`.

Why: `Archive::Zip` (~200 KB, Alpine `main`) lets exiftool read ZIP-based
formats (DOCX, XLSX, ODT, EPUB and others); without it "as if installed
locally" fails silently for those. It is pinned exactly and bumped like Perl
(D3), with the same accepted breakage risk. The other two are not packaged in
Alpine 3.24; shipping them would mean compiling from CPAN, so they are out of
scope and listed as known gaps in the README.

Rejected: compiling the missing modules from CPAN (heavier image, build
toolchain in the final stage, no package-level pin).

## D15. Required check on `main`; repo admin may bypass

Decision: a ruleset on `main` requires `build-and-smoke-test`; the repo admin
(owner) is on the bypass list.

Why: Renovate can then never merge untested changes (D6). The bypass keeps hand
fixes to broken CI or Renovate config easy. The ruleset was created after the
initial push so the first commit was not blocked.

Rejected: no protection (auto-merge could race CI); no bypass (a broken CI
config could lock the owner out of fixing it).

## D16. Agent instructions: `AGENTS.md` canonical, `CLAUDE.md` imports it

Decision: `AGENTS.md` holds the content (read natively by Codex, Cursor and
others); `CLAUDE.md` is the single line `@AGENTS.md`, which Claude Code resolves
as an import.

Why: one source, no drift.

Rejected: `AGENTS.md` as a symlink to `CLAUDE.md` (Git on Windows checks symlinks
out as plain text files by default, `core.symlinks=false`); two independent
copies (drift, and agents follow the stale one).

## D17. Publish by digest; move tags only after verification (deviation from the plan)

Decision: the publish job pushes the image by digest only, with BuildKit SBOM
and provenance (`mode=max`). It then attests provenance, signs with keyless
cosign, verifies both (`gh attestation verify`, `cosign verify`) and smoke-tests
that digest. Only then does it move `latest` and `<version>` to exactly that
digest and assert they resolve to it. A guard step skips the whole job unless
the commit is still the tip of `main`, and job-level concurrency serialises
publishes.

Why: the original plan pushed tags first and verified afterwards. Run
42674470293 moved the tags to an image whose post-publish smoke test then
failed, leaving users on a broken `latest`. Separately, job-level concurrency
serialises publishes but orders them by build-finish time, not commit order, so
an older commit could move the tags back after a newer one. The tip guard fixes
the ordering; pushing by digest and moving tags last fixes the broken-tag
window.

Rejected: tags first, verify after (shipped a broken tag); concurrency alone
(wrong order possible); `cancel-in-progress: true` (can cancel a publish midway
between pushing and tagging).
