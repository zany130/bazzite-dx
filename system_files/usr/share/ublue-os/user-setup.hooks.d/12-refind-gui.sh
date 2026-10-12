#!/usr/bin/bash

source /usr/lib/ublue/setup-services/libsetup.sh

REFIND_GUI_VERSION="$(cat /usr/share/rEFInd_GUI/VERSION)"
version-script refind-gui user "$REFIND_GUI_VERSION" || exit 1

set -euo pipefail

source_dir=/usr/share/rEFInd_GUI
data_dir="$HOME/.local/rEFInd_GUI"
mkdir -p "$data_dir"/{GUI,icons,backgrounds,themes}

for directory in GUI icons backgrounds themes; do
    cp -rn "$source_dir/$directory/." "$data_dir/$directory/"
done

for script in refind_install_package_mgr.sh refind_install_Sourceforge.sh uninstall_rEFInd.sh scan_esp.sh; do
    install -m 0755 "$source_dir/$script" "$data_dir/$script"
done

install -m 0644 "$source_dir/refind-GUI.conf" "$data_dir/GUI/refind.conf"
ln -sfn ../backgrounds "$data_dir/GUI/backgrounds"
ln -sfn ../themes "$data_dir/GUI/themes"
