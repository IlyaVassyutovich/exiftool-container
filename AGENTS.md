# AGENTS.md

This repo builds a small public container image that runs exiftool by hand (`ghcr.io/ilyavassyutovich/exiftool`). The point is supply-chain hygiene: every input is pinned, every pin change arrives as a PR that CI builds and smoke-tests, and every published image can be verified. Decisions and their rationale live in `docs/decisions.md`; read it before changing behaviour.

## Invariants

- Every input to the image is pinned: Alpine by tag and digest, every package the final stage adds (perl, perl-archive-zip, libbz2, tzdata) by exact version, exiftool by version and commit. Only the throwaway `source` stage may use unpinned tools (D13).
- `Containerfile` stays engine-neutral and Podman-buildable: no `# syntax=`, `RUN --mount`, heredocs, `ADD --checksum`, `ADD <git url>`.
- Every GitHub Action is pinned to a full commit SHA with a `# vX.Y.Z` comment.
- Moving tags only (`latest`, `<exiftool version>`), no per-build tags, no registry retention (D7, D8). Tags move only after the digest is attested, signed, verified and smoke-tested (D17).
- amd64 only; the platform list is set once, as `PLATFORMS` in `.github/workflows/ci.yml` (D10).
- Container runs as UID/GID 1000, never root.
- Text files use LF (`.gitattributes`). Comments explain why, not what.
- Commit subjects are plain imperative sentences with no conventional-commit prefixes, and commits carry no Co-authored-by or other attribution trailers.

## Manual bump procedures

Renovate normally does these; do them by hand when it cannot.

exiftool: change `EXIFTOOL_VERSION` and `EXIFTOOL_COMMIT` in `Containerfile` together. The commit is the one the upstream tag points to (`git ls-remote https://github.com/exiftool/exiftool.git refs/tags/<version>`; use the dereferenced `^{}` line for an annotated tag). The build fails if either does not match.

Alpine packages: set `PERL_VERSION`, `PERL_ARCHIVE_ZIP_VERSION`, `LIBBZ2_VERSION` and `TZDATA_VERSION` to the versions in Alpine `v<alpine minor>/main` (`apk update && apk policy perl perl-archive-zip libbz2 tzdata` in the current base image shows them). If a new dependency appears, pin it too: `apk info -v` in the built image must differ from the base image by exactly the pinned packages (D20).

Alpine minor bump (for example 3.24 to 3.25), all in one PR:

1. Replace the base in both `FROM` lines with `alpine:3.25.X@sha256:<index digest>` (the multi-arch index digest, not a per-platform one).
2. Change all four Repology names in the `# renovate:` comments to `alpine_3_25/perl`, `alpine_3_25/perl-archive-zip`, `alpine_3_25/libbz2` and `alpine_3_25/tzdata`.
3. Set `PERL_VERSION`, `PERL_ARCHIVE_ZIP_VERSION`, `LIBBZ2_VERSION` and `TZDATA_VERSION` to the exact versions in `v3.25/main`, and re-check the `apk info -v` difference (D20).
4. Re-check whether `IO::Compress::Brotli`, `Compress::Raw::Lzma` and `File::StatX` are now packaged in the new branch (search the new base image with `apk search`). D14 rests on them being absent; if they are packaged, adding them is a decision change (see below).
5. Update the "Alpine 3.24" mentions in D14 of `docs/decisions.md` and in the README's known gaps.
6. Build and smoke-test locally (below), then let CI confirm.

Renovate's own Alpine minor/major PRs are not auto-merged. Such a PR fails CI only if one of the pinned package versions is missing from the new branch; it can pass CI and still be incomplete, because the Repology names stay on the old branch until step 2 is done.

## Build and test locally

```sh
docker build -f Containerfile -t exiftool:local .
sh tests/smoke.sh exiftool:local
```

Use `podman` for the build and `ENGINE=podman sh tests/smoke.sh exiftool:local` to test with Podman. `tests/smoke.sh` pulls the image first if it is not present locally.

## Changing a decision

Update `docs/decisions.md` in the same PR (or commit): name the earlier decision, its rationale and what changes.
