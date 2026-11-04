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
    def test_release_install_requests_filelists_metadata(self):
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
                        printf 'repo id name status\\nfedora Fedora enabled\\n'
                        exit 0
                    fi
                    if [[ "$1" == "--setopt=optional_metadata_types=filelists" &&
                          "$2" == "install" && "$3" == "-y" ]]; then
                        exit 0
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
                }
            )
            script = (
                f"source {str(REPOSITORIES)!r}\n"
                "ensure_rpmfusion_release_repo rpmfusion-free "
                "'https://example.invalid/rpmfusion-free-release-45.noarch.rpm'\n"
            )
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", script],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "--setopt=optional_metadata_types=filelists install -y "
                "https://example.invalid/rpmfusion-free-release-45.noarch.rpm",
                log_path.read_text(),
            )


if __name__ == "__main__":
    unittest.main()
