#!/bin/bash

# Packages installed from the repositories already enabled on the base image.
# Sourced by build.sh. This stays a separate transaction from DX and third-party sets.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/02-base-packages.sh from build.sh." >&2
    exit 1
fi

base_packages=(
    beep
    btfs
    bsdtar
    google-authenticator
    kvantum
    liquidctl
    mpv
    python3-pygame
    rEFInd
    rEFInd-tools
    solaar
    tesseract
    tesseract-langpack-eng
    tesseract-langpack-spa
    tesseract-libs
    mosh
    nmap
)

dnf5 install -y "${base_packages[@]}"
