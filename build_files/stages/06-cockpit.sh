#!/bin/bash

# Bazzite's web server connects to the host bridge over SSH. Keep custom
# pages on the host. cockpit-machines may install libvirt without Stage 03.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/06-cockpit.sh from build.sh." >&2
    exit 1
fi

# Normally enabled repositories only. 45Drives is not enabled for this install.
# cockpit-benchmark requires cockpit, whose web server RPM replaces Deck's
# vendor cockpit.service. Preserve the base wrapper at systemd's higher
# priority path so ujust cockpit still starts the Quadlet after that install.
wrapper=/usr/lib/systemd/system/cockpit.service
grep -Fxq 'Requires=cockpit-container.service' "${wrapper}"
install -Dm0644 "${wrapper}" /etc/systemd/system/cockpit.service

dnf5 install -y cockpit-machines cockpit-ostree

# Filled by stages/01-repositories.sh in this same shell.
# shellcheck disable=SC2154
dnf5 --refresh --enable-repo="${fortyfive_repo_id}" install -y \
    cockpit-file-sharing \
    cockpit-navigator \
    cockpit-benchmark

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

# cockpit-nspawn publishes the same RPM under more than one release tag and
# is unpacked with cpio rather than installed as a package, so it does not
# use install_pinned_rpm.
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
