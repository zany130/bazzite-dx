#!/bin/bash

# Ordinary additional repositories: Terra, RPM Fusion, Docker CE, 45Drives,
# and Punktfunk. COPRs stay out of this stage and are registered on demand.
# Sourced by build.sh. Every repo here is disabled before the closing
# makecache, so later stages opt in per transaction.
#
# 45Drives publishes 45drives_stable with enabled=1 and priority=1. The old
# Cockpit stage refreshed metadata while that repo was still enabled, then
# disabled it before installing. Registration now happens before Fedora and
# DX installs, so the repo is disabled immediately and the install in Stage 06
# refreshes it with --enable-repo. The closing makecache does not need to
# see 45Drives or Punktfunk; both package transactions use --refresh.

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

# The upstream repo file enables 45drives_stable. Disable that id before any
# package transaction. fortyfive_repo_id is reused by stages/06-cockpit.sh.
echo "Adding 45Drives repository..."
curl --fail-with-body --retry 3 -Lo /tmp/45drives.repo https://repo.45drives.com/lists/45drives.repo
dnf5 config-manager addrepo --from-repofile=/tmp/45drives.repo
curl --fail-with-body --retry 3 -Lo /tmp/45drives-gpg.asc https://repo.45drives.com/key/gpg.asc
rpm --import /tmp/45drives-gpg.asc
rm -f /tmp/45drives.repo /tmp/45drives-gpg.asc
fortyfive_repolist="$(dnf5 repolist --all)"
fortyfive_repo_id="$(awk 'NR > 1 && $1 ~ /^45drives/ && $1 !~ /source|debuginfo/ {print $1; exit}' <<< "${fortyfive_repolist}")"
if [[ -z "${fortyfive_repo_id}" ]]; then
    echo "ERROR: Could not find 45Drives repository ID after adding repo." >&2
    exit 1
fi
dnf5 config-manager setopt "${fortyfive_repo_id}.enabled=0"

# Use Punktfunk's signed Bazzite RPMs for streaming in Gaming Mode and KDE.
# The file is disabled here. Stage 04 opts into one install transaction, and
# Stage 08 disables the user service that the RPM enables.
cat > /etc/yum.repos.d/punktfunk.repo <<'EOF'
[gitea-unom-bazzite]
name=Punktfunk (unom, Bazzite)
baseurl=https://git.unom.io/api/packages/unom/rpm/bazzite
enabled=0
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://git.unom.io/api/packages/unom/rpm/repository.key
       https://git.unom.io/api/packages/unom/generic/punktfunk-keys/1/RPM-GPG-KEY-punktfunk
EOF

dnf5 --refresh makecache
