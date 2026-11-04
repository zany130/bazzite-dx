#!/bin/bash

# Download helpers for build.sh.
# Sourced into the image build; executing this file does not install anything.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source lib/common.sh from build.sh." >&2
    exit 1
fi

# Check a downloaded file against a pinned SHA-256.
# Two spaces match the format `sha256sum -c` expects.
verify_sha256() {
    local dest="${1}"
    local sha256="${2}"

    echo "${sha256}  ${dest}" | sha256sum -c -
}

# Download with the same retry flags previously inlined at each call site.
download_verified() {
    local url="${1}"
    local dest="${2}"
    local sha256="${3}"

    curl --fail-with-body --retry 3 -Lo "${dest}" "${url}"
    verify_sha256 "${dest}" "${sha256}"
}

# Download a pinned RPM, verify it, install it, and remove the temporary file.
# install_pinned_rpm SHA256 RPM_FILENAME URL
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

# GitHub tags v1.0 and V1.0 are published as 1.0.0 RPM versions.
loose_rpm_version() {
    local version="${1#[Vv]}"

    if [[ "${version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        version="${version}.0"
    fi
    printf '%s\n' "${version}"
}
