ARG ALPINE_VERSION=3.22

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
 && mkdir /out \
 && for b in mosquitto_pub mosquitto_sub mosquitto_rr; do \
      cp build/client/$b /out/ && strip /out/$b; \
      if readelf -d /out/$b | grep -q NEEDED; then echo "$b is not static" >&2; exit 1; fi; \
    done \
 && cd /out && sha256sum * > SHA256SUMS

FROM scratch
COPY --from=build /out/ /