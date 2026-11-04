#!/bin/bash

# Custom third-party packages. Docker CE is upstream DX and stays in Stage 03.
# Each transaction opts into its own disabled repository. Sourced by build.sh.
# rpmfusion_repo_args is filled by stages/01-repositories.sh.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/04-third-party-packages.sh from build.sh." >&2
    exit 1
fi

# Terra
dnf_install_with_retry terra \
    coolercontrol \
    sbctl \
    topgrade

# RPM Fusion
# shellcheck disable=SC2154
dnf5 --refresh "${rpmfusion_repo_args[@]}" install -y \
    dolphin-megasync \
    megasync

# Punktfunk
dnf5 --refresh --enable-repo=gitea-unom-bazzite install -y \
    punktfunk \
    punktfunk-web \
    punktfunk-scripting
