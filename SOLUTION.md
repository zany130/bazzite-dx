# Gamescope background apps - solution

The Gamescope background-app implementation uses one systemd user-service instance per application.

## Why this design

The previous aggregate launcher started every configured command, checked its launcher PID once after two seconds, and then slept forever. After startup, systemd supervised the sleeping shell rather than each application. Later crashes were not independently observable or recoverable, and all app output was discarded.

The replacement has one service manager: systemd.

- Each app has independent lifecycle and restart behavior.
- Each app has dedicated journal output and exit status.
- One app failure cannot restart or obscure another app.
- Process trees are tracked and cleaned up by cgroup.
- The launcher contains no backgrounding, polling, PID bookkeeping, restart logic, or infinite sleep.
- Users retain easy app-specific configuration and overrides.

## Resulting layout

```text
/usr/lib/systemd/user/gamescope-apps.target
/usr/lib/systemd/user/gamescope-app@.service
/usr/libexec/gamescope-xvfb-launch
/etc/gamescope/apps.d/megasync.conf
/etc/gamescope/apps.d/discord.conf
~/.config/gamescope/apps.d/APP.conf
```

The Gamescope session weakly wants `gamescope-apps.target`. The target groups packaged defaults and any user-enabled instances. Each instance loads the matching app-named config and executes its `COMMAND` array under Xvfb.

Examples:

```bash
systemctl --user status gamescope-app@discord.service
journalctl --user -u gamescope-app@discord.service -b
systemctl --user enable gamescope-app@openrgb.service
```

See `IMPLEMENTATION.md` for architecture details and `GAMESCOPE_APPS.md` for user configuration and migration instructions.
