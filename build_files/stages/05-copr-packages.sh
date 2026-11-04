#!/bin/bash

# Custom COPR packages. Registration stays inside copr_install_isolated so a
# new COPR is disabled before its install. Sourced by build.sh.
# This stage does not depend on Stage 03.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/05-copr-packages.sh from build.sh." >&2
    exit 1
fi

copr_install_isolated matinlotfali/KDE-Rounded-Corners \
    kwin-effect-roundcorners

copr_install_isolated loteran/arctis-sound-manager \
    arctis-sound-manager

# The Arctis RPM writes a second, enabled COPR in its postinstall script.
# Deck already provides /usr/lib64/ladspa/librnnoise_ladspa.so.
if [[ -f /etc/yum.repos.d/_asm-noise-suppression-for-voice.repo ]]; then
    dnf5 config-manager setopt 'copr:copr.fedoraproject.org:lkiesow:noise-suppression-for-voice.enabled=0'
fi

copr_install_isolated rok/cdemu \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=noscripts \
    cdemu-client \
    cdemu-daemon \
    gcdemu \
    vhba
