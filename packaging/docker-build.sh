#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [--no-cache] [--with-arduino-avr] [--ubuntu-mirror HOST] [--pypi-mirror URL]\n' "${0##*/}"
}

build_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-cache) build_args+=(--no-cache) ;;
        --with-arduino-avr)
            build_args+=(--build-arg INSTALL_ARDUINO_AVR_CORE=true) ;;
        --ubuntu-mirror)
            shift
            if [[ $# -eq 0 || "$1" == -* ]]; then
                usage >&2
                exit 2
            fi
            build_args+=(--build-arg "UBUNTU_MIRROR=$1") ;;
        --pypi-mirror)
            shift
            if [[ $# -eq 0 || "$1" == -* ]]; then
                usage >&2
                exit 2
            fi
            build_args+=(--build-arg "PIP_INDEX_URL=$1") ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
image_name='lapki-compiler-builder:local'

docker build "${build_args[@]}" -t "$image_name" "$project_root"
docker run --rm -v "$project_root:/src" "$image_name"
