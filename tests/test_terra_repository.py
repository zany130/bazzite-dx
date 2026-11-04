"""Regression tests for Fedora 45 Terra repository configuration."""

import os
import re
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build_files" / "lib" / "repositories.sh"
THIRD_PARTY = ROOT / "build_files" / "stages" / "04-third-party-packages.sh"
BUILD_SCRIPTS = ROOT / "build_files"
FUNCTION = re.compile(
    r"^configure_terra_repository\(\) \{\n.*?\n\}",
    re.MULTILINE | re.DOTALL,
)
EXCLUDES = "qt6-*,kf6-*,plasma-*,fcitx5-qt*"


def load_function():
    match = FUNCTION.search(BUILD.read_text())
    if match is None:
        raise AssertionError("configure_terra_repository() is missing from lib/repositories.sh")
    return match.group(0)


class TerraRepositoryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = BUILD.read_text()
        cls.function = load_function()

    def test_build_script_does_not_edit_packaged_terra_repo(self):
        scripts = "\n".join(path.read_text() for path in BUILD_SCRIPTS.rglob("*.sh"))
        self.assertNotRegex(scripts, r">>\s*/etc/yum\.repos\.d/terra\.repo")
        self.assertNotRegex(scripts, r"sed\s+-i[^\n]*terra\.repo")
        self.assertNotRegex(self.text, r"grep[^\n]*terra\.repo")
        self.assertIn("Refusing to create /etc/yum.repos.d/terra.repo.", self.function)
        self.assertIn('terra_excludes="qt6-*,kf6-*,plasma-*,fcitx5-qt*"', self.function)
        self.assertIn('"${terra_repo_id}.enabled=0"', self.function)
        self.assertIn('"${terra_repo_id}.excludepkgs=${terra_excludes}"', self.function)

    def test_terra_packages_still_install_from_an_explicit_repo(self):
        self.assertRegex(
            THIRD_PARTY.read_text(),
            r"dnf_install_with_retry terra \\\n"
            r"\s+coolercontrol \\\n"
            r"\s+sbctl \\\n"
            r"\s+topgrade\n",
        )

    def test_scoped_install_retries_under_strict_mode(self):
        # Use a capability with spaces to detect accidental splitting of "$@".
        install = ["--refresh", "--enable-repo=example", "install", "-y", "one", "two >= 1"]
        clean = ["clean", "all", "--enable-repo=example"]
        script = r'''set -euo pipefail
source "$1"
calls=0
dnf5() {
    printf '%s\0' "$@" >> "$LOG"
    printf '\0' >> "$LOG"
    if [[ "$1" == clean ]]; then
        return "$CLEAN_STATUS"
    fi
    calls=$((calls + 1))
    (( calls > FAILURES ))
}
dnf_install_with_retry example one "two >= 1"
echo continued
'''
        for failures, clean_status, succeeds, expected in [
            (0, 0, True, [install]),
            (1, 0, True, [install, clean, install]),
            (3, 0, False, [install, clean, install, clean, install]),
            (1, 1, False, [install, clean]),
        ]:
            with self.subTest(failures=failures, clean_status=clean_status), tempfile.TemporaryDirectory() as tmp:
                log = Path(tmp) / "calls"
                result = subprocess.run(
                    ["bash", "-c", script, "test", str(BUILD)],
                    env={**os.environ, "LOG": str(log), "FAILURES": str(failures),
                         "CLEAN_STATUS": str(clean_status)},
                    text=True, capture_output=True,
                )
                calls = log.read_bytes().decode().split("\0\0")
                self.assertEqual(calls.pop(), "")
                self.assertEqual([call.split("\0") for call in calls], expected)
                self.assertEqual(result.returncode, 0 if succeeds else 1, result.stderr)
                self.assertEqual("continued" in result.stdout, succeeds)
                if failures == 3:
                    self.assertIn("after 3 attempts", result.stderr)

    def test_override_is_applied_when_terra_already_exists(self):
        result, log, created = self.run_configure("terra Terra-45 enabled\nfedora Fedora enabled\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            f"config-manager setopt terra.enabled=0 terra.excludepkgs={EXCLUDES}",
            log,
        )
        self.assertFalse(created)

    def test_missing_terra_repository_is_not_invented(self):
        result, log, created = self.run_configure("fedora Fedora enabled\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to create /etc/yum.repos.d/terra.repo.", result.stderr)
        self.assertNotIn("Failed to list DNF repositories", result.stderr)
        self.assertNotIn("config-manager", log)
        self.assertFalse(created)

    def test_repository_listing_errors_are_not_reported_as_a_missing_repo(self):
        result, log, created = self.run_configure("", fail_repolist=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to list DNF repositories while configuring Terra.", result.stderr)
        self.assertIn("simulated repolist failure", result.stderr)
        self.assertNotIn("Refusing to create", result.stderr)
        self.assertNotIn("config-manager", log)
        self.assertFalse(created)

    def run_configure(self, repos, fail_repolist=False):
        function = self.function
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bindir = root / "bin"
            etc = root / "etc/yum.repos.d"
            bindir.mkdir()
            etc.mkdir(parents=True)
            mock = bindir / "dnf5"
            mock.write_text(
                textwrap.dedent(
                    """\
                    #!/bin/bash
                    set -euo pipefail
                    printf '%s\\n' "$*" >> "${DNF_MOCK_LOG:?}"
                    if [[ "$1" == "repolist" && "$2" == "--all" ]]; then
                        if [[ "${DNF_MOCK_FAIL_REPOLIST:-}" == 1 ]]; then
                            echo "dnf5: simulated repolist failure" >&2
                            exit 1
                        fi
                        printf 'repo id name status\\n'
                        printf '%s' "${DNF_MOCK_REPOS:-}"
                        exit 0
                    fi
                    if [[ "$1" == "config-manager" && "$2" == "setopt" ]]; then
                        exit 0
                    fi
                    echo "unexpected dnf5 invocation: $*" >&2
                    exit 99
                    """
                )
            )
            mock.chmod(mock.stat().st_mode | stat.S_IEXEC)
            log_path = root / "dnf.log"
            env = os.environ.copy()
            env.update(
                {
                    "PATH": f"{bindir}{os.pathsep}{env.get('PATH', '')}",
                    "DNF_MOCK_LOG": str(log_path),
                    "DNF_MOCK_REPOS": repos,
                    "DNF_MOCK_FAIL_REPOLIST": "1" if fail_repolist else "0",
                    "HOME": str(root),
                }
            )
            script = f"set -euo pipefail\n{function}\nconfigure_terra_repository\n"
            result = subprocess.run(
                ["bash", "-c", script],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            log = log_path.read_text() if log_path.exists() else ""
            created = (etc / "terra.repo").exists()
            return result, log, created


if __name__ == "__main__":
    unittest.main()
