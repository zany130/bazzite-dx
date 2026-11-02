#!/usr/bin/env python3
"""Three-way merge upstream Bazzite changes into locally customised copies.

Each entry in .github/upstream-sync.json records the upstream commit our copy
was last synced with (base_sha). For every file the script fetches the base
and the current upstream version and runs `git merge-file` so local
customisations are kept. Entries with no base_sha are only pinned to the
current upstream commit (no file change) so later runs can merge.
Writes a summary to the path in $SUMMARY_FILE and sets changed=true in
$GITHUB_OUTPUT when anything was modified.
"""
import json, os, subprocess, tempfile, urllib.error, urllib.request

CFG = ".github/upstream-sync.json"


def api(url):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
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


cfg = json.load(open(CFG))
heads = {}


def head_of(repo, branch):
    if (repo, branch) not in heads:
        heads[(repo, branch)] = api(f"https://api.github.com/repos/{repo}/commits/{branch}")["sha"]
    return heads[(repo, branch)]


def is_text(b):
    return b"\0" not in b


notes, changed = [], False

for f in cfg["files"]:
    repo = f.get("repo", cfg["repo"])
    head = head_of(repo, f.get("branch", cfg["branch"]))
    new = raw(repo, head, f["upstream"])
    if new is None:
        notes.append(f"- `{f['local']}`: upstream file `{f['upstream']}` no longer exists, review manually")
        continue
    base_sha = f.get("base_sha")
    if not os.path.exists(f["local"]):
        os.makedirs(os.path.dirname(f["local"]), exist_ok=True)
        open(f["local"], "wb").write(new)
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
        f["base_sha"] = head
        changed = True
        continue
    local_bytes = open(f["local"], "rb").read()
    if base is None or not (is_text(new) and is_text(local_bytes)):
        if local_bytes == base:
            open(f["local"], "wb").write(new)
            notes.append(f"- `{f['local']}`: updated from upstream")
        else:
            notes.append(f"- `{f['local']}`: changed upstream and locally (or binary), review manually")
        f["base_sha"] = head
        changed = True
        continue
    with tempfile.TemporaryDirectory() as d:
        paths = {}
        for name, data in (("base", base), ("new", new), ("local", local_bytes)):
            paths[name] = os.path.join(d, name)
            open(paths[name], "wb").write(data)
        rc = subprocess.run(["git", "merge-file", "-L", "ours", "-L", "upstream-base", "-L", "upstream",
                             paths["local"], paths["base"], paths["new"]]).returncode
        if not 0 <= rc <= 127:
            raise SystemExit(f"merge-file failed for {f['local']}")
        open(f["local"], "wb").write(open(paths["local"], "rb").read())
    f["base_sha"] = head
    changed = True
    notes.append(f"- `{f['local']}`: merged upstream changes" +
                 (f" with **{rc} conflict(s)** - resolve the conflict markers before merging" if rc else ""))

if changed:
    json.dump(cfg, open(CFG, "w"), indent=2)
    open(CFG, "a").write("\n")
open(os.environ.get("SUMMARY_FILE", "/dev/null"), "w").write("\n".join(notes) + "\n")
if os.environ.get("GITHUB_OUTPUT"):
    open(os.environ["GITHUB_OUTPUT"], "a").write(f"changed={'true' if changed else 'false'}\n")
print("\n".join(notes))
