# renovate: datasource=github-tags depName=exiftool/exiftool versioning=loose
ARG EXIFTOOL_VERSION=13.61
ARG EXIFTOOL_COMMIT=9b8664dfcf2c609d3cc8925d380e98ad2a379f9b
# renovate: datasource=repology depName=alpine_3_24/perl versioning=loose
ARG PERL_VERSION=5.42.3-r0
# renovate: datasource=repology depName=alpine_3_24/perl-archive-zip versioning=loose
ARG PERL_ARCHIVE_ZIP_VERSION=1.68-r3

FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS source
ARG EXIFTOOL_VERSION
ARG EXIFTOOL_COMMIT
# git and perl are deliberately unpinned: they only exist in this throwaway stage, and the
# commit/version check below is what guarantees the shipped content.
RUN apk add --no-cache git perl
WORKDIR /src
RUN git init -q . \
    && git fetch -q --depth 1 https://github.com/exiftool/exiftool.git "$EXIFTOOL_COMMIT" \
    && git checkout -q FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "$EXIFTOOL_COMMIT" \
    && test "$(perl ./exiftool -ver 2>/dev/null || true)" = "$EXIFTOOL_VERSION"

FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf
ARG PERL_VERSION
ARG PERL_ARCHIVE_ZIP_VERSION
LABEL org.opencontainers.image.licenses="Artistic-1.0-Perl OR GPL-1.0-or-later" \
      org.opencontainers.image.title="exiftool"
RUN apk add --no-cache "perl=$PERL_VERSION" "perl-archive-zip=$PERL_ARCHIVE_ZIP_VERSION"
COPY --from=source /src/exiftool /opt/exiftool/exiftool
COPY --from=source /src/lib /opt/exiftool/lib
RUN ln -s /opt/exiftool/exiftool /usr/local/bin/exiftool \
    && addgroup -g 1000 exiftool \
    && adduser -D -H -u 1000 -G exiftool -s /sbin/nologin exiftool
USER 1000:1000
WORKDIR /data
ENTRYPOINT ["exiftool"]
