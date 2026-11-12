# Debian 10 supplies glibc 2.28 and GCC 8's libstdc++ (GLIBCXX <= 3.4.25).
# Pin the amd64 buster-slim manifest; the shipped Linux AppImage is x86_64.
FROM debian:buster-slim@sha256:32220ea48be72979c9f0810d69f3de9145c9584c2ee966c6ec26edbcf4640c0b

# Buster is archived. Keep signature verification; only disable the expired
# metadata freshness check for these historical repositories.
RUN printf '%s\n' \
      'deb http://archive.debian.org/debian buster main' \
      'deb http://archive.debian.org/debian-security buster/updates main' \
      > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends \
      g++ libasound2-dev binutils python3 python3-websocket \
      pulseaudio pulseaudio-utils xvfb xauth \
      libgtk-3-0 libnss3 libnspr4 libatk-bridge2.0-0 libdrm2 libgbm1 \
      libx11-xcb1 libxcomposite1 libxdamage1 libxrandr2 libxss1 \
      libxtst6 libxkbcommon0 libcups2 libsecret-1-0 libnotify4 \
      fonts-liberation ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 1000 --create-home paloma

WORKDIR /workspace
