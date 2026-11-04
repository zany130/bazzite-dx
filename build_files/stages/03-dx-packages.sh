#!/bin/bash

# Upstream DX package layer missing from the bazzite-deck base.
# Bazzite Deck plus this stage restores that set. Omit this file from build.sh
# to drop the layer later. It defines no helpers or variables that later
# custom stages need. Stage 08 still enables docker.socket and the libvirt
# sockets these packages provide, so a DX-free build must adjust those lines.
#
# Compared with ublue-os/bazzite-dx build_files/20-install-apps.sh on main.
# That image is built from desktop Bazzite, not Deck. Packages installed here
# that match that script: android-tools, bcc, bpftop, bpftrace, ccache,
# flatpak-builder, git-subtree, google-noto-sans-fonts, nicstat, numactl,
# podman-machine, podman-tui, restic, rclone, sysprof, tiptop, usbmuxd,
# waypipe, zsh, rocm-hip, rocm-opencl, rocm-clinfo, rocm-smi, qemu, libvirt,
# qemu-kvm, virt-manager, guestfs-tools, and the Docker CE group.
# This image keeps the package name ramalama; upstream currently requests
# python3-ramalama. The established Cockpit, libvirt, and QEMU extras below
# are not in that upstream script and stay so this image's DX layer does not
# shrink. Not copied from upstream, because they change Deck session behavior
# or add software this image does not ship: code, edk2-ovmf, ds-inhibit,
# ublue-setup-services, removing mesa-libOpenCL, enabling tuned/uupd/
# input-remapper, and swapping SDDM for plasma-login-manager.
#
# Docker is installed before the other DX packages, matching the previous
# transaction order. containerd.io is then already installed when that solver
# runs. Docker stays its own scoped transaction.
# Sourced by build.sh.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/03-dx-packages.sh from build.sh." >&2
    exit 1
fi

docker_packages=(
    containerd.io
    docker-buildx-plugin
    docker-ce
    docker-ce-cli
    docker-compose-plugin
)

dnf5 --refresh --enable-repo=docker-ce-stable install -y \
    "${docker_packages[@]}"

# Restore DX-specific tooling that is present in upstream DX but missing from deck.
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
