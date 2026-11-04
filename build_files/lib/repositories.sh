#!/bin/bash

# Repository helpers for build.sh.
# Terra and RPM Fusion stay disabled except for the transactions that opt in.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source lib/repositories.sh from build.sh." >&2
    exit 1
fi

# Install packages with one additional repository enabled for the transaction.
dnf_install_with_retry() {
    local repo="$1"
    shift
    local attempt
    local attempts=3

    for ((attempt=1; attempt<=attempts; attempt++)); do
        echo "Installing packages with ${repo} enabled (attempt ${attempt}/${attempts})."
        if dnf5 --refresh --enable-repo="${repo}" install -y "$@"; then
            return 0
        fi
        if (( attempt < attempts )); then
            echo "Install failed on attempt ${attempt}/${attempts}; cleaning metadata before retrying." >&2
            dnf5 clean all --enable-repo="${repo}" || return 1
        fi
    done

    echo "ERROR: Failed to install $* with ${repo} enabled after ${attempts} attempts." >&2
    return 1
}

# Configure Terra through a DNF5 repository override.
# The packaged repo must already exist. This refuses to invent terra.repo.
configure_terra_repository() {
    local terra_repo_id="terra"
    local terra_excludes="qt6-*,kf6-*,plasma-*,fcitx5-qt*"
    local repolist

    if ! repolist="$(dnf5 repolist --all)"; then
        echo "ERROR: Failed to list DNF repositories while configuring Terra." >&2
        return 1
    fi
    if ! awk -v repo="${terra_repo_id}" 'NR > 1 && $1 == repo { found = 1 } END { exit !found }' <<< "${repolist}"; then
        echo "ERROR: Terra repository '${terra_repo_id}' is not defined. Refusing to create /etc/yum.repos.d/terra.repo." >&2
        return 1
    fi

    # enabled=0 keeps Terra off by default. excludepkgs is stored beside any
    # existing "exclude" override, so base-image exclusions are preserved and
    # Qt6, KDE Frameworks, Plasma, and fcitx Qt packages stay out of Terra.
    dnf5 config-manager setopt \
        "${terra_repo_id}.enabled=0" \
        "${terra_repo_id}.excludepkgs=${terra_excludes}"
}

get_available_repos() {
    dnf5 repolist --all | awk 'NR > 1 && $1 != "" {print $1}'
}

repo_matches_family() {
    local repo_id="${1}"
    local repo_family="${2}"

    case "${repo_id}" in
        "${repo_family}"|"${repo_family}"-*)
            return 0
            ;;
    esac

    return 1
}

ensure_rpmfusion_release_repo() {
    local repo_family="${1}"
    local repo_url="${2}"
    local available_repos
    available_repos="$(get_available_repos)"
    while IFS= read -r repo_id; do
        repo_matches_family "${repo_id}" "${repo_family}" || continue
        case "${repo_id}" in
            *-debuginfo|*-source)
                continue
                ;;
        esac
        return 0
    done <<< "${available_repos}"
    echo "RPM Fusion repo family '${repo_family}' not found. Installing release package."
    dnf5 --setopt=optional_metadata_types=filelists install -y "${repo_url}"
}

# Appends --enable-repo flags to the caller-initialized rpmfusion_repo_args array.
scope_rpmfusion_repo_family() {
    local repo_family="${1}"
    local repo_id

    while IFS= read -r repo_id; do
        repo_matches_family "${repo_id}" "${repo_family}" || continue
        case "${repo_id}" in
            *-debuginfo|*-source)
                continue
                ;;
        esac
        if ! dnf5 config-manager setopt "${repo_id}.enabled=0"; then
            echo "ERROR: Failed to disable RPM Fusion repo '${repo_id}'." >&2
            exit 1
        fi
        rpmfusion_repo_args+=("--enable-repo=${repo_id}")
    done <<< "$(get_available_repos)"
}
