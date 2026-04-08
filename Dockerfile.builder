# Custom builder image for Paloma Morse
# Includes Node.js, Electron Builder dependencies (Wine), and Mingw-w64 for C++ compilation

FROM electronuserland/builder:wine

# Fix: electronuserland images sometimes have outdated keys or sources
# We pre-install mingw-w64 and basic build tools to avoid doing this in CI
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    mingw-w64 \
    g++ \
    make \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Verify installations
RUN x86_64-w64-mingw32-g++ --version && g++ --version
