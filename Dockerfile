FROM debian:trixie-slim

ARG WINE_BRANCH=devel
ARG WINE_VERSION=11.16
ARG DEBIAN_CODENAME=trixie

LABEL org.opencontainers.image.title="cfx-server-wine" \
      org.opencontainers.image.description="Pterodactyl image running the Cfx (FiveM Enhanced) Windows server under Wine ${WINE_VERSION}" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL -o /etc/apt/keyrings/winehq-archive.key \
        https://dl.winehq.org/wine-builds/winehq.key; \
    curl -fsSL -o "/etc/apt/sources.list.d/winehq-${DEBIAN_CODENAME}.sources" \
        "https://dl.winehq.org/wine-builds/debian/dists/${DEBIAN_CODENAME}/winehq-${DEBIAN_CODENAME}.sources"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        "winehq-${WINE_BRANCH}=${WINE_VERSION}~${DEBIAN_CODENAME}-1" \
        cabextract \
        fonts-liberation \
        locales \
        procps \
        tzdata \
        unzip \
        winbind \
        xvfb \
        xz-utils; \
    "/opt/wine-${WINE_BRANCH}/bin/wine" --version; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

ENV PATH="/opt/wine-${WINE_BRANCH}/bin:${PATH}"

RUN useradd -m -d /home/container -s /bin/bash container

ENV USER=container \
    HOME=/home/container \
    WINEPREFIX=/home/container/.wine \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    DISPLAY=:0 \
    DISPLAY_WIDTH=1024 \
    DISPLAY_HEIGHT=768 \
    DISPLAY_DEPTH=16 \
    LANG=C.UTF-8 \
    TZ=UTC

COPY --chmod=0755 entrypoint.sh /entrypoint.sh

USER container
WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]
