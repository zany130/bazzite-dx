#!/bin/bash

# Systemd configuration and final package removals. Sourced by build.sh.
# The removal stays last so it cannot change dependency resolution of earlier installs.
#
# Stage 03 dependencies, for a future build that omits the DX package layer:
#   docker.socket          requires docker-ce from Stage 03
#   virt*.socket           requires libvirt from Stage 03
# podman.socket comes from the Deck base. podman-machine is the Stage 03 addition.
# bazzite-dx-user-setup, bazzite-dx-system-setup, and the rEFInd seed binaries
# come from system_files, not from Stage 03.
# punktfunk-scripting.service is enabled by the Stage 04 RPM; this stage turns
# that default off. beep-startup and the editor removals do not depend on Stage 03.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/08-services.sh from build.sh." >&2
    exit 1
fi

# Independent DX setup: Bazzite's own setup runner does not dispatch legacy
# ublue hook directories. Enable both for new and already-configured users.
chmod 0755 /usr/libexec/bazzite-dx-refind-seed /usr/libexec/bazzite-dx-refind-sync
systemctl --global enable bazzite-dx-user-setup.service
systemctl enable bazzite-dx-system-setup.service

# Requires docker-ce from Stage 03.
systemctl enable docker.socket
# podman.socket is part of the Deck base. podman-machine is installed in Stage 03.
systemctl enable podman.socket
# Requires libvirt from Stage 03.
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

# The benchmark dependency installs Fedora's native web server. Bazzite
# manages the container with cockpit.service; only it should listen on 9090.
systemctl mask cockpit.socket
# The Punktfunk RPM enables this user service. Leave it opt-in.
systemctl --global disable punktfunk-scripting.service

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

dnf5 remove -y \
    kate \
    kwrite \
    kfind
