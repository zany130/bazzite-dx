"""Pin source bytes on same-repository Renovate PRs; never execute PR code."""

import base64
import hashlib
import json
import os
import re
import urllib.request

UPSTREAM = "jlobue10/rEFInd_GUI"
BUILD_FILE = "build_files/build.sh"
BRANCH = re.compile(r"renovate/jlobue10-refind_gui-[0-9]+\.x")
VERSION = re.compile(r'^REFIND_GUI_VERSION="(v[0-9]+\.[0-9]+\.[0-9]+)"$', re.M)
RPM_HASH = re.compile(r'^REFIND_GUI_SHA256="([a-f0-9]{64})"$', re.M)
SOURCE_HASH = re.compile(r'^REFIND_GUI_SOURCE_SHA256="([a-f0-9]{64})"$', re.M)


def eligible(pr, repository):
    return (
        pr["state"] == "open"
        and pr["user"]["login"] == "renovate[bot]"
        and pr["user"]["type"] == "Bot"
        and pr["base"]["ref"] == "main"
        and pr["base"]["repo"]["full_name"] == repository
        and pr["head"]["repo"] is not None
        and pr["head"]["repo"]["full_name"] == repository
        and BRANCH.fullmatch(pr["head"]["ref"]) is not None
    )


def one(pattern, text):
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one assignment for {pattern.pattern}")
    return matches[0]


def download_hash(url):
    # Public upstream URLs only; never send the repository token to downloads.
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(url, timeout=60) as response:
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > 256 * 1024 * 1024:
                raise ValueError("Release download exceeds 256 MiB")
            digest.update(chunk)
    if not size:
        raise ValueError("Empty release download")
    return digest.hexdigest()


def updated_source(text, digest=download_hash):
    version = one(VERSION, text)[1]
    rpm_hash = one(RPM_HASH, text)[1]
    source = one(SOURCE_HASH, text)
    rpm = f"rEFInd_GUI-{version[1:]}-1.fc44.x86_64.rpm"
    # Fail closed if Renovate could not map the RPM to this release. Do not
    # repair/replace Renovate's RPM pin with a checksum from the network.
    actual = digest(f"https://github.com/{UPSTREAM}/releases/download/{version}/{rpm}")
    if actual != rpm_hash:
        raise ValueError("RPM does not match Renovate's pinned SHA-256")
    source_digest = digest(f"https://github.com/{UPSTREAM}/archive/refs/tags/{version}.tar.gz")
    if not re.fullmatch(r"[a-f0-9]{64}", source_digest):
        raise ValueError("Invalid source SHA-256")
    return text[:source.start(1)] + source_digest + text[source.end(1):]


class GitHub:
    def __init__(self, token):
        self.token = token

    def __call__(self, method, path, data=None):
        request = urllib.request.Request(
            "https://api.github.com/" + path,
            data=None if data is None else json.dumps(data).encode(),
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "Content-Type": "application/json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
        return json.loads(body) if body else None


def update_pr(api, repository, event, digest=download_hash):
    number = int(event["number"])
    prefix = f"repos/{repository}"
    pr = api("GET", f"{prefix}/pulls/{number}")
    if not eligible(pr, repository):
        print("Not an eligible Renovate PR; nothing changed.")
        return
    head = pr["head"]["sha"]
    if head != event["pull_request"]["head"]["sha"]:
        print("Superseded PR event; nothing changed.")
        return
    branch = pr["head"]["ref"]
    file = api("GET", f"{prefix}/contents/{BUILD_FILE}?ref={head}")
    if file["type"] != "file" or file["encoding"] != "base64":
        raise ValueError("Expected a regular build script")
    text = base64.b64decode(file["content"]).decode("utf-8")
    updated = updated_source(text, digest)
    # Recheck after downloads, including closure or branch replacement.
    current = api("GET", f"{prefix}/pulls/{number}")
    if not eligible(current, repository) or current["head"]["sha"] != head:
        print("PR changed during verification; nothing changed.")
        return
    if updated != text:
        parent = api("GET", f"{prefix}/git/commits/{head}")
        tree = api("POST", f"{prefix}/git/trees", {
            "base_tree": parent["tree"]["sha"],
            "tree": [{"path": BUILD_FILE, "mode": "100755", "type": "blob", "content": updated}],
        })
        commit = api("POST", f"{prefix}/git/commits", {
            "message": "fix: pin rEFInd GUI source archive for Renovate update",
            "tree": tree["sha"], "parents": [head],
        })
        # Never force: a concurrent push makes this sibling commit fail to
        # fast-forward, rather than overwriting the contributor's changes.
        api("PATCH", f"{prefix}/git/refs/heads/{branch}", {
            "sha": commit["sha"], "force": False,
        })
        head = commit["sha"]
        print(f"Pinned source checksum in {head}.")
    else:
        print("Both pinned checksums already match upstream.")
    # GITHUB_TOKEN pushes are not a reliable trigger for PR builds. Explicit
    # dispatch works with GITHUB_TOKEN and also covers a no-op or retried run.
    # Checkout is pinned to the verified commit even if the branch advances.
    api("POST", f"{prefix}/actions/workflows/build.yml/dispatches", {
        "ref": branch, "inputs": {"verified_head": head},
    })
    print(f"Dispatched image build for {head}.")


if __name__ == "__main__":
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as event_file:
        event = json.load(event_file)
    update_pr(GitHub(os.environ["GH_TOKEN"]), os.environ["GITHUB_REPOSITORY"], event)
