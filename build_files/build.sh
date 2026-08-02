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

# Enable Docker and VS Code repositories
echo 'Enabling DX repositories.'
# SHA256 verified from https://download.docker.com/linux/fedora/gpg on 2026-07-10.
DOCKER_GPG_SHA256="e6c650e0700b1bf4868b693b30761b926844befc8a0acb7ac0dd9b1faf1b7423"
curl --fail-with-body --retry 3 -Lo /tmp/docker-gpg https://download.docker.com/linux/fedora/gpg
echo "${DOCKER_GPG_SHA256}  /tmp/docker-gpg" | sha256sum -c -
rpm --import /tmp/docker-gpg
rm -f /tmp/docker-gpg
cat > /etc/yum.repos.d/docker-ce.repo <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/fedora/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg

[docker-ce-stable-source]
name=Docker CE Stable - Sources
baseurl=https://download.docker.com/linux/fedora/$releasever/source/stable
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg

[docker-ce-test]
name=Docker CE Test - $basearch
baseurl=https://download.docker.com/linux/fedora/$releasever/$basearch/test
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg

[docker-ce-test-source]
name=Docker CE Test - Sources
baseurl=https://download.docker.com/linux/fedora/$releasever/source/test
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg
EOF

# SHA256 verified from https://packages.microsoft.com/keys/microsoft.asc on 2026-07-10.
MICROSOFT_GPG_SHA256="2fa9c05d591a1582a9aba276272478c262e95ad00acf60eaee1644d93941e3c6"
curl --fail-with-body --retry 3 -Lo /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc
echo "${MICROSOFT_GPG_SHA256}  /tmp/microsoft.asc" | sha256sum -c -
rpm --import /tmp/microsoft.asc
rm -f /tmp/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

dnf5 --refresh makecache

# Non-DX custom packages
dnf5 install -y \
beep \
btfs \
bsdtar \
coolercontrol \
google-authenticator \
kvantum \
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
vlc-plugins-all

# DX Packages
# Restore DX-specific tooling that is present in bazzite-dx but missing from deck:testing.
dx_debug_packages=(
android-tools
bcc
bpftop
bpftrace
ccache
nicstat
numactl
sysprof
tiptop
)
dx_editor_packages=(
code
flatpak-builder
git-subtree
ramalama
)
dx_workstation_packages=(
cockpit
cockpit-machines
cockpit-ostree
cockpit-ws-selinux
guestfs-tools
)
dx_container_packages=(
containerd.io
docker-buildx-plugin
docker-ce
docker-ce-cli
docker-compose-plugin
podman-machine
podman-tui
)
dx_virtualization_packages=(
libvirt
python3-libvirt
qemu
qemu-kvm
qemu-system-x86
qemu-user-static-aarch64
swtpm
virt-manager
virtiofsd
virtualbox-guest-additions
)
dx_remote_packages=(
rclone
restic
usbmuxd
waypipe
zsh
)
dx_acceleration_packages=(
rocm-clinfo
rocm-hip
rocm-opencl
rocm-smi
)

dnf5 install -y \
    "${dx_debug_packages[@]}" \
    "${dx_editor_packages[@]}" \
    "${dx_workstation_packages[@]}" \
    "${dx_container_packages[@]}" \
    "${dx_virtualization_packages[@]}" \
    "${dx_remote_packages[@]}" \
    "${dx_acceleration_packages[@]}"

# Download and verify cockpit-file-sharing with checksum
# renovate: datasource=github-releases depName=45Drives/cockpit-file-sharing versioning=loose
COCKPIT_FS_VERSION="v4.6.1"
COCKPIT_FS_RPM="cockpit-file-sharing-${COCKPIT_FS_VERSION#v}-1.el9.noarch.rpm"
COCKPIT_FS_URL="https://github.com/45Drives/cockpit-file-sharing/releases/download/${COCKPIT_FS_VERSION}/${COCKPIT_FS_RPM}"
# SHA256 is NOT auto-updated by Renovate; update manually when COCKPIT_FS_VERSION changes.
COCKPIT_FS_SHA256="bb83a996bb55c49a3409d1db023351b4d4e356805b5f23666b1dd9438f10e0e3"

echo "Downloading ${COCKPIT_FS_RPM}..."
if ! curl --fail-with-body --retry 3 -Lo "/tmp/${COCKPIT_FS_RPM}" "${COCKPIT_FS_URL}" || [ ! -s "/tmp/${COCKPIT_FS_RPM}" ]; then
  echo "Failed to download ${COCKPIT_FS_RPM}" >&2
  exit 1
fi

echo "Verifying checksum..."
echo "${COCKPIT_FS_SHA256}  /tmp/${COCKPIT_FS_RPM}" | sha256sum -c -

echo "Installing ${COCKPIT_FS_RPM}..."
dnf5 install -y "/tmp/${COCKPIT_FS_RPM}"
rm -f "/tmp/${COCKPIT_FS_RPM}"

# Download and verify cockpit-nspawn with checksum
# renovate: datasource=github-releases depName=realmcuser/cockpit-nspawn versioning=loose
COCKPIT_NSPAWN_VERSION="v1.0.0-65"
COCKPIT_NSPAWN_RPM="cockpit-nspawn-${COCKPIT_NSPAWN_VERSION#v}.fc44.noarch.rpm"
COCKPIT_NSPAWN_URL="https://github.com/realmcuser/cockpit-nspawn/releases/download/${COCKPIT_NSPAWN_VERSION}/${COCKPIT_NSPAWN_RPM}"
# SHA256 is NOT auto-updated by Renovate; update manually when COCKPIT_NSPAWN_VERSION changes.
COCKPIT_NSPAWN_SHA256="e0979d3c2701bb09bcffef9d19648640ceb21af434d87b7499bba786b5a62c09"

echo "Downloading ${COCKPIT_NSPAWN_RPM}..."
if ! curl --fail-with-body --retry 3 -Lo "/tmp/${COCKPIT_NSPAWN_RPM}" "${COCKPIT_NSPAWN_URL}" || [ ! -s "/tmp/${COCKPIT_NSPAWN_RPM}" ]; then
  echo "Failed to download ${COCKPIT_NSPAWN_RPM}" >&2
  exit 1
fi

echo "Verifying checksum..."
echo "${COCKPIT_NSPAWN_SHA256}  /tmp/${COCKPIT_NSPAWN_RPM}" | sha256sum -c -

echo "Installing ${COCKPIT_NSPAWN_RPM}..."
dnf5 install -y "/tmp/${COCKPIT_NSPAWN_RPM}"
rm -f "/tmp/${COCKPIT_NSPAWN_RPM}"

# install only necessary plasma-discover packages for plasmoids
dnf5 install -y --setopt=install_weak_deps=False plasma-discover plasma-discover-kns

# Enable COPRs
dnf5 -y copr enable matinlotfali/KDE-Rounded-Corners
dnf5 -y copr enable loteran/arctis-sound-manager

# install packages from copr
dnf5 install -y \
    arctis-sound-manager \
    kwin-effect-roundcorners

# DX Services
systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable \
    virtinterfaced.socket \
    virtlockd.socket \
    virtlogd.socket \
    virtnetworkd.socket \
    virtnodedevd.socket \
    virtnwfilterd.socket \
    virtproxyd.socket \
    virtqemud.socket \
    virtsecretd.socket \
    virtstoraged.socket

# Deck customizations (commented out - now provided by deck:testing base image)
# See README "Additional Packages" -> "Deck" for why this block is kept for rollback.
# mkdir -p /usr/share/gamescope-session-plus /etc/sddm.conf.d
#
# downloads=(
#     "https://large-package-sources.nobaraproject.org/bootstrap_steam.tar.gz|/usr/share/gamescope-session-plus/bootstrap_steam.tar.gz"
#     "https://raw.githubusercontent.com/ublue-os/bazzite/main/system_files/deck/shared/etc/sddm.conf.d/virtualkbd.conf|/etc/sddm.conf.d/virtualkbd.conf"
# )
#
# for item in "${downloads[@]}"; do
#     IFS='|' read -r url dest <<<"${item}"
#     if ! curl --fail-with-body --retry 3 -Lo "${dest}" "${url}" || [ ! -s "${dest}" ]; then
#         echo "Failed to download ${dest}" >&2
#         exit 1
#     fi
# done
#
# dnf5 install -y \
#     sddm \
#     steamos-manager-powerstation
#
# packages_to_remove=(ds-inhibit plasma-login-manager steamdeck-kde-presets-desktop)
#
# services_to_disable_before_remove=(ds-inhibit.service plasmalogin.service)
# for service in "${services_to_disable_before_remove[@]}"; do
#     if systemctl list-unit-files "${service}" 2>/dev/null | awk '{print $1}' | grep -qx "${service}"; then
#         systemctl disable "${service}"
#     fi
# done
#
# installed_packages_to_remove=()
# for package in "${packages_to_remove[@]}"; do
#     if rpm -q "${package}" >/dev/null 2>&1; then
#         installed_packages_to_remove+=("${package}")
#     fi
# done
#
# if ((${#installed_packages_to_remove[@]})); then
#     dnf5 remove -y "${installed_packages_to_remove[@]}"
# fi
#
# dnf5 -y copr enable ublue-os/bazzite-multilib
# dnf5 install -y steamdeck-kde-presets
# dnf5 -y copr disable ublue-os/bazzite-multilib
#
# services_to_disable=(gdm.service plasmalogin.service ds-inhibit.service input-remapper.service)
# for service in "${services_to_disable[@]}"; do
#     if systemctl list-unit-files "${service}" 2>/dev/null | awk '{print $1}' | grep -qx "${service}"; then
#         systemctl disable "${service}"
#     fi
# done
#
# sed -i 's@^NoDisplay=false@NoDisplay=true@' /usr/share/applications/input-remapper-gtk.desktop
#
# systemctl enable sddm.service
# systemctl enable bazzite-autologin.service
# deck:testing already ships this disabled; keep the old override commented for easy rollback.
# systemctl disable uupd.timer
# End disabled Deck block

# Custom non-Deck service restore
systemctl enable beep-startup.service

# this uninstalls a package
dnf5 remove -y \
kate \
kwrite \
kfind
