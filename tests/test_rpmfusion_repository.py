"""Regression tests for RPM Fusion repository bootstrapping."""

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPOSITORIES = ROOT / "build_files" / "lib" / "repositories.sh"


class RpmFusionRepositoryTest(unittest.TestCase):
    def run_ensure(self, repos="", fail_repolist=False, install_status=0):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bindir = root / "bin"
            bindir.mkdir()
            mock = bindir / "dnf5"
            mock.write_text(
                textwrap.dedent(
                    """\
                    #!/bin/bash
                    printf '%s\\n' "$*" >> "${DNF_MOCK_LOG:?}"
                    if [[ "$1" == "repolist" && "$2" == "--all" ]]; then
                        if [[ "${DNF_MOCK_FAIL_REPOLIST:-}" == 1 ]]; then
                            echo "dnf5: simulated repolist failure" >&2
                            exit 1
                        fi
                        printf 'repo id name status\\n%s' "${DNF_MOCK_REPOS:-}"
                        exit
                    fi
                    if [[ "$1" == "--setopt=optional_metadata_types=filelists" &&
                          "$2" == "install" && "$3" == "-y" ]]; then
                        exit "${DNF_MOCK_INSTALL_STATUS:-0}"
                    fi
                    echo "unexpected dnf5 invocation: $*" >&2
                    exit 99
                    """
                )
            )
            mock.chmod(0o755)
            log_path = root / "dnf.log"
            env = os.environ.copy()
            env.update(
                {
                    "PATH": f"{bindir}{os.pathsep}{env.get('PATH', '')}",
                    "DNF_MOCK_LOG": str(log_path),
                    "DNF_MOCK_REPOS": repos,
                    "DNF_MOCK_FAIL_REPOLIST": "1" if fail_repolist else "0",
                    "DNF_MOCK_INSTALL_STATUS": str(install_status),
                }
            )
            script = (
                f"source {str(REPOSITORIES)!r}\n"
                "ensure_rpmfusion_release_repos "
                "'rpmfusion-free=https://example.invalid/rpmfusion-free-release-45.noarch.rpm' "
                "'rpmfusion-nonfree=https://example.invalid/rpmfusion-nonfree-release-45.noarch.rpm'\n"
            )
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", script],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

            log = log_path.read_text() if log_path.exists() else ""
            return result, log

    def test_missing_release_packages_install_in_one_transaction(self):
        result, log = self.run_ensure()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            log.splitlines(),
            [
                "repolist --all",
                "--setopt=optional_metadata_types=filelists install -y "
                "https://example.invalid/rpmfusion-free-release-45.noarch.rpm "
                "https://example.invalid/rpmfusion-nonfree-release-45.noarch.rpm",
            ],
        )

    def test_only_missing_release_package_is_installed(self):
        result, log = self.run_ensure("rpmfusion-free Fedora 45 enabled\n")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "--setopt=optional_metadata_types=filelists install -y "
            "https://example.invalid/rpmfusion-nonfree-release-45.noarch.rpm",
            log,
        )
        self.assertNotIn("rpmfusion-free-release-45.noarch.rpm", log)

    def test_existing_release_packages_need_no_install(self):
        result, log = self.run_ensure(
            "rpmfusion-free Fedora 45 enabled\n"
            "rpmfusion-nonfree Fedora 45 enabled\n"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.splitlines(), ["repolist --all"])

    def test_repository_listing_failure_is_reported(self):
        result, log = self.run_ensure(fail_repolist=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to list DNF repositories while checking RPM Fusion", result.stderr)
        self.assertIn("simulated repolist failure", result.stderr)
        self.assertEqual(log.splitlines(), ["repolist --all"])

    def test_release_install_failure_is_reported(self):
        result, log = self.run_ensure(install_status=42)

        self.assertEqual(result.returncode, 42)
        self.assertIn("install -y https://example.invalid/rpmfusion-free-release-45.noarch.rpm", log)


if __name__ == "__main__":
    unittest.main()
