#!/bin/sh
# Usage: smoke.sh IMAGE   (engine from $ENGINE, default docker)
set -u

# Git Bash would otherwise rewrite /data into a Windows path.
export MSYS_NO_PATHCONV=1

ENGINE=${ENGINE:-docker}
IMAGE=${1:?usage: smoke.sh IMAGE}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIX=$ROOT/tests/fixtures
FAILED=0
DIRS=

cleanup() {
    for d in $DIRS; do rm -rf "$d"; done
}
trap cleanup EXIT

# The engine runs outside MSYS on Windows and cannot resolve MSYS paths.
hostpath() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# 0777 lets container UIDs that differ from the host owner write to the mount.
newdir() {
    D=$(mktemp -d)
    chmod 0777 "$D"
    DIRS="$DIRS $D"
}

# run MOUNT_OPTS ENGINE_ARGS...   (mount is $D at /data)
run() {
    mo=$1
    shift
    "$ENGINE" run --rm -v "$(hostpath "$D"):/data$mo" "$@"
}

ok() { echo "ok $1"; }
fail() {
    echo "FAIL $1: $2"
    FAILED=1
}

expect_eq() { # name actual expected
    if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected '$3', got '$2'"; fi
}

EXPECTED_VERSION=$(sed -n 's/^ARG EXIFTOOL_VERSION=//p' "$ROOT/Containerfile")

check_version() {
    newdir
    out=$(run "" "$IMAGE" -ver 2>&1)
    expect_eq version "$out" "$EXPECTED_VERSION"
}

check_non_root() {
    newdir
    out=$(run "" --entrypoint id "$IMAGE" -u 2>&1)
    expect_eq non_root "$out" 1000
}

check_perl_modules() {
    newdir
    if out=$(run "" --entrypoint perl "$IMAGE" -MCompress::Zlib -MDigest::MD5 -MDigest::SHA -MArchive::Zip -e 1 2>&1); then
        ok perl_modules
    else
        fail perl_modules "$out"
    fi
}

check_jpeg_write() {
    newdir
    cp "$FIX/pixel.jpg" "$D/"
    run "" "$IMAGE" -Artist=smoke-test pixel.jpg >/dev/null 2>&1
    out=$(run "" "$IMAGE" -s3 -Artist pixel.jpg 2>&1)
    if [ ! -f "$D/pixel.jpg_original" ]; then
        fail jpeg_write "pixel.jpg_original missing on host"
    else
        expect_eq jpeg_write "$out" smoke-test
    fi
}

check_docx_read() {
    newdir
    cp "$FIX/sample.docx" "$D/"
    out=$(run "" "$IMAGE" -s3 -FileType -Creator sample.docx 2>&1)
    expect_eq docx_read "$out" "DOCX
smoke-fixture"
}

check_user_override() {
    newdir
    cp "$FIX/pixel.jpg" "$D/"
    run "" --user 4242:4242 "$IMAGE" -Artist=uid pixel.jpg >/dev/null 2>&1
    out=$(run "" "$IMAGE" -s3 -Artist pixel.jpg 2>&1)
    expect_eq user_override "$out" uid
}

check_unicode_filename() {
    newdir
    cp "$FIX/pixel.jpg" "$D/my photo ü.jpg"
    run "" "$IMAGE" -Artist=ü "my photo ü.jpg" >/dev/null 2>&1
    out=$(run "" "$IMAGE" -s3 -Artist "my photo ü.jpg" 2>&1)
    expect_eq unicode_filename "$out" ü
}

check_stdin_read() {
    newdir
    out=$(run "" -i "$IMAGE" -s3 -FileType - <"$FIX/pixel.jpg" 2>&1)
    expect_eq stdin_read "$out" JPEG
}

check_readonly_mount() {
    newdir
    cp "$FIX/pixel.jpg" "$D/"
    out=$(run ":ro" "$IMAGE" -s3 -FileType pixel.jpg 2>&1)
    expect_eq readonly_mount "$out" JPEG
}

check_version
check_non_root
check_perl_modules
check_jpeg_write
check_docx_read
check_user_override
check_unicode_filename
check_stdin_read
check_readonly_mount

exit "$FAILED"
