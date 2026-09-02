# Ubuntu 22.04 provides GLIBC 2.35, the oldest supported runtime for the
# generated package.  Do not change this base image without reviewing that
# compatibility guarantee.
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG ARDUINO_CLI_VERSION=1.3.1
# AVR core is not part of the frozen application or its .deb.  Keep its
# download opt-in because Arduino's public index service can be unavailable
# from a build network (and is not needed to create the package).
ARG INSTALL_ARDUINO_AVR_CORE=false

# Unreliable IPv6 routes are common on CI and corporate networks.  Configure
# APT before its first request and use one mirror for both archive and security
# repositories so package downloads use the same, retryable route.
RUN printf '%s\n' \
        'Acquire::ForceIPv4 "true";' \
        'Acquire::Retries "5";' \
        'Acquire::http::Timeout "60";' \
        'Acquire::https::Timeout "60";' \
        'Acquire::http::Pipeline-Depth "0";' \
        > /etc/apt/apt.conf.d/99network-resilience \
    && sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu/|http://mirror.yandex.ru/ubuntu/|g' \
        -e 's|http://security.ubuntu.com/ubuntu/|http://mirror.yandex.ru/ubuntu/|g' \
        /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils \
        python3.10 \
        python3.10-dev \
        libpython3.10 \
        libpython3.10-dev \
        python3-pip \
        gcc-arm-none-eabi \
        binutils-arm-none-eabi \
        make \
        dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# Arduino CLI is not shipped by Ubuntu 22.04.  Install a pinned upstream
# release.  The optional AVR core is used by ArduinoUno and ArduinoMicro.
RUN curl --fail --location --ipv4 --retry 5 --retry-all-errors \
        --connect-timeout 20 --max-time 300 \
        -o /tmp/arduino-cli.tar.xz \
        "https://github.com/arduino/arduino-cli/releases/download/v${ARDUINO_CLI_VERSION}/arduino-cli_${ARDUINO_CLI_VERSION}_Linux_64bit.tar.gz" \
    && tar -xzf /tmp/arduino-cli.tar.xz -C /usr/local/bin arduino-cli \
    && rm /tmp/arduino-cli.tar.xz \
    && if [ "$INSTALL_ARDUINO_AVR_CORE" = 'true' ]; then \
           arduino-cli core update-index \
           && arduino-cli core install arduino:avr; \
       fi

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=120 \
    PIP_RETRIES=5 \
    PYTHONUNBUFFERED=1

WORKDIR /src
COPY . /src

# PyInstaller itself is deliberately installed in the builder only: the final
# package contains its frozen executable, never this source tree or a venv.
# Keep an LF-normalized entry point outside /src.  At run time /src is a host
# bind mount; Windows checkouts may otherwise pass CRLF shell code to bash.
RUN python3.10 -m pip install --no-cache-dir --retries 5 --timeout 120 . pyinstaller \
    && sed -i 's/\r$//' packaging/build-linux.sh \
    && install -m 0755 packaging/build-linux.sh /usr/local/bin/lapki-build-linux

ENTRYPOINT ["/usr/local/bin/lapki-build-linux"]
