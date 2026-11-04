#!/bin/bash

# Isolated COPR installs.
#
# Adapted from Bluefin's copr_install_isolated (Apache-2.0):
# https://github.com/ublue-os/bluefin/blob/main/build_files/shared/copr-helpers.sh
#
# Bluefin enables a COPR, disables it, then installs with --enablerepo.
# This helper uses --from-repo so the named packages can only come from that
# COPR. Dependencies still come from enabled repositories, and DNF5 enables
# the --from-repo repository for the transaction only.
# https://dnf5.readthedocs.io/en/latest/commands/install.8.html
#
# The Bazzite base image does not configure the COPRs this image installs
# from. Its build only enables ublue-os/bazzite, ublue-os/bazzite-multilib,
# ublue-os/staging, ublue-os/packages, ycollet/audinux, and che/nerd-fonts
# (build_files/bazzite/04-initialize.sh). When a COPR is missing, register it
# and disable it before the install, so an installation failure cannot leave
# it enabled. When the repository is already defined, leave its saved
# enablement alone.
#
# Disabling first is safe for the projects this image uses. Their Fedora 45
# repo files contain only the main repository, with no external dependency
# repositories that would have to stay enabled during the install.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source lib/copr.sh from build.sh." >&2
    exit 1
fi

# OWNER/PROJECT on the default hub becomes DNF5's COPR repository id.
copr_repo_id() {
    local copr="${1}"
    printf 'copr:copr.fedorainfracloud.org:%s\n' "${copr//\//:}"
}

# Return 0 when repo_id is already defined, including when it is disabled.
# A repolist failure aborts the build instead of registering a new COPR.
copr_repo_defined() {
    local repo_id="${1}"
    local repolist

    if ! repolist="$(dnf5 repolist --all)"; then
        echo "ERROR: Failed to list DNF repositories while checking COPR '${repo_id}'." >&2
        exit 1
    fi
    awk -v repo="${repo_id}" 'NR > 1 && $1 == repo { found = 1 } END { exit !found }' <<< "${repolist}"
}

# copr_install_isolated COPR [dnf5-install-args...] PACKAGE...
# Extra arguments are passed through, which preserves cdemu's transaction flags.
copr_install_isolated() {
    local copr
    local repo_id

    if (( $# < 2 )); then
        echo "ERROR: copr_install_isolated requires a COPR name and at least one package." >&2
        return 1
    fi

    copr="${1}"
    shift
    repo_id="$(copr_repo_id "${copr}")"

    if copr_repo_defined "${repo_id}"; then
        echo "COPR '${copr}' is already configured. Installing without changing repository enablement."
    else
        echo "Configuring COPR '${copr}' and leaving it disabled."
        dnf5 -y copr enable "${copr}"
        if ! dnf5 -y copr disable "${copr}"; then
            echo "ERROR: Failed to disable COPR '${copr}' after registering it. Not installing packages." >&2
            exit 1
        fi
    fi

    dnf5 install -y --from-repo="${repo_id}" "$@"
}
