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
# The pinned source archive does not contain every runtime configuration asset.
# Overlay the repository's complete, version-matched configuration bundle so
# C++ modules can resolve %include directives and polishing matrices at runtime.
COPY flye/config/bin_cfg /tmp/flye-bin-cfg

RUN tar -xzf /tmp/flye-source.tar.gz -C /opt/flye-src \
    && rm /tmp/flye-source.tar.gz \
    && install -d flye/config/bin_cfg \
    && cp -a /tmp/flye-bin-cfg/. flye/config/bin_cfg/ \
    && rm -rf /tmp/flye-bin-cfg \
    && test -s flye/config/bin_cfg/asm_defaults.cfg \
    && test -s flye/config/bin_cfg/asm_corrected_reads.cfg \
    && for include in $(awk '$1 == "%include" {print $2}' flye/config/bin_cfg/*.cfg | sort -u); do \
        test -s "flye/config/bin_cfg/${include}"; \
    done \
    && sed -i 's/\r$//' bin/flye \
    && find flye -type f -name '*.py' -exec sed -i 's/\r$//' {} + \
    # The container2wasm guest exposes roughly 1 GiB of usable RAM to Flye. \
    # Upstream consensus sorting requests 1 GiB per worker with four workers, \
    # which cannot fit alongside minimap2 and the guest OS. Keep this image's \
    # sort deterministic and bounded for the WASM verification workload. \
    && sed -i 's/^    SORT_THREADS = "4"$/    SORT_THREADS = "1"/' flye/polishing/alignment.py \
    && sed -i 's/^    SORT_MEM = "4G" if os.path.getsize(reference_file) > 100 \* 1024 \* 1024 else "1G"$/    SORT_MEM = "128M"/' flye/polishing/alignment.py \
    && grep -q '^    SORT_THREADS = "1"$' flye/polishing/alignment.py \
    && grep -q '^    SORT_MEM = "128M"$' flye/polishing/alignment.py \
    && mkdir -p bin \
    && install -m 0755 \
        /usr/share/autoconf/build-aux/config.guess \
        lib/samtools-1.9/htslib-1.9/config.guess \
    && install -m 0644 \
        /usr/share/autoconf/build-aux/config.sub \
        lib/samtools-1.9/htslib-1.9/config.sub \
    && (cd lib/samtools-1.9/htslib-1.9 && autoheader && autoconf -Wno-syntax) \
    && (cd lib/samtools-1.9 && autoheader && autoconf -Wno-syntax) \
    && HOST_TRIPLET="$(lib/samtools-1.9/htslib-1.9/config.guess)" \
    && if ! (cd lib/samtools-1.9 \
        && ./configure --host="${HOST_TRIPLET}" --without-curses --disable-bz2 --disable-lzma --enable-plugins); then \
        printf '\n===== samtools config.log =====\n' >&2; \
        cat lib/samtools-1.9/config.log >&2 || true; \
        printf '\n===== htslib config.log =====\n' >&2; \
        cat lib/samtools-1.9/htslib-1.9/config.log >&2 || true; \
        exit 1; \
    fi \
    && make samtools -C lib/samtools-1.9 -j"${JOBS}" \
    && cp lib/samtools-1.9/samtools bin/flye-samtools \
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
    && test -s /opt/flye/flye/config/bin_cfg/asm_defaults.cfg \
    && test -s /opt/flye/flye/config/bin_cfg/asm_corrected_reads.cfg \
    && for include in $(awk '$1 == "%include" {print $2}' /opt/flye/flye/config/bin_cfg/*.cfg | sort -u); do \
        test -s "/opt/flye/flye/config/bin_cfg/${include}"; \
    done \
    && mkdir -p /work/.tmp \
    && python3 /opt/flye/bin/flye --version

ENV PATH=/opt/flye/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TMPDIR=/work/.tmp

WORKDIR /work
CMD ["/opt/flye/bin/flye", "--help"]
