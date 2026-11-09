# exiftool-container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pinned, non-root Alpine + exiftool image, built and smoke-tested in CI and published to GHCR with provenance, SBOM and a cosign signature. Renovate keeps every pin current.

**Architecture:** A multi-stage `Containerfile`: a throwaway stage clones exiftool at a pinned commit, and the final stage is pinned Alpine plus pinned Perl packages. One POSIX shell smoke test (`tests/smoke.sh`) is the single source of truth for "the image works". It runs locally, on every PR, and again against the pushed digest. GitHub Actions (Buildx) builds, tests and publishes. Renovate opens and auto-merges bump PRs, gated by a required check.

**Tech Stack:** Containerfile (Docker/Podman/Buildah-compatible), POSIX sh, GitHub Actions, Docker Buildx, GHCR, `actions/attest-build-provenance`, cosign (keyless), Renovate.

**Spec:** `docs/superpowers/specs/2026-11-09-exiftool-container-design.md`. Read it first; decision IDs (D1–D16) below refer to it.

> Amended after execution: commit subjects are plain imperative sentences without conventional-commit prefixes; the commit messages below are historical. See spec Amendments.

## Global Constraints

- Base: `alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf`
- Perl: `perl=5.42.3-r0`; Archive::Zip: `perl-archive-zip=1.68-r3` (Alpine `v3.24/main`)
- exiftool: `13.61` at commit `9b8664dfcf2c609d3cc8925d380e98ad2a379f9b` from `https://github.com/exiftool/exiftool.git`
- Repo: `IlyaVassyutovich/exiftool-container` (public). Image: `ghcr.io/ilyavassyutovich/exiftool`
- Tags: `latest` and `<EXIFTOOL_VERSION>` only, both moving (D7). No retention job (D8).
- Container user: UID/GID `1000`, `WORKDIR /data`, `ENTRYPOINT ["exiftool"]`
- Platforms: `linux/amd64` only, set in exactly one place (D10)
- Every GitHub Action is pinned to a full 40-char commit SHA with a `# vX.Y.Z` comment. Resolve SHAs with `gh api repos/<o>/<r>/git/ref/tags/<tag>`, dereferencing annotated tags.
- `Containerfile` must stay buildable by Podman: no BuildKit-only syntax (no `# syntax=`, `RUN --mount`, heredocs, `ADD --checksum`, `ADD <git url>`)
- All text files use LF (enforced by `.gitattributes`).
- Code comments explain *why*, never *what*.
- Commits: never add `Co-authored-by` trailers; never `--amend`.
- Required check name (used by the ruleset): `build-and-smoke-test`

## Review Focus

1. **Out-of-order publishes.** Two merges in quick succession must not leave `latest`/`13.61` pointing at the older build. The publish job uses a `concurrency` group with `cancel-in-progress: false` (Task 3, Step 1 check).
2. **Arbitrary `--user` UID with no passwd entry.** The README tells users to run `--user "$(id -u):$(id -g)"`, so exiftool must read and write as such a user (smoke test `user_override`).
3. **Filenames with spaces and non-ASCII characters.** These must read and write correctly (smoke test `unicode_filename`).
4. **Piped input.** `cat photo.jpg | <engine> run -i --rm IMAGE -` must print tags (smoke test `stdin_read`).
5. **Read-only bind mounts.** `-v "$PWD:/data:ro"` must still allow reads (smoke test `readonly_mount`).

---

### Task 1: Image, smoke test, fixtures

**Files:**
- Create: `.gitattributes`, `Containerfile`, `.containerignore`, `tests/smoke.sh`, `tests/fixtures/pixel.jpg`, `tests/fixtures/sample.docx`, `tests/fixtures/README.md`

**Interfaces:**
- Produces: `tests/smoke.sh IMAGE`. It is POSIX sh, picks the engine from env `ENGINE` (default `docker`), reads the expected version from `Containerfile`, prints `ok <name>` or `FAIL <name>: <detail>` per check, and exits non-zero if any check fails. Tasks 2 and 3 call it exactly this way.
- Produces: the `Containerfile` `ARG` lines with Renovate annotations, in exactly this shape. Task 4's regex depends on it:
  ```
  # renovate: datasource=github-tags depName=exiftool/exiftool versioning=loose
  ARG EXIFTOOL_VERSION=13.61
  ARG EXIFTOOL_COMMIT=9b8664dfcf2c609d3cc8925d380e98ad2a379f9b
  # renovate: datasource=repology depName=alpine_3_24/perl versioning=loose
  ARG PERL_VERSION=5.42.3-r0
  # renovate: datasource=repology depName=alpine_3_24/perl-archive-zip versioning=loose
  ARG PERL_ARCHIVE_ZIP_VERSION=1.68-r3
  ```

- [ ] **Step 1: Line endings first**

`.gitattributes`: `* text=auto eol=lf`, `*.jpg binary`, `*.docx binary`. Then run `git add --renormalize .` and commit (`chore: enforce LF line endings`). The spec was committed with the warning that LF would turn into CRLF, and renormalizing prevents that.

- [ ] **Step 2: Create fixtures**

- `pixel.jpg`: an 8×8 white JPEG with no metadata. Generate it on Windows with .NET `System.Drawing.Bitmap` → `.Save(path, [System.Drawing.Imaging.ImageFormat]::Jpeg)`.
- `sample.docx`: a minimal OOXML zip containing `[Content_Types].xml` (declaring the `core-properties` override for `/docProps/core.xml`) and `docProps/core.xml` with `<dc:creator>smoke-fixture</dc:creator>`. When zipping, use `-LiteralPath`, because `[` is a wildcard in PowerShell.
- `tests/fixtures/README.md`: say how both were generated and that they're original work under the repo license.

- [ ] **Step 3: Write `tests/smoke.sh` (the failing test)**

Each check runs in its own temp dir (`mktemp -d`, `chmod 0777` so container UID 1000 can write to a host dir owned by another UID, removed by `trap … EXIT`). Bind-mount it at `/data` with `--rm`. Checks and exact assertions:

| name | run | assert |
|---|---|---|
| `version` | `IMAGE -ver` | stdout == value of `ARG EXIFTOOL_VERSION=` in `Containerfile` |
| `non_root` | `--entrypoint id IMAGE -u` | stdout == `1000` |
| `perl_modules` | `--entrypoint perl IMAGE -MCompress::Zlib -MDigest::MD5 -MDigest::SHA -MArchive::Zip -e 1` | exit 0 |
| `jpeg_write` | `IMAGE -Artist=smoke-test pixel.jpg`, then `IMAGE -s3 -Artist pixel.jpg` | second stdout == `smoke-test`; `pixel.jpg_original` exists on host |
| `docx_read` | `IMAGE -s3 -FileType -Creator sample.docx` | stdout == `DOCX` then `smoke-fixture` (this fails without Archive::Zip) |
| `user_override` | `--user 4242:4242 IMAGE -Artist=uid pixel.jpg`, then read back | read-back == `uid` |
| `unicode_filename` | copy fixture to `my photo ü.jpg`, write `-Artist=ü`, read back | read-back == `ü` |
| `stdin_read` | `-i IMAGE -s3 -FileType -` with `< pixel.jpg` | stdout == `JPEG` |
| `readonly_mount` | mount with `:ro`, `IMAGE -s3 -FileType pixel.jpg` | stdout == `JPEG` |

Set `MSYS_NO_PATHCONV=1` inside the script so Git Bash on Windows doesn't rewrite `/data`.

- [ ] **Step 4: Run it to verify it fails**

Run: `bash tests/smoke.sh exiftool:local`
Expected: `FAIL version: …` (image not found), exit ≠ 0.

- [ ] **Step 5: Write the `Containerfile`**

- Stage `source`: `FROM <base pin> AS source`. `apk add --no-cache git`, unpinned (D13, with a comment saying so). `git init` + `git fetch --depth 1 <url> "$EXIFTOOL_COMMIT"` + `git checkout FETCH_HEAD`. Fail the build unless `git rev-parse HEAD` == `$EXIFTOOL_COMMIT` *and* `./exiftool -ver` == `$EXIFTOOL_VERSION`. That catches a Renovate PR that bumps one pin but not the other.
- Final stage: `FROM <base pin>` (the same pin, repeated so Renovate updates both lines). `apk add --no-cache "perl=$PERL_VERSION" "perl-archive-zip=$PERL_ARCHIVE_ZIP_VERSION"`. Copy only `exiftool` and `lib/` to `/opt/exiftool`, and symlink `/usr/local/bin/exiftool`. Create group/user `exiftool` with 1000/1000 and no password. Then `USER 1000:1000`, `WORKDIR /data`, `ENTRYPOINT ["exiftool"]`.
- OCI labels: only `org.opencontainers.image.licenses` and `.title` here. CI adds source, revision and version (Task 3).
- `.containerignore`: exclude everything except `Containerfile` (the build needs no context files).

- [ ] **Step 6: Build and run the test, with both engines**

Run: `docker build -f Containerfile -t exiftool:local . && bash tests/smoke.sh exiftool:local`
Then: `podman build -f Containerfile -t exiftool:local . && ENGINE=podman bash tests/smoke.sh exiftool:local`
Expected: 9 × `ok`, exit 0, for both engines. The Podman run is the one-time proof of D1; it is not added to CI.

- [ ] **Step 7: Negative check of the pin guard**

Run: `docker build -f Containerfile --build-arg EXIFTOOL_VERSION=13.60 -t x .`
Expected: the build fails at the verify step.

- [ ] **Step 8: Commit** (`feat: add pinned exiftool Containerfile and smoke test`)

---

### Task 2: GitHub repo + CI build-and-smoke-test

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `tests/smoke.sh IMAGE` (Task 1)
- Produces: workflow `ci.yml` with job id `build`, whose `name: build-and-smoke-test` is the required check. Env `IMAGE: ghcr.io/ilyavassyutovich/exiftool` and `PLATFORMS: linux/amd64` sit at workflow level. Task 3 adds a `publish` job to this file.

- [ ] **Step 1: Write `ci.yml`**

- Triggers: `pull_request`, `push` to `master`, `workflow_dispatch`.
- Top-level `permissions: contents: read`.
- Job `build`:
  1. checkout
  2. `docker/setup-buildx-action`
  3. `docker/build-push-action` with `file: Containerfile`, `load: true`, `push: false`, `tags: exiftool:ci`, `cache-from/to: type=gha` (`mode=max` on `cache-to`)
  4. `bash tests/smoke.sh exiftool:ci`

`load` only supports one platform, so this job always builds `linux/amd64` regardless of `PLATFORMS`. Comment why.

- [ ] **Step 2: Lint**

Run: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:<pinned tag>@sha256:<digest>`
Expected: no output, exit 0.

- [ ] **Step 3: Create the repo and push**

Run: `gh repo create IlyaVassyutovich/exiftool-container --public --source . --remote origin --description "Pinned, non-root exiftool container image" && git push -u origin master`

- [ ] **Step 4: Verify CI is green**

Run: `gh run watch --exit-status $(gh run list --workflow ci.yml --limit 1 --json databaseId --jq '.[0].databaseId')`
Expected: the `build-and-smoke-test` job succeeds and its log shows 9 × `ok`.

- [ ] **Step 5: Commit** (`ci: build and smoke-test the image`) and push.

---

### Task 3: Publish to GHCR with provenance, SBOM, cosign

**Files:**
- Modify: `.github/workflows/ci.yml` (add job `publish`)

**Interfaces:**
- Consumes: `build` job and env `IMAGE`, `PLATFORMS` (Task 2); `tests/smoke.sh` (Task 1)
- Produces: tags `latest` and `<EXIFTOOL_VERSION>` on `ghcr.io/ilyavassyutovich/exiftool`, each published digest with a provenance attestation, a BuildKit SBOM and a cosign signature. Task 5's README documents the exact verify commands used in Step 2.

- [ ] **Step 1: Add the `publish` job**

- `needs: build`; `if: github.event_name == 'push' && github.ref == 'refs/heads/master'`.
- `concurrency: { group: publish-master, cancel-in-progress: false }` (Review Focus 1).
- `permissions: contents: read, packages: write, id-token: write, attestations: write`.
- Steps:
  1. checkout
  2. read the version: `sed -n 's/^ARG EXIFTOOL_VERSION=//p' Containerfile` → output `version`; fail if empty
  3. `docker/setup-qemu-action`, only `if: env.PLATFORMS != 'linux/amd64'` (D10 scaffold)
  4. setup-buildx
  5. `docker/login-action` to `ghcr.io` with `GITHUB_TOKEN`
  6. `docker/metadata-action`: tags `type=raw,value=latest` and `type=raw,value=<version>`; labels include `org.opencontainers.image.version=<version>`
  7. build-push with `platforms: ${{ env.PLATFORMS }}`, `push: true`, `sbom: true`, `provenance: mode=max`, gha cache
  8. `actions/attest-build-provenance` with `subject-name: ${{ env.IMAGE }}`, `subject-digest` from the build output, `push-to-registry: true`
  9. `sigstore/cosign-installer`, then `cosign sign --yes "$IMAGE@$DIGEST"`
  10. post-publish verification (Step 2's commands), as workflow steps
  11. `bash tests/smoke.sh "$IMAGE@$DIGEST"`, so the published artifact itself is tested

Check: `rg -n 'cancel-in-progress: false' .github/workflows/ci.yml` finds the line under `publish`.

- [ ] **Step 2: The verification commands, used in the workflow (step 10) and the README**

```sh
gh attestation verify "oci://$IMAGE@$DIGEST" --repo IlyaVassyutovich/exiftool-container
cosign verify "$IMAGE@$DIGEST" \
  --certificate-identity-regexp '^https://github\.com/IlyaVassyutovich/exiftool-container/\.github/workflows/ci\.yml@refs/heads/master$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
Expected: both exit 0. `gh` needs `GH_TOKEN: ${{ github.token }}`.

- [ ] **Step 3: Lint** (as in Task 2, Step 2).

- [ ] **Step 4: Commit** (`ci: publish to GHCR with provenance, SBOM and cosign`), push, then watch the run (Task 2, Step 4 command).
Expected: `build-and-smoke-test` and `publish` both succeed, and the post-publish smoke test shows 9 × `ok`.

- [ ] **Step 5: Verify from outside CI**

Run: `docker buildx imagetools inspect ghcr.io/ilyavassyutovich/exiftool:13.61 --format '{{json .SBOM}}' | jaq -r '.SPDX.packages[].name' | rg -x 'perl|perl-archive-zip'`
Expected: both names are listed, which shows the SBOM is attached and covers the pinned packages.

Run: `gh api /users/IlyaVassyutovich/packages/container/exiftool --jq .visibility`
Expected: `public`. If it's `private`, stop and ask the owner to make it public in the package settings, since GitHub has no API for that. Also confirm the package is linked to the repo (`.repository.full_name`).

---

### Task 4: Renovate config + required-check ruleset

**Files:**
- Create: `renovate.json`

**Interfaces:**
- Consumes: the `ARG` block shape (Task 1); check name `build-and-smoke-test` (Task 2)

- [ ] **Step 1: Write `renovate.json`**

- `extends`: `config:recommended`, `helpers:pinGitHubActionDigests`, `:dependencyDashboard`
- `automerge: true`, `platformAutomerge: true`
- `customManagers`: one `regex` entry with `managerFilePatterns: ["/(^|/)Containerfile$/"]` and `versioningTemplate: "{{#if versioning}}{{{versioning}}}{{else}}loose{{/if}}"`. Its `matchStrings` capture `datasource`, `depName`, optional `versioning`, then `ARG \w+_VERSION=(?<currentValue>\S+)`, followed by an optional `\nARG \w+_COMMIT=(?<currentDigest>[0-9a-f]{40})`. Exiftool's version and commit are therefore bumped in the same PR.
- `packageRules`:
  - `matchDepNames: ["exiftool/exiftool"]` → `minimumReleaseAge: "7 days"` (D6)
  - `matchDepNames: ["alpine"]`, `matchUpdateTypes: ["minor", "major"]` → `automerge: false`, with a `prBodyNotes` entry saying "Also move the `alpine_3_XX/*` Repology names and the Perl pins; see AGENTS.md" (spec, known manual case)

- [ ] **Step 2: Validate**

Run: `npx --yes --package renovate -- renovate-config-validator --strict renovate.json`
Expected: `Config validated successfully`.

- [ ] **Step 3: Commit** (`chore: add Renovate config`) and push. CI stays green.

- [ ] **Step 4: Create the ruleset on `master` (D15)**

`gh api -X POST repos/IlyaVassyutovich/exiftool-container/rulesets` with:
- `target: branch`, `enforcement: active`
- `conditions.ref_name.include: ["~DEFAULT_BRANCH"]`
- rules: `required_status_checks` (context `build-and-smoke-test`, `strict_required_status_checks_policy: false`), plus `deletion` and `non_fast_forward`
- `bypass_actors: [{actor_id: 5, actor_type: RepositoryRole, bypass_mode: always}]` (admin)

Verify: `gh api repos/IlyaVassyutovich/exiftool-container/rules/branches/master | toon` lists the required check.

- [ ] **Step 5: Hand-off to the owner, then verify**

Ask the owner to install the Renovate GitHub App on the repo. Once installed, wait for the "Dependency Dashboard" issue.
Expected: it lists `alpine`, `exiftool/exiftool`, `alpine_3_24/perl`, `alpine_3_24/perl-archive-zip`, and every action in `ci.yml`. A missing entry means the regex or a file pattern is wrong. Fix it and re-validate.

---

### Task 5: Docs and agent instructions

**Files:**
- Create: `README.md`, `LICENSE`, `docs/decisions.md`, `AGENTS.md`, `CLAUDE.md`

- [ ] **Step 1: `LICENSE`**: Apache-2.0 text verbatim, from `gh api /licenses/apache-2.0 --jq .body`. Leave the appendix placeholders alone; they're instructions for per-file headers, not for filling in.

- [ ] **Step 2: `docs/decisions.md`**: D1–D16 from the spec, one section each: decision, why, rejected alternatives. Keep the D4 evidence (tarball vs tag comparison) in full.

- [ ] **Step 3: `README.md`**
  - Usage for Docker and Podman. Note `--userns=keep-id` for rootless Podman and `--user "$(id -u):$(id -g)"` when the host UID isn't 1000.
  - Tags policy: moving tags; pin `@sha256:` for immutability.
  - Verify commands: exactly Task 3, Step 2's.
  - Update policy: Renovate auto-merges; 7-day wait on exiftool.
  - Known gaps: Brotli, `POSIX::strptime` (D14).
  - Licensing: repo Apache-2.0; image contents under Perl's terms.

- [ ] **Step 4: `AGENTS.md`**: content as listed in the spec's Docs section (purpose, invariants, manual bump procedures including the full Alpine 3.24→3.25 steps, local build + `tests/smoke.sh`, decisions-update rule). `CLAUDE.md` is exactly `@AGENTS.md` plus a newline.

- [ ] **Step 5: Verify the docs' commands are real**

Run each verify command from the README against the published `:13.61` digest, locally.
Expected: both exit 0. If `cosign` isn't installed locally, run it via `ghcr.io/sigstore/cosign/cosign:<pinned>`.

- [ ] **Step 6: Commit** (`docs: add README, decisions, agent instructions, license`) and push. Expected: CI green, and the publish job re-publishes the same content.
