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
import json, os, subprocess, tempfile, urllib.request

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
            return r.read().decode()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


cfg = json.load(open(CFG))
repo = cfg["repo"]
head = api(f"https://api.github.com/repos/{repo}/commits/{cfg['branch']}")["sha"]
notes, changed = [], False

for f in cfg["files"]:
    new = raw(repo, head, f["upstream"])
    if new is None:
        notes.append(f"- `{f['local']}`: upstream file `{f['upstream']}` no longer exists, review manually")
        continue
    base_sha = f.get("base_sha")
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
    base = base or ""
    with tempfile.TemporaryDirectory() as d:
        paths = {}
        for name, text in (("base", base), ("new", new)):
            paths[name] = os.path.join(d, name)
            open(paths[name], "w").write(text)
        local = os.path.join(d, "local")
        open(local, "w").write(open(f["local"]).read())
        rc = subprocess.run(["git", "merge-file", "-L", "ours", "-L", "upstream-base", "-L", "upstream",
                             local, paths["base"], paths["new"]]).returncode
        if not 0 <= rc <= 127:
            raise SystemExit(f"merge-file failed for {f['local']}")
        open(f["local"], "w").write(open(local).read())
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
