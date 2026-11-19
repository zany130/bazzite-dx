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

# Custom non-Deck service restore
systemctl enable beep-startup.service

# Disable bazzites cockpit quadlet and use native fedora installed cockpit instead
systemctl disable cockpit.service
systemctl unmask cockpit.socket
systemctl enable cockpit.socket

dnf5 remove -y \
    kate \
    kwrite \
    kfind
