#!/bin/bash

# Download and verify rEFInd_GUI from its Fedora 44 release package.
# Version and checksum pins are assigned in build.sh for Renovate.
# Sourced by build.sh.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: source stages/03-refind-gui.sh from build.sh." >&2
    exit 1
fi

REFIND_GUI_RPM="rEFInd_GUI-${REFIND_GUI_VERSION#v}-1.fc44.x86_64.rpm"
REFIND_GUI_URL="https://github.com/jlobue10/rEFInd_GUI/releases/download/${REFIND_GUI_VERSION}/${REFIND_GUI_RPM}"
download_verified "${REFIND_GUI_URL}" "/tmp/${REFIND_GUI_RPM}" "${REFIND_GUI_SHA256}"
dnf5 install -y "/tmp/${REFIND_GUI_RPM}"
# Keep executable payloads in immutable /usr as the authoritative upgrade source.
# /etc remains the upstream ABI used by the GUI, exact sudoers rules and units.
install -d -m 0755 /usr/libexec/rEFInd_GUI /usr/share/rEFInd_GUI
install -m 0755 /etc/rEFInd/rEFInd_GUI /etc/rEFInd/rEFInd_GUI_helper /usr/libexec/rEFInd_GUI/
# Retain known 3.4.6/3.4.7 release bytes for migration; include the installed RPM's
# SHA-256 file metadata automatically on subsequent Renovate updates.
python3 - <<'PYMANIFEST'
import json
import subprocess
from pathlib import Path
known = {
    "rEFInd_GUI": ["fa1788d3b28ccec18ce9b87af5856959476ea956b1c083f63a060d03efe65829",
                   "3468198d2364f690aceb8a0da7fb11e0713df50d27b7cc2ed48c3c3a92400c5c"],
    "rEFInd_GUI_helper": ["68ee3a57456e9722cef615cd27a43e4c80cf5060b569e4582f3048ab7be84169",
                          "3c1772e51f6763300f47102a8048f700670a2e891ce4921b5af139d3fe6c25b1"],
}
for line in subprocess.check_output(["rpm", "-q", "--dump", "rEFInd_GUI"], text=True).splitlines():
    fields = line.split()
    name = Path(fields[0]).name
    if fields[0] == "/etc/rEFInd/" + name and name in known:
        known[name].append(fields[3])
Path("/usr/share/rEFInd_GUI/packaged-binaries.json").write_text(json.dumps(known) + "\n")
PYMANIFEST
rm -f "/tmp/${REFIND_GUI_RPM}"

REFIND_GUI_SOURCE_ARCHIVE="rEFInd_GUI-${REFIND_GUI_VERSION}.tar.gz"
REFIND_GUI_SOURCE_URL="https://github.com/jlobue10/rEFInd_GUI/archive/refs/tags/${REFIND_GUI_VERSION}.tar.gz"
download_verified \
    "${REFIND_GUI_SOURCE_URL}" \
    "/tmp/${REFIND_GUI_SOURCE_ARCHIVE}" \
    "${REFIND_GUI_SOURCE_SHA256}"
mkdir -p /usr/share/rEFInd_GUI
tar -xzf "/tmp/${REFIND_GUI_SOURCE_ARCHIVE}" \
    -C /usr/share/rEFInd_GUI \
    --strip-components=1 \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/VERSION" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/GUI" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/icons" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/backgrounds" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/themes" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/refind_install_package_mgr.sh" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/refind_install_Sourceforge.sh" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/uninstall_rEFInd.sh" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/scan_esp.sh" \
    "rEFInd_GUI-${REFIND_GUI_VERSION#v}/refind-GUI.conf"
rm -f "/tmp/${REFIND_GUI_SOURCE_ARCHIVE}"
install -m 0644 /usr/share/rEFInd_GUI/GUI/UEFI_icon.png /etc/rEFInd/UEFI_icon.png
printf '%s\n' /usr/share/rEFInd_GUI/backgrounds > /etc/rEFInd/background-dir
chown root:root /etc/rEFInd/background-dir
chmod 0644 /etc/rEFInd/background-dir
