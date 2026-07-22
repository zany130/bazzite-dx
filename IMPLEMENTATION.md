# Gamescope background apps - implementation

## Overview

Background applications run as independent systemd user-service instances during the Gamescope/Steam session. The implementation deliberately uses systemd as the only service manager; the launcher is responsible only for resolving an app config and executing it under Xvfb.

## Components

```text
gamescope-session-plus@ogui-steam.service
└── gamescope-apps.target
    ├── gamescope-app@megasync.service
    ├── gamescope-app@discord.service
    └── gamescope-app@USER-APP.service
```

- `/usr/lib/systemd/user/gamescope-apps.target` binds the app group to the Gamescope session, conflicts with Plasma Desktop Mode, and pulls in packaged defaults.
- `/usr/lib/systemd/user/gamescope-app@.service` supervises one application per instance.
- `/usr/libexec/gamescope-xvfb-launch` selects the user or system config and uses `exec xvfb-run`.
- `/etc/gamescope/apps.d/*.conf` contains packaged application definitions.
- `~/.config/gamescope/apps.d/*.conf` contains user applications and per-name overrides.
- The Gamescope session drop-in adds only `Wants=gamescope-apps.target`; upstream session files are not replaced.

## Lifecycle and failure behavior

Each application has its own service state, cgroup, logs, exit status, restart policy, and rate limit. `ExitType=cgroup` keeps systemd aware of applications that fork or replace their initial process. `KillMode=control-group` cleans up the complete app process tree when the session ends.

`Restart=on-failure` restarts an app after an unexpected failure while its service remains wanted. A crash in Discord does not restart MegaSync or the target. App failures also do not break the Gamescope session because the session uses a weak `Wants=` dependency.

The target uses `BindsTo=` and `After=` for the Gamescope session, so ending the session stops all participating app services. It also uses `Conflicts=plasma-workspace.target` and `Before=plasma-workspace.target`, ensuring that entering Desktop Mode explicitly stops the app target and all `PartOf=` instances before Plasma starts. This preserves session isolation even if a service was started manually or session shutdown ordering changes.

## Configuration model

The service instance is named after the application, for example:

```text
gamescope-app@discord.service
gamescope-app@megasync.service
gamescope-app@openrgb.service
```

A matching config must define a Bash `COMMAND` array:

```bash
COMMAND=(
    flatpak
    run
    com.discordapp.Discord
    --start-minimized
)
```

Arrays preserve argument boundaries and avoid invoking `bash -lc` for ordinary commands. Configs that require shell operators or multiple commands may explicitly set `COMMAND=(bash -lc '...')`; all resulting processes remain supervised inside the service cgroup. `XVFB_SCREEN` may optionally override the default `1024x768x24` virtual display.

User configs take priority over packaged configs with the same instance name. Users add an app without modifying the image by creating `~/.config/gamescope/apps.d/APP.conf` and enabling `gamescope-app@APP.service`.

See `GAMESCOPE_APPS.md` for user instructions, multi-command examples, and migration details.
