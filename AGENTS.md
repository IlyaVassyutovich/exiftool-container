# AGENTS.md

This repo builds a small public container image that runs exiftool by hand (`ghcr.io/ilyavassyutovich/exiftool`). The point is supply-chain hygiene: every input is pinned, every pin change arrives as a PR that CI builds and smoke-tests, and every published image can be verified. Decisions and their rationale live in `docs/decisions.md`; read it before changing behaviour.

## Invariants

- Every input to the image is pinned: Alpine by tag and digest, Perl and Archive::Zip by exact package version, exiftool by version and commit. Only the throwaway `source` stage may use unpinned tools (D13).
- `Containerfile` stays engine-neutral and Podman-buildable: no `# syntax=`, `RUN --mount`, heredocs, `ADD --checksum`, `ADD <git url>`.
- Every GitHub Action is pinned to a full commit SHA with a `# vX.Y.Z` comment.
- Moving tags only (`latest`, `<exiftool version>`), no per-build tags, no registry retention (D7, D8). Tags move only after the digest is attested, signed, verified and smoke-tested (D17).
- amd64 only; the platform list is set once, as `PLATFORMS` in `.github/workflows/ci.yml` (D10).
- Container runs as UID/GID 1000, never root.
- Text files use LF (`.gitattributes`). Comments explain why, not what.

## Manual bump procedures

Renovate normally does these; do them by hand when it cannot.

exiftool: change `EXIFTOOL_VERSION` and `EXIFTOOL_COMMIT` in `Containerfile` together. The commit is the one the upstream tag points to (`git ls-remote https://github.com/exiftool/exiftool.git refs/tags/<version>`; use the dereferenced `^{}` line for an annotated tag). The build fails if either does not match.

Perl and Archive::Zip: set `PERL_VERSION` and `PERL_ARCHIVE_ZIP_VERSION` to the versions in Alpine `v<alpine minor>/main` (`apk policy perl perl-archive-zip` in the current base image shows them).

Alpine minor bump (for example 3.24 to 3.25), all in one PR:

1. Replace the base in both `FROM` lines with `alpine:3.25.X@sha256:<index digest>` (the multi-arch index digest, not a per-platform one).
2. Change the Repology names in the `# renovate:` comments to `alpine_3_25/perl` and `alpine_3_25/perl-archive-zip`.
3. Set `PERL_VERSION` and `PERL_ARCHIVE_ZIP_VERSION` to the exact versions in `v3.25/main`.
4. Update the "Alpine 3.24" mention in D14 of `docs/decisions.md`.
5. Build and smoke-test locally (below), then let CI confirm.

Renovate's own Alpine minor/major PRs are not auto-merged and fail CI until steps 2 to 4 are done on its branch.

## Build and test locally

```sh
docker build -f Containerfile -t exiftool:local .
sh tests/smoke.sh exiftool:local
```

Use `podman` for the build and `ENGINE=podman sh tests/smoke.sh exiftool:local` to test with Podman. `tests/smoke.sh` pulls the image first if it is not present locally.

## Changing a decision

Update `docs/decisions.md` in the same PR (or commit): name the earlier decision, its rationale and what changes.
