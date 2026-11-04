#!/bin/bash

# General system packages from repositories already enabled on the Deck base.
# Bazzite repositories may participate. This is not the upstream DX layer.
# Sourced by build.sh. The transaction stays separate from DX and third-party sets.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/02-fedora-packages.sh from build.sh." >&2
    exit 1
fi

fedora_packages=(
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
    mosh
    nmap
)

dnf5 install -y "${fedora_packages[@]}"
