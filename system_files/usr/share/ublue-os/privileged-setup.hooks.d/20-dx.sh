#!/usr/bin/bash
set -euo pipefail
# Reconcile all wheel users on each boot, including users added later.
# Function to append a group entry to /etc/group
append_group() {
	local group_name="$1"
	if ! grep -q "^$group_name:" /etc/group; then
		echo "Appending $group_name to /etc/group"
		entry=$(getent group "$group_name")
		[[ -n "$entry" ]] || return 1
		printf '%s\n' "$entry" >> /etc/group
	fi
}

# Setup Groups
append_group docker

# We dont have incus on the image yet
# append_group incus-admin
# usermod -aG incus-admin $user

mapfile -t wheelarray < <(getent group wheel | cut -d ":" -f 4 | tr ',' '\n')
for user in "${wheelarray[@]}"; do
	[[ -n "$user" ]] || continue
	if ! id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
		usermod -aG docker "$user"
	fi
done
