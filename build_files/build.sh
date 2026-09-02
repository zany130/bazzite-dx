#!/bin/bash

set -ouex pipefail

# system_files/ is copied into / by the Containerfile (COPY system_files/ /)

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPM Fusion repos may be provided by the base image, but bootstrap them if absent.
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# Keep Terra disabled except for transactions that explicitly need it.
echo 'Configuring Terra Repository.'
dnf5 config-manager setopt terra.enabled=0

# Exclude core Qt/KDE/fcitx Qt packages from Terra to avoid pulling in
# mismatched Qt private ABI versions that break plasmoids at runtime.
if grep -q '^excludepkgs=' /etc/yum.repos.d/terra.repo; then
    sed -i 's@^excludepkgs=.*@excludepkgs=qt6-*,kf6-*,plasma-*,fcitx5-qt*@' /etc/yum.repos.d/terra.repo
else
    echo 'excludepkgs=qt6-*,kf6-*,plasma-*,fcitx5-qt*' >> /etc/yum.repos.d/terra.repo
fi

# Keep RPM Fusion disabled except for transactions that explicitly need it.
echo 'Configuring RPM Fusion Repository.'
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

scope_rpmfusion_repo_family() {
    local repo_family="${1}"
    local repo_id

    while IFS= read -r repo_id; do
        repo_matches_family "${repo_id}" "${repo_family}" || continue
        case "${repo_id}" in
            *-debuginfo|*-source)
                continue
                ;;
        esac
        if ! dnf5 config-manager setopt "${repo_id}.enabled=0"; then
            echo "ERROR: Failed to disable RPM Fusion repo '${repo_id}'." >&2
            exit 1
        fi
        rpmfusion_repo_args+=("--enable-repo=${repo_id}")
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

rpmfusion_repo_args=()
scope_rpmfusion_repo_family rpmfusion-free
scope_rpmfusion_repo_family rpmfusion-nonfree
if ((${#rpmfusion_repo_args[@]} == 0)); then
    echo "ERROR: No RPM Fusion repositories are available for scoped installs." >&2
    exit 1
fi

# Configure the Docker repository for scoped package installs.
echo 'Configuring Docker repository.'
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

# Non-DX custom packages
dnf5 install -y \
beep \
btfs \
bsdtar \
google-authenticator \
kvantum \
liquidctl \
mpv \
python3-pygame \
rEFInd \
rEFInd-tools \
solaar \
tesseract \
tesseract-langpack-eng \
tesseract-langpack-spa \
tesseract-libs \
mosh \
nmap

# Install third-party packages only while their owning repository is enabled.
dnf5 --refresh --enable-repo=terra install -y \
    coolercontrol \
    sbctl \
    topgrade

dnf5 --refresh "${rpmfusion_repo_args[@]}" install -y \
    dolphin-megasync \
    megasync

docker_packages=(
containerd.io
docker-buildx-plugin
docker-ce
docker-ce-cli
docker-compose-plugin
)

dnf5 --refresh --enable-repo=docker-ce-stable install -y \
    "${docker_packages[@]}"

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
flatpak-builder
git-subtree
google-noto-sans-fonts
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

# Install 45Drives Cockpit packages
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

# Download and verify cockpit-nspawn with checksum
# renovate: datasource=github-releases depName=realmcuser/cockpit-nspawn versioning=loose
COCKPIT_NSPAWN_VERSION="v1.0.0-74"
COCKPIT_NSPAWN_RPM="cockpit-nspawn-${COCKPIT_NSPAWN_VERSION#v}.fc44.noarch.rpm"
# SHA256 is NOT auto-updated by Renovate; update manually when COCKPIT_NSPAWN_VERSION changes.
COCKPIT_NSPAWN_SHA256="0ced2aa9f493b9d144779c9be0a7d90318e1ad9ebadd366c7162a2a124e6b458"

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
echo "${COCKPIT_NSPAWN_SHA256}  /tmp/${COCKPIT_NSPAWN_RPM}" | sha256sum -c -

echo "Installing ${COCKPIT_NSPAWN_RPM}..."
mkdir -p /var/usrlocal
rpm2cpio "/tmp/${COCKPIT_NSPAWN_RPM}" | (cd / && cpio -idm --quiet --no-absolute-filenames \
    './usr/local/lib/nspawn-pull*' \
    './usr/share/cockpit/nspawn*')
rm -f "/tmp/${COCKPIT_NSPAWN_RPM}"

# Install each COPR package, then disable its repository immediately.
dnf5 -y copr enable matinlotfali/KDE-Rounded-Corners
dnf5 install -y kwin-effect-roundcorners
dnf5 -y copr disable matinlotfali/KDE-Rounded-Corners

dnf5 -y copr enable loteran/arctis-sound-manager
dnf5 install -y arctis-sound-manager
dnf5 -y copr disable loteran/arctis-sound-manager

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
