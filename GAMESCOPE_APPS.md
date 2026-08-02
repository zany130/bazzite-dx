# Gamescope background applications

Gamescope background applications are managed as independent systemd user services. The Gamescope session pulls in `gamescope-apps.target`, and each enabled `gamescope-app@NAME.service` instance runs one app under Xvfb.

## Architecture

- `gamescope-apps.target` groups apps, binds them to the Gamescope session, and conflicts with Plasma Desktop Mode.
- `gamescope-app@.service` provides systemd supervision, restart policy, logging, and process cleanup.
- `gamescope-xvfb-launch` resolves the app config and executes its command under Xvfb.
- `/etc/gamescope/apps.d/NAME.conf` provides image defaults.
- `~/.config/gamescope/apps.d/NAME.conf` provides user apps or overrides the matching image default.

The service instance name should match the application, for example `discord`, `megasync`, or `openrgb`. This makes service status and journal output self-explanatory.

When the Gamescope session ends, `gamescope-apps.target` stops and systemd stops every participating `gamescope-app@NAME.service`. The target also conflicts with `plasma-workspace.target`, so starting Desktop Mode explicitly stops the Gamescope app group before Plasma starts.

## Add a user app

Create a config whose filename matches the desired service instance:

```bash
mkdir -p ~/.config/gamescope/apps.d
cat > ~/.config/gamescope/apps.d/openrgb.conf <<'EOF'
COMMAND=(
    openrgb
    --startminimized
)
EOF
```

Enable the instance for `gamescope-apps.target`:

```bash
systemctl --user enable gamescope-app@openrgb.service
```

Use `--now` only when the target is already active and the app should start immediately:

```bash
systemctl --user enable --now gamescope-app@openrgb.service
```

## Config format

Every config is a trusted Bash fragment and must define `COMMAND` as an array. Arrays preserve arguments exactly and avoid an unnecessary shell command string.

```bash
COMMAND=(
    flatpak
    run
    com.discordapp.Discord
    --start-minimized
)
```

An optional Xvfb screen can be specified:

```bash
XVFB_SCREEN=1920x1080x24
```

User configs take precedence over system configs with the same name. For example, `~/.config/gamescope/apps.d/discord.conf` overrides `/etc/gamescope/apps.d/discord.conf` without modifying the image.

### Run multiple commands

`COMMAND` normally represents one executable and its arguments. Shell operators such as `&`, `;`, `&&`, pipes, and redirects are not interpreted directly inside the array. To run a sequence of commands, explicitly invoke a shell:

```bash
# ~/.config/gamescope/apps.d/openrgb.conf
COMMAND=(
    bash
    -lc
    'flatpak run org.openrgb.OpenRGB --server &
     sleep 2
     exec flatpak run org.openrgb.OpenRGB --gui --profile "MyRGB"'
)
```

This example starts the OpenRGB server in the background, waits two seconds, and then replaces the shell with the GUI process. Both processes remain in the same systemd service cgroup and are stopped together when the service, Gamescope session, or app target stops.

Keep the primary long-running process last and use `exec` for it when practical. Use `bash -lc` only when shell syntax is actually required; ordinary single commands should remain direct arrays.

## Manage and debug apps

```bash
systemctl --user status gamescope-app@discord.service
systemctl --user restart gamescope-app@discord.service
systemctl --user disable --now gamescope-app@discord.service
journalctl --user -u gamescope-app@discord.service -b
journalctl --user -u gamescope-app@discord.service -f
```

Each app has its own exit status, restart loop, journal, and cgroup. A failure in one app does not restart or obscure the state of another app.

To disable a packaged default while preserving its config:

```bash
systemctl --user mask gamescope-app@discord.service
```

To disable all apps:

```bash
touch ~/.config/gamescope/disable-apps
```

Remove the flag and restart the Gamescope session to enable the target again.

## Migration from the aggregate launcher

The previous implementation read commands from `/etc/gamescope-apps.conf` or `~/.config/gamescope/apps.conf` and launched all of them from one `gamescopeApps.service`. Convert each uncommented command into a separately named config.

Old config:

```text
megasync
flatpak run com.discordapp.Discord --start-minimized
openrgb --startminimized
```

Equivalent per-app configs:

```bash
# ~/.config/gamescope/apps.d/megasync.conf
COMMAND=(megasync)

# ~/.config/gamescope/apps.d/discord.conf
COMMAND=(flatpak run com.discordapp.Discord --start-minimized)

# ~/.config/gamescope/apps.d/openrgb.conf
COMMAND=(openrgb --startminimized)
```

Enable each user-added instance:

```bash
systemctl --user enable gamescope-app@openrgb.service
```

`megasync` and `discord` are packaged target defaults, so they do not need to be enabled manually unless their generated target links have been removed or masked.

The old `gamescopeApps.service`, `startGamescopeApps.sh`, and single-file configs are no longer used.
