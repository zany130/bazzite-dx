#!/bin/bash

# Repository setup: version locks, Terra, RPM Fusion, and Docker.
# Sourced by build.sh. Terra and RPM Fusion stay disabled except where a later
# transaction opts in. Docker is written disabled and enabled per transaction.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/01-repositories.sh from build.sh." >&2
    exit 1
fi

# Keep Qt and Plasma on one version so a later transaction cannot mix them.
dnf5 versionlock add 'qt6-*' 'plasma-*'

# Keep Terra disabled except for transactions that explicitly need it.
# Fedora 45 ships the packaged definition in /usr/share/dnf5/repos.d/terra.repo.
# Appending options to a missing /etc/yum.repos.d/terra.repo creates a file
# with no section header and makes every later dnf5 command fail. Overrides
# belong in /etc/dnf/repos.override.d, which config-manager maintains.
echo 'Configuring Terra Repository.'
configure_terra_repository

# RPM Fusion may already be present on the base image. Bootstrap the release
# package only when that family is missing, then disable it and remember the
# ids for the one transaction that needs it.
echo 'Configuring RPM Fusion Repository.'
fedora_version="$(rpm -E %fedora)"
if ! [[ "${fedora_version}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Unable to determine Fedora version for RPM Fusion bootstrap: '${fedora_version}'. Verify the base image is Fedora and 'rpm -E %fedora' returns a numeric release." >&2
    exit 1
fi

ensure_rpmfusion_release_repo \
    rpmfusion-free \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm"
ensure_rpmfusion_release_repo \
    rpmfusion-nonfree \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

rpmfusion_repo_args=()
scope_rpmfusion_repo_family rpmfusion-free
scope_rpmfusion_repo_family rpmfusion-nonfree
if ((${#rpmfusion_repo_args[@]} == 0)); then
    echo "ERROR: No RPM Fusion repositories are available for scoped installs." >&2
    exit 1
fi

# SHA256 verified from https://download.docker.com/linux/fedora/gpg on 2026-07-10.
echo 'Configuring Docker repository.'
DOCKER_GPG_SHA256="e6c650e0700b1bf4868b693b30761b926844befc8a0acb7ac0dd9b1faf1b7423"
download_verified \
    "https://download.docker.com/linux/fedora/gpg" \
    /tmp/docker-gpg \
    "${DOCKER_GPG_SHA256}"
rpm --import /tmp/docker-gpg
rm -f /tmp/docker-gpg
cat > /etc/yum.repos.d/docker-ce.repo <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/fedora/$releasever/$basearch/stable
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg

[docker-ce-stable-source]
name=Docker CE Stable - Sources
baseurl=https://download.docker.com/linux/fedora/$releasever/source/stable
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg

EOF

dnf5 --refresh makecache
