#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# Enable Terra Repository
echo 'Enabling Terra Repository.'
sed -i 's@enabled=0@enabled=1@g' /etc/yum.repos.d/terra.repo

# Enable RPM Fusion Repository
echo 'Enabling RPM Fusion Repository.'
dnf5 config-manager setopt rpmfusion-nonfree.enabled=1
dnf5 config-manager setopt rpmfusion-free.enabled=1

# this installs a package from Fedora repos
dnf5 install -y \
beep \
btfs \
cockpit \
cockpit-ostree \
cockpit-ws-selinux \
coolercontrol \
google-authenticator \
kvantum \
liquidctl \
megasync \
dolphin-megasync \
python3-pygame \
rEFInd \
rEFInd-tools \
sbctl \
solaar \
vlc \
vlc-plugins-all

# Download and verify cockpit-file-sharing with checksum
COCKPIT_FS_VERSION="4.5.2"
COCKPIT_FS_RPM="cockpit-file-sharing-${COCKPIT_FS_VERSION}-1.el9.noarch.rpm"
COCKPIT_FS_URL="https://github.com/45Drives/cockpit-file-sharing/releases/download/v${COCKPIT_FS_VERSION}/${COCKPIT_FS_RPM}"
COCKPIT_FS_SHA256="1cf9930da223e6010be0c0e416e9755d17be87b181a9e7704185b7b31b1e782e"

echo "Downloading ${COCKPIT_FS_RPM}..."
curl --retry 3 -Lo "/tmp/${COCKPIT_FS_RPM}" "${COCKPIT_FS_URL}"

echo "Verifying checksum..."
echo "${COCKPIT_FS_SHA256}  /tmp/${COCKPIT_FS_RPM}" | sha256sum -c -

echo "Installing ${COCKPIT_FS_RPM}..."
dnf5 install -y "/tmp/${COCKPIT_FS_RPM}"
rm -f "/tmp/${COCKPIT_FS_RPM}"

# install only necessary plasma-discover packages for plasmoids
dnf5 install -y --setopt=install_weak_deps=False plasma-discover plasma-discover-kns

# Enable COPR'S
dnf5 -y copr enable birkch/HeadsetControl
dnf5 -y copr enable matinlotfali/KDE-Rounded-Corners
dnf5 -y copr enable kylegospo/wallpaper-engine-kde-plugin

# install packages from copr
dnf5 install -y \
HeadsetControl \
HeadsetControl-Qt \
kwin-effect-roundcorners \
wallpaper-engine-kde-plugin

### Renable -deck specfic changes
curl --retry 3 -Lo /usr/share/gamescope-session-plus/bootstrap_steam.tar.gz https://large-package-sources.nobaraproject.org/bootstrap_steam.tar.gz && \
curl --retry 3 -Lo /etc/sddm.conf.d/steamos.conf https://raw.githubusercontent.com/ublue-os/bazzite/refs/heads/main/system_files/deck/shared/etc/sddm.conf.d/steamos.conf && \
curl --retry 3 -Lo /etc/sddm.conf.d/virtualkbd.conf https://raw.githubusercontent.com/ublue-os/bazzite/refs/heads/main/system_files/deck/shared/etc/sddm.conf.d/virtualkbd.conf

sed -i -E \
     -e 's/^(action\/switch_user)=true/\1=false/' \
     -e 's/^(action\/start_new_session)=true/\1=false/' \
     -e 's/^(action\/lock_screen)=true/\1=false/' \
     -e 's/^(kcm_sddm\.desktop)=true/\1=false/' \
     -e 's/^(kcm_plymouth\.desktop)=true/\1=false/' \
     /etc/xdg/kdeglobals

systemctl enable bazzite-autologin.service
systemctl enable beep-startup.service
systemctl disable uupd.timer

# this uninstalls a package
dnf5 remove -y \
kate \
kwrite \
kfind
