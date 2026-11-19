import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("upstream_sync", ROOT / ".github/scripts/upstream_sync.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class UpstreamSyncTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        previous = os.getcwd()
        os.chdir(self.temp.name)
        self.addCleanup(os.chdir, previous)
        Path(".github").mkdir()
        self.entry = {"local": "custom/file", "upstream": "upstream/file",
                      "base_sha": "old", "mode": "notify-only"}
        Path("custom").mkdir()
        Path("custom/file").write_bytes(b"my customization\n")
        self.issues = []
        self.posts = []
        self.pages = []
        self.base = b"upstream original\n"
        self.new = b"upstream changed\n"
        self.head = "new"
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {"GITHUB_REPOSITORY": "owner/fork",
                               "GITHUB_OUTPUT": "output",
                               "SUMMARY_FILE": "summary"}).start()
        patch.object(sync, "api", side_effect=self.api).start()
        patch.object(sync, "raw", side_effect=self.raw).start()

    def raw(self, repo, ref, path):
        return self.base if ref == "old" else self.new

    def api(self, url, data=None):
        if "/commits/" in url:
            return {"sha": self.head}
        if data is not None:
            self.posts.append(data)
            issue = dict(data, html_url="https://github.com/owner/fork/issues/1")
            self.issues.append(issue)
            return issue
        self.assertIn("state=all", url)
        page = int(url.rsplit("=", 1)[1])
        self.pages.append(page)
        return self.issues[(page - 1) * 100:page * 100]

    def run_sync(self):
        cfg = {"repo": "upstream/repo", "branch": "main", "files": [self.entry]}
        Path(sync.CFG).write_text(json.dumps(cfg))
        original = Path(sync.CFG).read_bytes()
        Path("output").write_text("")
        with contextlib.redirect_stdout(io.StringIO()):
            sync.main()
        return original

    def test_notify_preserves_local_and_config(self):
        original = self.run_sync()
        self.assertEqual(Path("custom/file").read_bytes(), b"my customization\n")
        self.assertEqual(Path(sync.CFG).read_bytes(), original)
        self.assertEqual(Path("output").read_text(), "changed=false\n")
        self.assertEqual(len(self.posts), 1)
        self.assertIn("/compare/old...new", self.posts[0]["body"])

    def test_unchanged_content_is_silent_in_both_modes(self):
        self.new = self.base
        for mode in ("merge", "notify-only"):
            self.entry["mode"] = mode
            original = self.run_sync()
            self.assertEqual(Path(sync.CFG).read_bytes(), original)
            self.assertEqual(Path("output").read_text(), "changed=false\n")
        self.assertFalse(self.posts)

    def test_open_and_closed_issues_deduplicate_across_commits(self):
        self.run_sync()
        self.run_sync()
        self.issues[0]["state"] = "closed"
        self.head = "later"
        self.run_sync()
        self.assertEqual(len(self.posts), 1)

    def test_changed_content_notifies_again(self):
        self.run_sync()
        self.new = b"another change\n"
        self.run_sync()
        self.assertEqual(len(self.posts), 2)

    def test_deletion_once_then_restoration(self):
        self.new = None
        self.run_sync()
        self.run_sync()
        self.assertEqual(len(self.posts), 1)
        self.assertIn("was removed", self.posts[0]["body"])
        self.new = b"restored with changes\n"
        self.run_sync()
        self.assertEqual(len(self.posts), 2)
        self.assertEqual(Path("custom/file").read_bytes(), b"my customization\n")

    def test_notify_does_not_recreate_missing_local_file(self):
        Path("custom/file").unlink()
        self.run_sync()
        self.assertFalse(Path("custom/file").exists())

    def test_pagination_finds_closed_receipt(self):
        self.run_sync()
        receipt = dict(self.issues[0], state="closed")
        self.issues = [{"body": "unrelated"} for _ in range(100)] + [receipt]
        self.pages.clear()
        self.run_sync()
        self.assertEqual(self.pages, [1, 2])
        self.assertEqual(len(self.posts), 1)

    def test_pr_body_is_not_a_receipt(self):
        self.run_sync()
        self.issues[0]["pull_request"] = {}
        self.run_sync()
        self.assertEqual(len(self.posts), 2)

    def test_normal_three_way_merge_keeps_customization(self):
        self.entry.pop("mode")
        self.base = b"first\nsecond\nthird\nfourth\n"
        self.new = b"upstream\nsecond\nthird\nfourth\n"
        Path("custom/file").write_bytes(b"first\nsecond\nthird\ncustom\n")
        self.run_sync()
        self.assertEqual(Path("custom/file").read_bytes(), b"upstream\nsecond\nthird\ncustom\n")
        self.assertEqual(Path("output").read_text(), "changed=true\n")
        self.assertEqual(json.loads(Path(sync.CFG).read_text())["files"][0]["base_sha"], "new")
        self.assertFalse(self.posts)

    def test_notification_failure_fails_run(self):
        def fail_post(url, data=None):
            if data is not None:
                raise RuntimeError("API failure")
            return self.api(url)
        with patch.object(sync, "api", side_effect=fail_post):
            with self.assertRaises(RuntimeError):
                self.run_sync()
        self.assertFalse(self.posts)
        self.assertEqual(Path("custom/file").read_bytes(), b"my customization\n")

    def test_missing_baseline_is_rejected(self):
        self.entry.pop("base_sha")
        with self.assertRaises(ValueError):
            self.run_sync()


if __name__ == "__main__":
    unittest.main()
