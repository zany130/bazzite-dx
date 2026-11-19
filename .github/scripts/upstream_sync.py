#!/usr/bin/env python3
"""Three-way merge upstream Bazzite changes into locally customised copies.

Each entry in .github/upstream-sync.json records the upstream commit our copy
was last synced with (base_sha). For every file the script fetches the base
and the current upstream version and runs `git merge-file` so local
customisations are kept. Entries with no base_sha are only pinned to the
current upstream commit (no file change) so later runs can merge.
Entries with mode=notify-only preserve local files and report new upstream
content states once via issues (including closed issues as receipts).
Unchanged upstream content never advances the baseline.
Writes a summary to the path in $SUMMARY_FILE and sets changed=true in
$GITHUB_OUTPUT when anything was modified.
"""
import hashlib, json, os, subprocess, tempfile, urllib.error, urllib.request
from pathlib import Path

CFG = ".github/upstream-sync.json"


def api(url, data=None):
    payload = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(url, data=payload, headers={
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    })
    if os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def raw(repo, ref, path):
    try:
        with urllib.request.urlopen(f"https://raw.githubusercontent.com/{repo}/{ref}/{path}") as r:
            return r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


heads = {}


def head_of(repo, branch):
    if (repo, branch) not in heads:
        heads[(repo, branch)] = api(f"https://api.github.com/repos/{repo}/commits/{branch}")["sha"]
    return heads[(repo, branch)]


def is_text(b):
    return b"\0" not in b


def notify(f, repo, head, new, notifications, notes):
    """Use open AND closed issues as durable receipts for upstream states."""
    target = os.environ["GITHUB_REPOSITORY"]
    endpoint = f"https://api.github.com/repos/{target}/issues"
    if not notifications.get("loaded"):
        page = 1
        bodies = notifications.setdefault("bodies", [])
        while True:
            issues = api(f"{endpoint}?state=all&per_page=100&page={page}")
            bodies.extend(issue.get("body") or "" for issue in issues
                          if "pull_request" not in issue)
            if len(issues) < 100:
                break
            page += 1
        notifications["loaded"] = True
    state = "missing" if new is None else hashlib.sha256(new).hexdigest()
    identity = json.dumps([repo, f["upstream"], f["local"], state])
    marker = "<!-- upstream-sync:" + hashlib.sha256(identity.encode()).hexdigest() + " -->"
    if any(marker in body for body in notifications["bodies"]):
        return
    base_sha = f["base_sha"]
    status = "was removed" if new is None else "changed"
    body = (
        f"{marker}\n"
        f"Upstream `{repo}:{f['upstream']}` {status}.\n\n"
        f"The customized local file `{f['local']}` was left untouched. "
        "Review the upstream change and apply any desired parts manually.\n\n"
        f"- [Baseline file](https://github.com/{repo}/blob/{base_sha}/{f['upstream']})\n"
        f"- [Upstream commit](https://github.com/{repo}/commit/{head})\n"
        f"- [Changes since baseline](https://github.com/{repo}/compare/{base_sha}...{head})\n"
        + (f"- [Current file](https://github.com/{repo}/blob/{head}/{f['upstream']})\n"
           if new is not None else "")
        + "\nClosing this issue dismisses this upstream content state. "
        "The scheduled check will not open another issue for the same state. "
        "Keep this issue (open or closed) as the notification receipt.\n"
    )
    issue = api(endpoint, {
        "title": f"Upstream change: {f['local']}",
        "body": body,
    })
    notifications["bodies"].append(body)
    notes.append(f"- `{f['local']}`: upstream {status}; {issue['html_url']} (local copy preserved)")


def main():
    heads.clear()
    with open(CFG) as stream:
        cfg = json.load(stream)
    notifications = {}
    notes, changed = [], False

    for f in cfg["files"]:
        repo = f.get("repo", cfg["repo"])
        head = head_of(repo, f.get("branch", cfg["branch"]))
        new = raw(repo, head, f["upstream"])
        if f.get("mode", "merge") == "notify-only":
            base_sha = f.get("base_sha")
            if not base_sha:
                raise ValueError(f"notify-only requires base_sha: {f['local']}")
            base = raw(repo, base_sha, f["upstream"])
            if base != new:
                notify(f, repo, head, new, notifications, notes)
            continue
        if f.get("mode", "merge") != "merge":
            raise ValueError(f"Unknown sync mode: {f['mode']}")
        if new is None:
            notes.append(f"- `{f['local']}`: upstream file `{f['upstream']}` no longer exists, review manually")
            continue
        base_sha = f.get("base_sha")
        if not os.path.exists(f["local"]):
            os.makedirs(os.path.dirname(f["local"]), exist_ok=True)
            Path(f["local"]).write_bytes(new)
            f["base_sha"] = head
            changed = True
            notes.append(f"- `{f['local']}`: added from `{repo}` `{head[:9]}`")
            continue
        if not base_sha:
            f["base_sha"] = head
            changed = True
            notes.append(f"- `{f['local']}`: pinned to upstream `{head[:9]}` (first run, no merge performed)")
            continue
        if base_sha == head:
            continue
        base = raw(repo, base_sha, f["upstream"])
        if base == new:
            continue
        local_bytes = Path(f["local"]).read_bytes()
        if base is None or not (is_text(new) and is_text(local_bytes)):
            if local_bytes == base:
                Path(f["local"]).write_bytes(new)
                notes.append(f"- `{f['local']}`: updated from upstream")
            else:
                notes.append(f"- `{f['local']}`: changed upstream and locally (or binary), review manually")
                continue
            f["base_sha"] = head
            changed = True
            continue
        with tempfile.TemporaryDirectory() as d:
            paths = {}
            for name, data in (("base", base), ("new", new), ("local", local_bytes)):
                paths[name] = os.path.join(d, name)
                Path(paths[name]).write_bytes(data)
            rc = subprocess.run(["git", "merge-file", "-L", "ours", "-L", "upstream-base", "-L", "upstream",
                                 paths["local"], paths["base"], paths["new"]]).returncode
            if not 0 <= rc <= 127:
                raise SystemExit(f"merge-file failed for {f['local']}")
            Path(f["local"]).write_bytes(Path(paths["local"]).read_bytes())
        f["base_sha"] = head
        changed = True
        notes.append(f"- `{f['local']}`: merged upstream changes" +
                     (f" with **{rc} conflict(s)** - resolve the conflict markers before merging" if rc else ""))

    if changed:
        Path(CFG).write_text(json.dumps(cfg, indent=2) + "\n")
    Path(os.environ.get("SUMMARY_FILE", "/dev/null")).write_text("\n".join(notes) + "\n")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"changed={'true' if changed else 'false'}\n")
    print("\n".join(notes))


if __name__ == "__main__":
    main()
