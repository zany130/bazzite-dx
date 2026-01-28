# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/bazzite-dx:latest@sha256:55bc650bf73bb9bff2010a3efe55d506684cbb77c2c1b5308beb86e84c8deeea

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

COPY system_files/ /

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    \
    # Enforce correct permissions on sensitive files
    chmod 0440 /etc/sudoers.d/1-AllowScripts && \
    chmod 0644 /etc/pam.d/sshd && \
    chmod 0644 /etc/polkit-1/rules.d/90-plugin-loader.rules && \
    chmod 0644 /etc/ublue-os/topgrade.toml && \
    chmod 0644 /etc/ssh/sshd_config.d/99-bazzite.conf && \
    chmod 0755 /usr/local/sbin/reset-video-port && \
    chmod 0644 /etc/systemd/system/beep-startup.service && \
    # Mark binaries as executable
    chmod +x /usr/lib/systemd/system-sleep/lg-buddy-sleep && \
    chmod +x /usr/local/bin/LG_Buddy_Startup && \
    chmod +x /usr/local/bin/LG_Buddy_Shutdown && \
    chmod +x /usr/local/sbin/reset-video-port && \
    \
    ostree container commit
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint

