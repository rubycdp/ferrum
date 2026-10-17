ARG BROWSER=chromium
ARG GO_VERSION=1.27
ARG DEBIAN_VERSION=trixie

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-${DEBIAN_VERSION} AS build
ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath \
    -ldflags="-s -w -X github.com/rubycdp/ferrum/docker/internal/config.Version=${VERSION}" \
    -o /out/driver .

FROM --platform=$BUILDPLATFORM debian:${DEBIAN_VERSION}-slim AS fonts
ARG SELAWIK_SHA256=3f62c51e05e3b5a1e6241cf92a371f0be2ea1183aa87b30718bbd40832a8d423
ADD --checksum=sha256:${SELAWIK_SHA256} \
    https://github.com/microsoft/Selawik/releases/download/1.01/Selawik_Release.zip /tmp/selawik.zip
RUN apt-get update && apt-get install -y --no-install-recommends unzip \
    && mkdir -p /out/selawik && unzip -j /tmp/selawik.zip '*.ttf' -d /out/selawik

FROM debian:${DEBIAN_VERSION}-slim AS base
LABEL org.opencontainers.image.source=https://github.com/rubycdp/ferrum
LABEL org.opencontainers.image.licenses=MIT

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=UTC

RUN printf 'APT::Install-Recommends "false";\n' > /etc/apt/apt.conf.d/99no-recommends \
    && apt-get update && apt-get install -y \
      ca-certificates \
      curl \
      dumb-init \
      tzdata \
      xvfb \
      fontconfig \
      fonts-crosextra-caladea \
      fonts-crosextra-carlito \
      fonts-dejavu-core \
      fonts-freefont-ttf \
      fonts-gfs-neohellenic \
      fonts-indic \
      fonts-ipafont-gothic \
      fonts-liberation \
      fonts-noto-cjk \
      fonts-noto-color-emoji \
      fonts-open-sans \
      fonts-roboto \
      fonts-thai-tlwg \
      fonts-wqy-zenhei \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fonts /out/selawik /usr/share/fonts/truetype/selawik
COPY deploy/fonts.conf /etc/fonts/local.conf
RUN fc-cache -f

FROM base AS chromium
ARG BROWSER_VERSION
RUN apt-get update && apt-get install -y chromium \
    && rm -rf /var/lib/apt/lists/*
ENV BROWSER_PATH=/usr/bin/chromium

FROM base AS chrome
ARG TARGETARCH
ARG BROWSER_VERSION
RUN curl -fsSL --retry 5 --retry-all-errors -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_${TARGETARCH}.deb \
    && apt-get update && apt-get install -y /tmp/chrome.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/chrome.deb
ENV BROWSER_PATH=/usr/bin/google-chrome

FROM ${BROWSER}
ARG VERSION=dev
LABEL org.opencontainers.image.revision=${VERSION}

RUN mkdir -p /home/driver /tmp/.X11-unix && chmod 1777 /home/driver /tmp/.X11-unix \
    && useradd --uid 999 --home-dir /home/driver --no-create-home --shell /usr/sbin/nologin driver

ENV HOME=/home/driver \
    XDG_CONFIG_HOME=/home/driver/.config \
    XDG_CACHE_HOME=/home/driver/.cache

COPY --from=build /out/driver /usr/local/bin/driver

USER driver
WORKDIR /home/driver
EXPOSE 3000
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-3000}/health" || exit 1

ENTRYPOINT ["dumb-init", "--", "driver"]
