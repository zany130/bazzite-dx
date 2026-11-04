#!/bin/bash

# DX packages from the repositories already enabled on the base image.
# These are one transaction, grouped only so the lists stay readable.
# Sourced by build.sh.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/05-dx-packages.sh from build.sh." >&2
    exit 1
fi

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
