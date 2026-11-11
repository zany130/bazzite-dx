#!/bin/bash
# shellcheck source-path=SCRIPTDIR
# Pins are read by the sourced stages. `shellcheck -x` follows those files.
# shellcheck disable=SC2034,SC1091

# Image build entry point. The Containerfile runs this once.
# Stages are sourced so shell state, including rpmfusion_repo_args and
# fortyfive_repo_id, is shared. Bazzite runs numbered scripts as separate
# processes; that split does not fit state that later transactions still need.
#
# Stage 03 is the upstream DX package layer, including Docker CE. Omit that
# source line to drop the layer later, and adjust the Stage 08 units that
# depend on it. See stages/03-dx-packages.sh and stages/08-services.sh.
#
# Version pins stay in this file. Renovate's regex managers and
# refind-checksums.yml match build_files/build.sh only.

set -ouex pipefail

# renovate: datasource=github-release-attachments depName=jlobue10/rEFInd_GUI
REFIND_GUI_VERSION="v3.5.8"
REFIND_GUI_SHA256="1d1d87d0206ad5e408dbd45b000613ae9e6e48723edb6c92d8c70ba22c4fa6da"
# Updated on Renovate PRs by refind-checksums.yml before dispatching the image build.
REFIND_GUI_SOURCE_SHA256="94fb78edbc2bac425a794abb8dcbabc2d9b6ced39f65b3531f33a8b842af543c"

# renovate: datasource=github-releases depName=zany130/cockpit-probe versioning=loose
COCKPIT_HARDWARE_PROBE_VERSION="v1.0"
# SHA256 is NOT auto-updated by Renovate; update manually when COCKPIT_HARDWARE_PROBE_VERSION changes.
COCKPIT_HARDWARE_PROBE_SHA256="bd8ead0406fd6bdab8b998b1c148e56beb6c053a2c84ee126043cbc8435f78bc"

# renovate: datasource=github-releases depName=zany130/cockpit-diagnostics versioning=loose
COCKPIT_DIAGNOSTICS_VERSION="V1.0"
# SHA256 is NOT auto-updated by Renovate; update manually when COCKPIT_DIAGNOSTICS_VERSION changes.
COCKPIT_DIAGNOSTICS_SHA256="809ad753057820d23406c57d7c5c67fd711e1262a7f5188a26240cf573bffcf1"

# renovate: datasource=github-releases depName=realmcuser/cockpit-nspawn versioning=loose
COCKPIT_NSPAWN_VERSION="v1.0.0-83"
# SHA256 is NOT auto-updated by Renovate; update manually when COCKPIT_NSPAWN_VERSION changes.
COCKPIT_NSPAWN_SHA256="cd4e8bb057ae0c7dc806570fbe9ec34c15dcee43f2385e40cbc7cd95550ca1f4"

BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${BUILD_ROOT}/lib/common.sh"
# shellcheck source=lib/repositories.sh
source "${BUILD_ROOT}/lib/repositories.sh"
# shellcheck source=lib/copr.sh
source "${BUILD_ROOT}/lib/copr.sh"

# shellcheck source=stages/01-repositories.sh
source "${BUILD_ROOT}/stages/01-repositories.sh"
# shellcheck source=stages/02-fedora-packages.sh
source "${BUILD_ROOT}/stages/02-fedora-packages.sh"
# shellcheck source=stages/03-dx-packages.sh
source "${BUILD_ROOT}/stages/03-dx-packages.sh"
# shellcheck source=stages/04-third-party-packages.sh
source "${BUILD_ROOT}/stages/04-third-party-packages.sh"
# shellcheck source=stages/05-copr-packages.sh
source "${BUILD_ROOT}/stages/05-copr-packages.sh"
# shellcheck source=stages/06-cockpit.sh
source "${BUILD_ROOT}/stages/06-cockpit.sh"
# shellcheck source=stages/07-refind-gui.sh
source "${BUILD_ROOT}/stages/07-refind-gui.sh"
# shellcheck source=stages/08-services.sh
source "${BUILD_ROOT}/stages/08-services.sh"
