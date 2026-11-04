"""Checksum downloads and loose RPM versions keep their previous behavior."""

import hashlib
import os
import stat
import subprocess
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "build_files" / "lib" / "common.sh"


class BuildHelpersTest(unittest.TestCase):
    def test_loose_rpm_version_pads_two_component_tags(self):
        script = f'source "{COMMON}"\nloose_rpm_version "$1"\n'
        for version, expected in {
            "v1.0": "1.0.0",
            "V1.0": "1.0.0",
            "1.2": "1.2.0",
            "v1.2.3": "1.2.3",
            "v1.0.0-78": "1.0.0-78",
        }.items():
            result = subprocess.run(
                ["bash", "-c", script, "bash", version],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected + "\n", version)

    def test_download_verified_retries_and_checks_two_space_sha256(self):
        payload = b"pinned-bytes"
        digest = hashlib.sha256(payload).hexdigest()
        with tempfile_dir() as root:
            bindir = root / "bin"
            bindir.mkdir()
            log_path = root / "curl.log"
            mock = bindir / "curl"
            mock.write_text(
                textwrap.dedent(
                    """\
                    #!/bin/bash
                    set -euo pipefail
                    printf '%s\\n' "$*" >> "${CURL_MOCK_LOG:?}"
                    [[ "$1" == "--fail-with-body" && "$2" == "--retry" && "$3" == "3" && "$4" == "-Lo" ]]
                    printf 'pinned-bytes' > "$5"
                    """
                )
            )
            mock.chmod(mock.stat().st_mode | stat.S_IEXEC)
            dest = root / "payload"
            env = os.environ.copy()
            env.update(
                {
                    "PATH": f"{bindir}{os.pathsep}{env.get('PATH', '')}",
                    "CURL_MOCK_LOG": str(log_path),
                }
            )
            script = f'set -euo pipefail\nsource "{COMMON}"\ndownload_verified "$1" "$2" "$3"\n'
            result = subprocess.run(
                ["bash", "-c", script, "bash", "https://example.test/file", str(dest), digest],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(": OK", result.stdout)
            self.assertEqual(
                log_path.read_text().strip(),
                f"--fail-with-body --retry 3 -Lo {dest} https://example.test/file",
            )
            self.assertEqual(dest.read_bytes(), payload)

    def test_download_verified_rejects_a_different_checksum(self):
        with tempfile_dir() as root:
            bindir = root / "bin"
            bindir.mkdir()
            mock = bindir / "curl"
            mock.write_text("#!/bin/bash\nprintf 'other' > \"$5\"\n")
            mock.chmod(mock.stat().st_mode | stat.S_IEXEC)
            dest = root / "payload"
            env = os.environ.copy()
            env["PATH"] = f"{bindir}{os.pathsep}{env.get('PATH', '')}"
            script = f'set -euo pipefail\nsource "{COMMON}"\ndownload_verified "$1" "$2" "$3"\n'
            result = subprocess.run(
                ["bash", "-c", script, "bash", "https://example.test/file", str(dest), "0" * 64],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("FAILED", result.stdout + result.stderr)


class tempfile_dir:
    def __enter__(self):
        import tempfile

        self._temporary = tempfile.TemporaryDirectory()
        return Path(self._temporary.name)

    def __exit__(self, exc_type, exc, traceback):
        self._temporary.cleanup()


if __name__ == "__main__":
    unittest.main()
