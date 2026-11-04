#!/bin/bash

# COPR packages and the Punktfunk repository.
# COPR installs go through copr_install_isolated. Punktfunk is a single signed
# repository written disabled, then enabled for one transaction. Sourced by build.sh.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/07-copr-punktfunk.sh from build.sh." >&2
    exit 1
fi

copr_install_isolated matinlotfali/KDE-Rounded-Corners \
    kwin-effect-roundcorners

copr_install_isolated loteran/arctis-sound-manager \
    arctis-sound-manager

copr_install_isolated rok/cdemu \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=noscripts \
    cdemu-client \
    cdemu-daemon \
    gcdemu \
    vhba

# Use Punktfunk's signed Bazzite RPMs for streaming in Gaming Mode and KDE.
# Keep this repository disabled outside its own install transaction, like other
# third-party package sources in this image.
cat > /etc/yum.repos.d/punktfunk.repo <<'EOF'
[gitea-unom-bazzite]
name=Punktfunk (unom, Bazzite)
baseurl=https://git.unom.io/api/packages/unom/rpm/bazzite
enabled=0
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://git.unom.io/api/packages/unom/rpm/repository.key
       https://git.unom.io/api/packages/unom/generic/punktfunk-keys/1/RPM-GPG-KEY-punktfunk
EOF

# Include the web console and scripting runner explicitly, rather than relying
# on weak dependencies. User services, pairing and firewall access are
# configured after installation, not during the image build.
dnf5 --refresh --enable-repo=gitea-unom-bazzite install -y \
    punktfunk \
    punktfunk-web \
    punktfunk-scripting
systemctl --global disable punktfunk-scripting.service
