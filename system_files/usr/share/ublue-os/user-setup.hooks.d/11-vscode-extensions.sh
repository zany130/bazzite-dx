#!/usr/bin/bash
set -euo pipefail
# Retry on a later login if code is not installed or installation fails.
command -v code >/dev/null || exit 0
state="${XDG_STATE_HOME:-$HOME/.local/state}/bazzite-dx"
[[ ! -e "$state/vscode-extensions-v1" ]] || exit 0
# Setup VSCode
if test ! -L "$HOME"/.config/Code/User/settings.json && test ! -e "$HOME"/.config/Code/User/settings.json; then
	mkdir -p "$HOME"/.config/Code/User
	cp -f /etc/skel/.config/Code/User/settings.json "$HOME"/.config/Code/User/settings.json
fi

code --install-extension ms-vscode-remote.remote-containers
code --install-extension ms-vscode-remote.remote-ssh
code --install-extension ms-azuretools.vscode-containers

mkdir -p "$state"
touch "$state/vscode-extensions-v1"
