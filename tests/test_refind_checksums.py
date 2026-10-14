import base64
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("checksums", ROOT / ".github/scripts/refind_checksums.py")
checksums = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checksums)
REPO = "zany130/bazzite-dx"
TEXT = (ROOT / "build_files/build.sh").read_text()
CURRENT_VERSION = checksums.one(checksums.VERSION, TEXT)[1]
RPM = checksums.one(checksums.RPM_HASH, TEXT)[1]
SOURCE = checksums.one(checksums.SOURCE_HASH, TEXT)[1]
PR = {
    "state": "open", "user": {"login": "renovate[bot]", "type": "Bot"},
    "base": {"ref": "main", "repo": {"full_name": REPO}},
    "head": {"ref": "renovate/jlobue10-refind_gui-3.x", "sha": "a" * 40,
             "repo": {"full_name": REPO}},
}
EVENT = {"number": 255, "pull_request": copy.deepcopy(PR)}


class ChecksumsTest(unittest.TestCase):
    def api(self, second=None, conflict=False, pr=None):
        reads = 0

        def respond(method, path, data=None):
            nonlocal reads
            if path.endswith("/pulls/255"):
                reads += 1
                return copy.deepcopy(second if second and reads > 1 else pr or PR)
            if "/contents/" in path:
                self.assertTrue(path.endswith("?ref=" + PR["head"]["sha"]))
                return {"type": "file", "encoding": "base64",
                        "content": base64.b64encode(TEXT.encode()).decode()}
            if method == "GET" and "/git/commits/" in path:
                return {"tree": {"sha": "b" * 40}}
            if path.endswith("/git/trees"):
                self.assertEqual(len(data["tree"]), 1)
                self.assertEqual(data["tree"][0]["path"], checksums.BUILD_FILE)
                self.assertEqual(data["tree"][0]["content"], TEXT.replace(SOURCE, "c" * 64))
                return {"sha": "d" * 40}
            if path.endswith("/git/commits"):
                self.assertEqual(data["parents"], [PR["head"]["sha"]])
                return {"sha": "e" * 40}
            if method == "PATCH":
                self.assertFalse(data["force"])
                self.assertTrue(path.endswith(PR["head"]["ref"]))
                if conflict:
                    raise RuntimeError("Not a fast-forward")
                return {}
            if path.endswith("/dispatches"):
                self.assertEqual(data["ref"], PR["head"]["ref"])
                return None
            self.fail(f"Unexpected API call: {method} {path}")

        return Mock(side_effect=respond)

    def test_allowlist(self):
        self.assertTrue(checksums.eligible(PR, REPO))
        for branch in ["main", "renovate/unrelated-3.x", "renovate/jlobue10-refind_gui-3.x/extra"]:
            pr = copy.deepcopy(PR)
            pr["head"]["ref"] = branch
            self.assertFalse(checksums.eligible(pr, REPO))
        for key, value in [("state", "closed"), ("user", {"login": "human", "type": "User"})]:
            pr = copy.deepcopy(PR)
            pr[key] = value
            self.assertFalse(checksums.eligible(pr, REPO))
        for repo in [None, {"full_name": "attacker/fork"}]:
            pr = copy.deepcopy(PR)
            pr["head"]["repo"] = repo
            api = self.api(pr=pr)
            checksums.update_pr(api, REPO, EVENT)
            self.assertEqual(api.call_count, 1)
        pr = copy.deepcopy(PR)
        pr["head"]["ref"] = "renovate/jlobue10-refind_gui-4.x"
        self.assertTrue(checksums.eligible(pr, REPO))

    def test_updates_only_source_hash(self):
        download = Mock(side_effect=[RPM, "c" * 64])
        result = checksums.updated_source(TEXT, download)
        self.assertEqual(result, TEXT.replace(SOURCE, "c" * 64))
        urls = [call.args[0] for call in download.call_args_list]
        self.assertTrue(urls[0].endswith(f"/{CURRENT_VERSION}/rEFInd_GUI-{CURRENT_VERSION[1:]}-1.fc44.x86_64.rpm"))
        self.assertTrue(urls[1].endswith(f"/refs/tags/{CURRENT_VERSION}.tar.gz"))

    def test_future_release(self):
        text = TEXT.replace(f'REFIND_GUI_VERSION="{CURRENT_VERSION}"', 'REFIND_GUI_VERSION="v4.2.1"')
        download = Mock(side_effect=[RPM, "c" * 64])
        checksums.updated_source(text, download)
        self.assertIn("/v4.2.1/rEFInd_GUI-4.2.1-1.fc44.x86_64.rpm", download.call_args_list[0].args[0])

    def test_rpm_mismatch_stops_before_source_download(self):
        download = Mock(return_value="0" * 64)
        with self.assertRaisesRegex(ValueError, "RPM does not match"):
            checksums.updated_source(TEXT, download)
        self.assertEqual(download.call_count, 1)

    def test_rejects_ambiguous_or_injected_version(self):
        for text in [TEXT + '\nREFIND_GUI_VERSION="v4.0.0"\n',
                     TEXT.replace(f'REFIND_GUI_VERSION="{CURRENT_VERSION}"', 'REFIND_GUI_VERSION="$(touch /tmp/unsafe)"')]:
            download = Mock()
            with self.assertRaises(ValueError):
                checksums.updated_source(text, download)
            download.assert_not_called()

    def test_commit_then_dispatch_verified_head(self):
        api = self.api()
        checksums.update_pr(api, REPO, EVENT, Mock(side_effect=[RPM, "c" * 64]))
        self.assertEqual(api.call_args.args[2]["inputs"], {"verified_head": "e" * 40})

    def test_noop_still_dispatches_without_commit(self):
        api = self.api()
        checksums.update_pr(api, REPO, EVENT, Mock(side_effect=[RPM, SOURCE]))
        writes = [call for call in api.call_args_list if call.args[0] != "GET"]
        self.assertEqual(len(writes), 1)
        self.assertEqual(writes[0].args[2]["inputs"], {"verified_head": PR["head"]["sha"]})

    def test_stale_event_skipped(self):
        event = copy.deepcopy(EVENT)
        event["pull_request"]["head"]["sha"] = "f" * 40
        api = self.api()
        checksums.update_pr(api, REPO, event)
        self.assertEqual(api.call_count, 1)

    def test_race_after_download_skipped(self):
        changed = copy.deepcopy(PR)
        changed["head"]["sha"] = "f" * 40
        api = self.api(second=changed)
        checksums.update_pr(api, REPO, EVENT, Mock(side_effect=[RPM, "c" * 64]))
        self.assertTrue(all(call.args[0] == "GET" for call in api.call_args_list))

    def test_push_conflict_does_not_dispatch(self):
        api = self.api(conflict=True)
        with self.assertRaisesRegex(RuntimeError, "fast-forward"):
            checksums.update_pr(api, REPO, EVENT, Mock(side_effect=[RPM, "c" * 64]))
        self.assertFalse(any(call.args[1].endswith("/dispatches") for call in api.call_args_list))


if __name__ == "__main__":
    unittest.main()
