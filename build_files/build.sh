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
 
# this installs a package from fedora repos
dnf5 install -y \
coolercontrol \
kvantum \
liquidctl \
rEFInd \
rEFInd-tools \
sbctl \
solaar

# Use a COPR Example:
#dnf5 -y copr enable agundur/KCast
#dnf5 -y install kcast

#### Example for enabling a System Unit File

# Renable -deck specfic changes
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
systemctl disable uupd.timer
