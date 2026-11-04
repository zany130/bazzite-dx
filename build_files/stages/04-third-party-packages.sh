#!/bin/bash

# Custom third-party packages. Docker CE is upstream DX and stays in Stage 03.
# Each transaction opts into its own disabled repository. Sourced by build.sh.
# rpmfusion_repo_args is filled by stages/01-repositories.sh.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/04-third-party-packages.sh from build.sh." >&2
    exit 1
fi

terra_install_attempts=3
terra_install_succeeded=0
for ((terra_install_attempt=1; terra_install_attempt<=terra_install_attempts; terra_install_attempt++)); do
    echo "Installing Terra packages (attempt ${terra_install_attempt}/${terra_install_attempts})."
    if dnf5 --refresh --enable-repo=terra install -y \
        coolercontrol \
        sbctl \
        topgrade; then
        terra_install_succeeded=1
        break
    fi

    if (( terra_install_attempt < terra_install_attempts )); then
        echo "Terra package install failed on attempt ${terra_install_attempt}/${terra_install_attempts}; cleaning Terra metadata before retrying." >&2
        dnf5 clean all --enable-repo=terra
    fi
done

if (( terra_install_succeeded == 0 )); then
    echo "ERROR: Failed to install Terra packages (coolercontrol, sbctl, topgrade) after ${terra_install_attempts} attempts." >&2
    exit 1
fi

# Filled by stages/01-repositories.sh in this same shell.
# shellcheck disable=SC2154
dnf5 --refresh "${rpmfusion_repo_args[@]}" install -y \
    dolphin-megasync \
    megasync

# Include the web console and scripting runner explicitly, rather than relying
# on weak dependencies. Stage 08 disables the user service this RPM enables.
# User pairing and firewall access stay out of the image build.
dnf5 --refresh --enable-repo=gitea-unom-bazzite install -y \
    punktfunk \
    punktfunk-web \
    punktfunk-scripting
