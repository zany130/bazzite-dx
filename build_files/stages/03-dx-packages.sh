#!/bin/bash

# Fedora 45 DX starts from bazzite-deck. Install the additional tooling here.
# Keep Docker first and scoped so later transactions see containerd.io.
# Stage 08 owns the Docker and libvirt socket defaults.

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
    ramalama
)
dx_container_packages=(
    podman-machine
    podman-tui
)
dx_virtualization_packages=(
    guestfs-tools
    libvirt
    qemu
    qemu-kvm
    virt-manager
)
dx_remote_packages=(
    rclone
    restic
    waypipe
    zsh
)
dx_acceleration_packages=(
    rocm-hip
)

dnf5 install -y \
    "${dx_debug_packages[@]}" \
    "${dx_editor_packages[@]}" \
    "${dx_container_packages[@]}" \
    "${dx_virtualization_packages[@]}" \
    "${dx_remote_packages[@]}" \
    "${dx_acceleration_packages[@]}"
