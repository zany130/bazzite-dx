# vim: set ft=make :

alias upgrade := update

# Update system, flatpaks, containers, Homebrew, and more with topgrade
[group("system")]
update:
    #!/usr/bin/bash
<<<<<<< ours

    # Source brew if we are not in an interactive session
    [[ $- != *i* ]] && source <(/home/linuxbrew/.linuxbrew/bin/brew shellenv)

    /usr/bin/topgrade --config /etc/ublue-os/topgrade.toml --keep
=======
    /usr/libexec/uupd-update | jq -r -R 'fromjson? | [(.title, .output, .description) | select(.)] | join(" ")'
>>>>>>> upstream

alias changelog := changelogs

# Show the stable changelog
[group("system")]
changelogs:
    #!/usr/bin/bash
    CONTENT=$(curl -s https://api.github.com/repos/ublue-os/bazzite/releases/latest | jq -r '.body')
    echo "$CONTENT" | glow -

# Show the testing (pre-release) changelog
[group("system")]
changelogs-testing:
    #!/usr/bin/bash
    CONTENT=$(curl -s https://api.github.com/repos/ublue-os/bazzite/releases | jq -r 'map(select(.prerelease)) | .[0].body')
    echo "$CONTENT" | glow -
