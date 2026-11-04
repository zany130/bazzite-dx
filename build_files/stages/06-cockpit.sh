#!/bin/bash

# 45Drives Cockpit packages and pinned GitHub release RPMs.
# Version pins are assigned in build.sh for Renovate. Sourced by build.sh.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/06-cockpit.sh from build.sh." >&2
    exit 1
fi

echo "Adding 45Drives repository..."
curl --fail-with-body --retry 3 -Lo /tmp/45drives.repo https://repo.45drives.com/lists/45drives.repo
dnf5 config-manager addrepo --from-repofile=/tmp/45drives.repo
curl --fail-with-body --retry 3 -Lo /tmp/45drives-gpg.asc https://repo.45drives.com/key/gpg.asc
rpm --import /tmp/45drives-gpg.asc
rm -f /tmp/45drives.repo /tmp/45drives-gpg.asc
dnf5 --refresh makecache

fortyfive_repolist="$(dnf5 repolist --all)"
fortyfive_repo_id="$(awk 'NR > 1 && $1 ~ /^45drives/ && $1 !~ /source|debuginfo/ {print $1; exit}' <<< "${fortyfive_repolist}")"
if [[ -z "${fortyfive_repo_id}" ]]; then
    echo "ERROR: Could not find 45Drives repository ID after adding repo." >&2
    exit 1
fi
dnf5 config-manager setopt "${fortyfive_repo_id}.enabled=0"
dnf5 --refresh --enable-repo="${fortyfive_repo_id}" install -y \
    cockpit-file-sharing \
    cockpit-navigator \
    cockpit-benchmark

install_pinned_rpm() {
    local sha256="${1}"
    local rpm_name="${2}"
    local url="${3}"

    echo "Downloading ${rpm_name}..."
    download_verified "${url}" "/tmp/${rpm_name}" "${sha256}"
    echo "Installing ${rpm_name}..."
    dnf5 install -y "/tmp/${rpm_name}"
    rm -f "/tmp/${rpm_name}"
}

COCKPIT_HARDWARE_PROBE_RELEASE_VERSION="$(loose_rpm_version "${COCKPIT_HARDWARE_PROBE_VERSION}")"
COCKPIT_HARDWARE_PROBE_RPM="cockpit-hardware-probe-${COCKPIT_HARDWARE_PROBE_RELEASE_VERSION}-1.noarch.rpm"
install_pinned_rpm \
    "${COCKPIT_HARDWARE_PROBE_SHA256}" \
    "${COCKPIT_HARDWARE_PROBE_RPM}" \
    "https://github.com/zany130/cockpit-probe/releases/download/${COCKPIT_HARDWARE_PROBE_VERSION}/${COCKPIT_HARDWARE_PROBE_RPM}"

COCKPIT_DIAGNOSTICS_RELEASE_VERSION="$(loose_rpm_version "${COCKPIT_DIAGNOSTICS_VERSION}")"
COCKPIT_DIAGNOSTICS_RPM="cockpit-diagnostics-${COCKPIT_DIAGNOSTICS_RELEASE_VERSION}-1.noarch.rpm"
install_pinned_rpm \
    "${COCKPIT_DIAGNOSTICS_SHA256}" \
    "${COCKPIT_DIAGNOSTICS_RPM}" \
    "https://github.com/zany130/cockpit-diagnostics/releases/download/${COCKPIT_DIAGNOSTICS_VERSION}/${COCKPIT_DIAGNOSTICS_RPM}"

# cockpit-nspawn publishes the same RPM under more than one release tag.
COCKPIT_NSPAWN_RPM="cockpit-nspawn-${COCKPIT_NSPAWN_VERSION#v}.fc44.noarch.rpm"
echo "Downloading ${COCKPIT_NSPAWN_RPM}..."
COCKPIT_NSPAWN_RELEASE_TAGS=(
    "cockpit-nspawn-${COCKPIT_NSPAWN_VERSION}"
    "${COCKPIT_NSPAWN_VERSION}"
)
for cockpit_nspawn_release_tag in "${COCKPIT_NSPAWN_RELEASE_TAGS[@]}"; do
    COCKPIT_NSPAWN_URL="https://github.com/realmcuser/cockpit-nspawn/releases/download/${cockpit_nspawn_release_tag}/${COCKPIT_NSPAWN_RPM}"
    if curl --fail-with-body --retry 3 -Lo "/tmp/${COCKPIT_NSPAWN_RPM}" "${COCKPIT_NSPAWN_URL}" && [ -s "/tmp/${COCKPIT_NSPAWN_RPM}" ]; then
        break
    fi
    rm -f "/tmp/${COCKPIT_NSPAWN_RPM}"
done
if [ ! -s "/tmp/${COCKPIT_NSPAWN_RPM}" ]; then
    echo "Failed to download ${COCKPIT_NSPAWN_RPM}" >&2
    exit 1
fi

echo "Verifying checksum..."
verify_sha256 "/tmp/${COCKPIT_NSPAWN_RPM}" "${COCKPIT_NSPAWN_SHA256}"

echo "Installing ${COCKPIT_NSPAWN_RPM}..."
mkdir -p /var/usrlocal
rpm2cpio "/tmp/${COCKPIT_NSPAWN_RPM}" | (cd / && cpio -idm --quiet --no-absolute-filenames \
    './usr/local/lib/nspawn-pull*' \
    './usr/share/cockpit/nspawn*')
rm -f "/tmp/${COCKPIT_NSPAWN_RPM}"
