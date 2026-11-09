# exiftool-container

A small container image for running [exiftool](https://exiftool.org) by hand, as if it were installed locally. Alpine base, non-root, every input pinned.

## Usage

Docker:

```sh
docker run --rm -e TZ=Europe/Moscow -v "${PWD}:/data" ghcr.io/ilyavassyutovich/exiftool -All photo.jpg
```

Podman:

```sh
podman run --rm -e TZ=Europe/Moscow -v "${PWD}:/data" ghcr.io/ilyavassyutovich/exiftool -All photo.jpg
```

Set `TZ` to your `Area/City` zone: exiftool writes file dates (such as `FileModifyDate`) in the container's timezone, which is UTC by default. On Linux hosts, `-v /etc/localtime:/etc/localtime:ro` instead passes the host's zone through. `${PWD}` works in both POSIX shells and PowerShell.

The container runs as UID/GID 1000 with `/data` as the working directory, so files in the mounted folder are read and written as that user.

- Rootless Podman: add `--userns=keep-id` so your host user maps to the same UID inside the container, otherwise writes to the bind mount can fail.
- Host UID other than 1000: add `--user "$(id -u):$(id -g)"` so written files belong to you.
- Read-only access works with `-v "${PWD}:/data:ro"`.
- Piping works: `cat photo.jpg | docker run -i --rm ghcr.io/ilyavassyutovich/exiftool -`

## Tags

Only moving tags are published: `latest` and the exiftool version (for example `13.61`). Both move on every merge to `master`.

For an immutable reference, pin the digest:

```sh
docker run --rm ghcr.io/ilyavassyutovich/exiftool@sha256:<digest> -ver
```

CI pushes each build by digest first and moves the tags only after the image has been attested, signed, verified and smoke-tested.

## Verify an image

Provenance (needs the [GitHub CLI](https://cli.github.com)):

```sh
gh attestation verify oci://ghcr.io/ilyavassyutovich/exiftool@sha256:<digest> --repo IlyaVassyutovich/exiftool-container
```

Signature (needs [cosign](https://github.com/sigstore/cosign) v3 or newer; the signature is stored as an OCI referrer, which cosign 2.x reports as "no signatures found"):

```sh
cosign verify ghcr.io/ilyavassyutovich/exiftool@sha256:<digest> \
  --certificate-identity-regexp '^https://github\.com/IlyaVassyutovich/exiftool-container/\.github/workflows/ci\.yml@refs/heads/master$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

An SBOM is attached to the image in the registry. Resolve the digest of a tag with `docker buildx imagetools inspect ghcr.io/ilyavassyutovich/exiftool:latest`.

## Updates

[Renovate](https://docs.renovatebot.com) keeps the Alpine base, the Alpine packages, exiftool and the GitHub Actions pinned to current versions, and auto-merges its PRs once the required `build-and-smoke-test` check passes. exiftool releases wait 7 days before being proposed, so the image normally trails upstream by about a week. An Alpine minor or major bump is not auto-merged because it needs manual changes.

exiftool is built from its Git tag at a pinned commit rather than the release tarball. See [docs/decisions.md](docs/decisions.md) for why.

## Known gaps

These optional Perl modules are not in the image, so exiftool runs normally but the features that need them are unavailable:

- `IO::Compress::Brotli`: Brotli-compressed metadata, for example in JPEG XL and JUMBF. Not packaged in Alpine 3.24.
- `Compress::Raw::Lzma`: encoded 7z information. Not packaged in Alpine 3.24.
- `File::StatX`: `FileCreateDate` on Linux. Not packaged in Alpine 3.24.
- `Unicode::LineBreak`: column alignment of plain-text output in languages with wide characters (`-lang`). Packaged in Alpine 3.24 `community`, but not included.

`exiftool -ver -v` lists which optional modules are present. `Archive::Zip` is included, so ZIP-based formats (DOCX, XLSX, EPUB and others) work. Details in D14.

## Licensing

The files in this repository are Apache-2.0 (see [LICENSE](LICENSE)). The published image also contains exiftool and Perl, which are distributed under Perl's terms (GPL or Artistic License), and Alpine Linux packages under their own licenses.
