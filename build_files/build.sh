#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPM Fusion repos may be provided by the base image, but bootstrap them if absent.
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# Enable Terra Repository
echo 'Enabling Terra Repository.'
sed -i 's@enabled=0@enabled=1@g' /etc/yum.repos.d/terra.repo

# Enable RPM Fusion Repository
echo 'Enabling RPM Fusion Repository.'
get_available_repos() {
    dnf5 repolist --all | awk 'NR > 1 && $1 != "" {print $1}'
}

repo_matches_family() {
    local repo_id="${1}"
    local repo_family="${2}"

    case "${repo_id}" in
        "${repo_family}"|"${repo_family}"-*)
            return 0
            ;;
    esac

    return 1
}

ensure_rpmfusion_release_repo() {
    local repo_family="${1}"
    local repo_url="${2}"
    local available_repos
    available_repos="$(get_available_repos)"
    while IFS= read -r repo_id; do
        repo_matches_family "${repo_id}" "${repo_family}" || continue
        case "${repo_id}" in
            *-debuginfo|*-source)
                continue
                ;;
        esac
        return 0
    done <<< "${available_repos}"
    echo "RPM Fusion repo family '${repo_family}' not found. Installing release package."
    dnf5 install -y "${repo_url}"
}

enable_rpmfusion_repo_family() {
    local repo_family="${1}"
    local repo_id

    while IFS= read -r repo_id; do
        repo_matches_family "${repo_id}" "${repo_family}" || continue
        case "${repo_id}" in
            *-debuginfo|*-source)
                continue
                ;;
        esac
        if ! dnf5 config-manager setopt "${repo_id}.enabled=1"; then
            echo "WARNING: Failed to enable RPM Fusion repo '${repo_id}'. Check 'dnf5 repolist --all' and repo configuration." >&2
        fi
    done <<< "$(get_available_repos)"
}

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

enable_rpmfusion_repo_family rpmfusion-free
enable_rpmfusion_repo_family rpmfusion-nonfree

dnf5 --refresh makecache

# this installs a package from Fedora repos
dnf5 install -y \
autofs \
beep \
btfs \
bsdtar \
coolercontrol \
google-authenticator \
liquidctl \
megasync \
dolphin-megasync \
mpv \
python3-pygame \
qt6-qtgrpc \
rEFInd \
rEFInd-tools \
sbctl \
solaar \
vlc \
vlc-plugins-all \
waypipe

# install only necessary plasma-discover packages for plasmoids
dnf5 install -y --setopt=install_weak_deps=False plasma-discover plasma-discover-kns

# Enable COPRs
dnf5 -y copr enable matinlotfali/KDE-Rounded-Corners
dnf5 -y copr enable loteran/arctis-sound-manager

### Re-enable Deck-specific changes on top of the DX base image.
mkdir -p /usr/share/gamescope-session-plus /etc/sddm.conf.d

downloads=(
    "https://large-package-sources.nobaraproject.org/bootstrap_steam.tar.gz|/usr/share/gamescope-session-plus/bootstrap_steam.tar.gz"
    "https://raw.githubusercontent.com/ublue-os/bazzite/main/system_files/deck/shared/etc/sddm.conf.d/virtualkbd.conf|/etc/sddm.conf.d/virtualkbd.conf"
)

for item in "${downloads[@]}"; do
    IFS='|' read -r url dest <<<"${item}"
    if ! curl --fail-with-body --retry 3 -Lo "${dest}" "${url}" || [ ! -s "${dest}" ]; then
        echo "Failed to download ${dest}" >&2
        exit 1
    fi
done

dnf5 install -y \
    sddm \
    steamos-manager-powerstation

packages_to_remove=(ds-inhibit plasma-login-manager steamdeck-kde-presets-desktop)

# Disable unit files before removing packages so enabled symlinks don't linger in /etc/systemd/system.
services_to_disable_before_remove=(ds-inhibit.service plasmalogin.service)
for service in "${services_to_disable_before_remove[@]}"; do
    if systemctl list-unit-files "${service}" 2>/dev/null | awk '{print $1}' | grep -qx "${service}"; then
        systemctl disable "${service}"
    fi
done

installed_packages_to_remove=()
for package in "${packages_to_remove[@]}"; do
    if rpm -q "${package}" >/dev/null 2>&1; then
        installed_packages_to_remove+=("${package}")
    fi
done

if ((${#installed_packages_to_remove[@]})); then
    dnf5 remove -y "${installed_packages_to_remove[@]}"
fi

# Re-enable bazzite-multilib COPR (disabled in base image, needed for steamdeck-kde-presets)
dnf5 -y copr enable ublue-os/bazzite-multilib
dnf5 install -y steamdeck-kde-presets
dnf5 -y copr disable ublue-os/bazzite-multilib

services_to_disable=(gdm.service plasmalogin.service ds-inhibit.service input-remapper.service)
for service in "${services_to_disable[@]}"; do
    if systemctl list-unit-files "${service}" 2>/dev/null | awk '{print $1}' | grep -qx "${service}"; then
        systemctl disable "${service}"
    fi
done

# Hide input-remapper UI (deck behavior; bazzite-dx unhides it)
sed -i 's@^NoDisplay=false@NoDisplay=true@' /usr/share/applications/input-remapper-gtk.desktop

systemctl enable sddm.service
systemctl enable bazzite-autologin.service
systemctl enable beep-startup.service
systemctl disable uupd.timer

# this uninstalls a package
dnf5 remove -y \
kate \
kwrite \
kfind
