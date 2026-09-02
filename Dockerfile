# Ubuntu 20.04 provides GLIBC 2.31, the oldest supported runtime for the
# generated package.  Do not change this base image without reviewing that
# compatibility guarantee.
FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
# Focal is still available from the primary archive.  Override this hostname
# for a reachable full APT mirror when the build network requires it.
ARG UBUNTU_MIRROR=archive.ubuntu.com
ARG PYTHON_VERSION=3.10.21
ARG PYTHON_SHA256=a0da1e72132e950154eca0f6f47d5db828454700de20e5113667940d81e0db04
ARG ARDUINO_CLI_VERSION=1.3.1
# Override for a reachable PEP 503-compatible PyPI mirror when required.
ARG PIP_INDEX_URL=https://pypi.org/simple
# AVR core is not part of the frozen application or its .deb.  Keep its
# download opt-in because Arduino's public index service can be unavailable
# from a build network (and is not needed to create the package).
ARG INSTALL_ARDUINO_AVR_CORE=false

# Unreliable IPv6 routes are common on CI and corporate networks.  Configure
# APT before its first request and use one configurable mirror for archive and
# security repositories.  old-releases.ubuntu.com stores installation images,
# not the focal APT repository, so it must not be used here.
RUN printf '%s\n' \
        'Acquire::ForceIPv4 "true";' \
        'Acquire::Retries "5";' \
        'Acquire::http::Timeout "60";' \
        'Acquire::https::Timeout "60";' \
        'Acquire::http::Pipeline-Depth "0";' \
        > /etc/apt/apt.conf.d/99network-resilience \
    && sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu/|http://${UBUNTU_MIRROR}/ubuntu/|g" \
        -e "s|http://security.ubuntu.com/ubuntu/|http://${UBUNTU_MIRROR}/ubuntu/|g" \
        /etc/apt/sources.list \
    && printf '%s\n' 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils \
        binutils \
        build-essential \
        zlib1g-dev \
        libssl-dev \
        libffi-dev \
        libbz2-dev \
        liblzma-dev \
        libreadline-dev \
        libsqlite3-dev \
        libgdbm-dev \
        libncursesw5-dev \
        uuid-dev \
        gcc-arm-none-eabi \
        binutils-arm-none-eabi \
        make \
        dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# deadsnakes no longer carries a complete Python 3.10 package set for Focal.
# Build a checksum-pinned CPython here to keep both Python and libpython built
# against Focal's GLIBC 2.31, without taking packages from a newer release.
RUN curl --fail --location --ipv4 --retry 5 --retry-delay 2 \
        --connect-timeout 20 --max-time 300 \
        -o /tmp/python.tar.xz \
        "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" \
    && echo "${PYTHON_SHA256}  /tmp/python.tar.xz" | sha256sum --check --status \
    && mkdir /tmp/python-source \
    && tar -xJf /tmp/python.tar.xz -C /tmp/python-source --strip-components=1 \
    && cd /tmp/python-source \
    && ./configure --prefix=/opt/python-3.10 --enable-shared --with-ensurepip=install \
    && make -j"$(nproc)" \
    && make install \
    && printf '%s\n' '/opt/python-3.10/lib' > /etc/ld.so.conf.d/python3.10.conf \
    && ldconfig \
    && ln -s /opt/python-3.10/bin/python3.10 /usr/local/bin/python3.10 \
    && rm -rf /tmp/python.tar.xz /tmp/python-source

# Arduino CLI is not shipped by Ubuntu 20.04.  Install a pinned upstream
# release.  The optional AVR core is used by ArduinoUno and ArduinoMicro.
RUN curl --fail --location --ipv4 --retry 5 --retry-delay 2 \
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
    PIP_INDEX_URL=${PIP_INDEX_URL} \
    PYTHONUNBUFFERED=1 \
    PATH=/opt/python-3.10/bin:$PATH

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
