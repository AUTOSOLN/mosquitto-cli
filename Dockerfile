ARG ALPINE_VERSION=3.22

# Static tcpdump, built against a static libpcap
FROM alpine:${ALPINE_VERSION} AS tcpdump
ARG TCPDUMP_VERSION=4.99.7
ARG LIBPCAP_VERSION=1.10.7

RUN apk add --no-cache build-base curl linux-headers flex bison pkgconf
WORKDIR /src

RUN curl -fsSL https://www.tcpdump.org/release/libpcap-${LIBPCAP_VERSION}.tar.gz | tar xz \
 && curl -fsSL https://www.tcpdump.org/release/tcpdump-${TCPDUMP_VERSION}.tar.gz | tar xz

RUN cd libpcap-${LIBPCAP_VERSION} \
 && ./configure --prefix=/usr/local --disable-shared \
      --disable-dbus --disable-rdma --disable-bluetooth --without-libnl \
 && make -j"$(nproc)" && make install

RUN cd tcpdump-${TCPDUMP_VERSION} \
 && PKG_CONFIG_PATH=/usr/local/lib/pkgconfig LDFLAGS="-static" \
      ./configure --without-crypto --without-smi --without-cap-ng \
 && make -j"$(nproc)" \
 && mkdir -p /out/licenses/tcpdump /out/licenses/libpcap \
 && cp tcpdump /out/ && strip /out/tcpdump \
 && if readelf -d /out/tcpdump | grep -q NEEDED; then echo "tcpdump is not static" >&2; exit 1; fi \
 && cp LICENSE /out/licenses/tcpdump/ \
 && cp ../libpcap-${LIBPCAP_VERSION}/LICENSE /out/licenses/libpcap/

FROM alpine:${ALPINE_VERSION} AS build
ARG MOSQUITTO_VERSION=2.1.2
ARG CJSON_VERSION=1.7.19

RUN apk add --no-cache build-base cmake ninja curl gnupg linux-headers patch \
        openssl-dev openssl-libs-static
WORKDIR /src

RUN curl -fsSLO https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz \
 && tar xzf mosquitto-${MOSQUITTO_VERSION}.tar.gz

# Version-specific fixes: applies patches/<MOSQUITTO_VERSION>/*.patch in order, if any
COPY patches/ /src/patches/
RUN for p in patches/${MOSQUITTO_VERSION}/*.patch; do \
      [ -e "$p" ] || continue; \
      echo "Applying $p"; \
      patch -d mosquitto-${MOSQUITTO_VERSION} -p1 --forward < "$p" || exit 1; \
    done

# Static cJSON
RUN curl -fsSL https://github.com/DaveGamble/cJSON/archive/refs/tags/v${CJSON_VERSION}.tar.gz | tar xz \
 && cmake -S cJSON-${CJSON_VERSION} -B cjson-build -G Ninja \
      -DBUILD_SHARED_LIBS=OFF -DENABLE_CJSON_TEST=OFF -DCMAKE_INSTALL_PREFIX=/usr/local \
 && cmake --build cjson-build && cmake --install cjson-build

# Clients only, fully static
RUN cmake -S mosquitto-${MOSQUITTO_VERSION} -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DWITH_BROKER=OFF -DWITH_APPS=OFF -DWITH_PLUGINS=OFF -DWITH_DOCS=OFF \
      -DWITH_LIB_CPP=OFF -DWITH_CLIENTS=ON \
      -DWITH_STATIC_LIBRARIES=ON -DWITH_SHARED_LIBRARIES=OFF \
      -DWITH_TLS=ON -DWITH_SRV=OFF -DWITH_WEBSOCKETS=OFF -DWITH_TESTS=OFF  \
      -DOPENSSL_USE_STATIC_LIBS=TRUE \
      -DCMAKE_EXE_LINKER_FLAGS="-static" \
 && cmake --build build \
 && mkdir -p /out \
 && for b in mosquitto_pub mosquitto_sub mosquitto_rr; do \
      cp build/client/$b /out/ && strip /out/$b; \
      if readelf -d /out/$b | grep -q NEEDED; then echo "$b is not static" >&2; exit 1; fi; \
    done

COPY --from=tcpdump /out/ /out/
RUN cd /out && sha256sum mosquitto_pub mosquitto_sub mosquitto_rr tcpdump > SHA256SUMS

# License texts for everything statically linked into the binaries (tcpdump and libpcap come from the tcpdump stage).
# Alpine doesn't ship license files, so OpenSSL's and musl's are fetched for the installed versions.
RUN set -e; mkdir -p /out/licenses/mosquitto /out/licenses/cjson /out/licenses/openssl /out/licenses/musl \
 && for f in LICENSE.txt NOTICE.md epl-v20 edl-v10; do cp mosquitto-${MOSQUITTO_VERSION}/$f /out/licenses/mosquitto/; done \
 && cp cJSON-${CJSON_VERSION}/LICENSE /out/licenses/cjson/ \
 && openssl_version=$(apk info -e -v libcrypto3 | sed 's/^libcrypto3-//; s/-r[0-9]*$//') \
 && musl_version=$(apk info -e -v musl | sed 's/^musl-//; s/-r[0-9]*$//') \
 && curl -fsSL -o /out/licenses/openssl/LICENSE.txt https://raw.githubusercontent.com/openssl/openssl/openssl-${openssl_version}/LICENSE.txt \
 && curl -fsSL -o /out/licenses/musl/COPYRIGHT "https://git.musl-libc.org/cgit/musl/plain/COPYRIGHT?h=v${musl_version}"

FROM scratch
COPY --from=build /out/ /