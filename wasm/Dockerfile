# syntax=docker/dockerfile:1.7

ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS builder
ARG FLYE_SOURCE_TARBALL=scripts/flye-patch/flye-src-886b8c1.tar.gz
ARG JOBS=4
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        build-essential \
        ca-certificates \
        file \
        python3 \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/flye-src
COPY ${FLYE_SOURCE_TARBALL} /tmp/flye-source.tar.gz

RUN tar -xzf /tmp/flye-source.tar.gz -C /opt/flye-src \
    && rm /tmp/flye-source.tar.gz \
    && mkdir -p bin \
    && (cd lib/samtools-1.9/htslib-1.9 && autoheader && autoconf -Wno-syntax) \
    && (cd lib/samtools-1.9 && autoheader && autoconf -Wno-syntax) \
    && if ! (cd lib/samtools-1.9 \
        && ./configure --without-curses --disable-bz2 --disable-lzma --enable-plugins); then \
        printf '\n===== samtools config.log =====\n' >&2; \
        cat lib/samtools-1.9/config.log >&2 || true; \
        printf '\n===== htslib config.log =====\n' >&2; \
        cat lib/samtools-1.9/htslib-1.9/config.log >&2 || true; \
        exit 1; \
    fi \
    && make THREADS="${JOBS}" -j"${JOBS}" \
    && test -x bin/flye-modules \
    && test -x bin/flye-minimap2 \
    && test -x bin/flye-samtools \
    && python3 bin/flye --version

FROM ubuntu:${UBUNTU_VERSION} AS runtime
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libstdc++6 \
        python3 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/flye-src/bin/flye /opt/flye/bin/flye
COPY --from=builder /opt/flye-src/bin/flye-modules /opt/flye/bin/flye-modules
COPY --from=builder /opt/flye-src/bin/flye-minimap2 /opt/flye/bin/flye-minimap2
COPY --from=builder /opt/flye-src/bin/flye-samtools /opt/flye/bin/flye-samtools
COPY --from=builder /opt/flye-src/flye /opt/flye/flye
COPY --from=builder /opt/flye-src/LICENSE /opt/flye/LICENSE

RUN chmod 0755 /opt/flye/bin/flye /opt/flye/bin/flye-* \
    && ln -s /opt/flye/bin/flye /usr/local/bin/flye \
    && ln -s /opt/flye/bin/flye-modules /usr/local/bin/flye-modules \
    && ln -s /opt/flye/bin/flye-minimap2 /usr/local/bin/flye-minimap2 \
    && ln -s /opt/flye/bin/flye-samtools /usr/local/bin/flye-samtools \
    && mkdir -p /work/.tmp \
    && python3 /opt/flye/bin/flye --version

ENV PATH=/opt/flye/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/work/.tmp

WORKDIR /work
ENTRYPOINT ["/opt/flye/bin/flye"]
CMD ["--help"]
