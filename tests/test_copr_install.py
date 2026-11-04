"""Isolated COPR installs register a missing repo, then leave it disabled."""

import os
import stat
import subprocess
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COPR = ROOT / "build_files" / "lib" / "copr.sh"
STAGE = ROOT / "build_files" / "stages" / "05-copr-packages.sh"

MOCK = textwrap.dedent(
    """\
    #!/bin/bash
    set -euo pipefail
    printf '%s\\n' "$*" >> "${DNF_MOCK_LOG:?}"
    if [[ "$1" == "repolist" && "${2:-}" == "--all" ]]; then
        if [[ "${DNF_MOCK_FAIL_REPOLIST}" == 1 ]]; then
            echo "dnf5: simulated repolist failure" >&2
            exit 1
        fi
        printf 'repo id name status\\n'
        printf '%s' "${DNF_MOCK_REPOS}"
        exit 0
    fi
    if [[ "$1" == "-y" && "$2" == "copr" && "$3" == "enable" ]]; then
        if [[ "${DNF_MOCK_FAIL_ENABLE}" == 1 ]]; then
            echo "dnf5: simulated enable failure" >&2
            exit 1
        fi
        printf '1' > "${DNF_MOCK_STATE}"
        exit 0
    fi
    if [[ "$1" == "-y" && "$2" == "copr" && "$3" == "disable" ]]; then
        if [[ "${DNF_MOCK_FAIL_DISABLE}" == 1 ]]; then
            echo "dnf5: simulated disable failure" >&2
            exit 1
        fi
        printf '0' > "${DNF_MOCK_STATE}"
        exit 0
    fi
    if [[ "$1" == "install" ]]; then
        if [[ "${DNF_MOCK_FAIL_INSTALL}" == 1 ]]; then
            echo "dnf5: simulated install failure" >&2
            exit 1
        fi
        exit 0
    fi
    echo "unexpected dnf5 invocation: $*" >&2
    exit 99
    """
)


class CoprInstallTest(unittest.TestCase):
    def test_repo_id_uses_the_dnf5_copr_format(self):
        result = subprocess.run(
            [
                "bash",
                "-c",
                f'source "{COPR}"; copr_repo_id "$1"',
                "bash",
                "rok/cdemu",
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "copr:copr.fedorainfracloud.org:rok:cdemu\n",
        )

    def test_missing_repo_is_disabled_before_install(self):
        result, log, state = self.run_install(
            ["matinlotfali/KDE-Rounded-Corners", "kwin-effect-roundcorners"]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            log.splitlines(),
            [
                "repolist --all",
                "-y copr enable matinlotfali/KDE-Rounded-Corners",
                "-y copr disable matinlotfali/KDE-Rounded-Corners",
                "install -y --from-repo=copr:copr.fedorainfracloud.org:matinlotfali:KDE-Rounded-Corners "
                "kwin-effect-roundcorners",
            ],
        )
        self.assertNotIn("--enablerepo", log)
        self.assertEqual(state, "0")

    def test_install_failure_leaves_the_new_repo_disabled(self):
        result, log, state = self.run_install(
            ["loteran/arctis-sound-manager", "arctis-sound-manager"],
            fail_install=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("simulated install failure", result.stderr)
        self.assertLess(
            log.index("-y copr disable loteran/arctis-sound-manager"),
            log.index("install -y --from-repo="),
        )
        self.assertEqual(log.count("-y copr enable "), 1)
        self.assertEqual(state, "0")

    def test_disable_failure_does_not_install(self):
        result, log, state = self.run_install(
            ["rok/cdemu", "vhba"],
            fail_disable=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Not installing packages.", result.stderr)
        self.assertNotIn("install ", log)
        self.assertEqual(state, "1")

    def test_enable_failure_stops_before_disable_or_install(self):
        result, log, state = self.run_install(
            ["rok/cdemu", "vhba"],
            fail_enable=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("simulated enable failure", result.stderr)
        self.assertNotIn("copr disable", log)
        self.assertNotIn("install ", log)
        self.assertEqual(state, "absent")

    def test_configured_repo_keeps_its_saved_enablement(self):
        repo = "copr:copr.fedorainfracloud.org:rok:cdemu Copr disabled\n"
        result, log, state = self.run_install(
            [
                "rok/cdemu",
                "--setopt=install_weak_deps=False",
                "--setopt=tsflags=noscripts",
                "cdemu-client",
                "cdemu-daemon",
                "gcdemu",
                "vhba",
            ],
            repos=repo,
            initial_state="0",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            log.splitlines(),
            [
                "repolist --all",
                "install -y --from-repo=copr:copr.fedorainfracloud.org:rok:cdemu "
                "--setopt=install_weak_deps=False --setopt=tsflags=noscripts "
                "cdemu-client cdemu-daemon gcdemu vhba",
            ],
        )
        self.assertNotIn("copr enable", log)
        self.assertNotIn("copr disable", log)
        self.assertEqual(state, "0")

    def test_configured_enabled_repo_stays_enabled_when_install_fails(self):
        repo = "copr:copr.fedorainfracloud.org:rok:cdemu Copr enabled\n"
        result, log, state = self.run_install(
            ["rok/cdemu", "vhba"],
            repos=repo,
            initial_state="1",
            fail_install=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("copr enable", log)
        self.assertNotIn("copr disable", log)
        self.assertEqual(state, "1")

    def test_repolist_failure_does_not_register_a_copr(self):
        result, log, state = self.run_install(
            ["rok/cdemu", "vhba"],
            fail_repolist=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to list DNF repositories while checking COPR", result.stderr)
        self.assertNotIn("copr enable", log)
        self.assertNotIn("install ", log)
        self.assertEqual(state, "absent")

    def test_missing_package_list_does_not_call_dnf(self):
        result, log, state = self.run_install(["rok/cdemu"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("at least one package", result.stderr)
        self.assertEqual(log, "")
        self.assertEqual(state, "absent")

    def test_stage_preserves_packages_and_cdemu_options(self):
        text = STAGE.read_text()
        self.assertIn(
            "copr_install_isolated matinlotfali/KDE-Rounded-Corners \\\n"
            "    kwin-effect-roundcorners\n",
            text,
        )
        self.assertIn(
            "copr_install_isolated loteran/arctis-sound-manager \\\n"
            "    arctis-sound-manager\n",
            text,
        )
        self.assertIn(
            "copr_install_isolated rok/cdemu \\\n"
            "    --setopt=install_weak_deps=False \\\n"
            "    --setopt=tsflags=noscripts \\\n"
            "    cdemu-client \\\n"
            "    cdemu-daemon \\\n"
            "    gcdemu\n",
            text,
        )
        executable = "\n".join(
            line for line in text.splitlines() if not line.lstrip().startswith("#")
        )
        self.assertNotIn("dnf5 -y copr enable", executable)

    def test_helper_is_not_an_entry_point(self):
        result = subprocess.run(
            ["bash", str(COPR)],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source lib/copr.sh from build.sh.", result.stderr)

    def run_install(self, args, repos="", initial_state="absent", **flags):
        with tempfile_dir() as root:
            bindir = root / "bin"
            bindir.mkdir()
            log_path = root / "dnf.log"
            state_path = root / "state"
            state_path.write_text(initial_state)
            mock = bindir / "dnf5"
            mock.write_text(MOCK)
            mock.chmod(mock.stat().st_mode | stat.S_IEXEC)
            env = os.environ.copy()
            env.update(
                {
                    "PATH": f"{bindir}{os.pathsep}{env.get('PATH', '')}",
                    "DNF_MOCK_LOG": str(log_path),
                    "DNF_MOCK_STATE": str(state_path),
                    "DNF_MOCK_REPOS": repos,
                    "DNF_MOCK_FAIL_REPOLIST": "1" if flags.get("fail_repolist") else "0",
                    "DNF_MOCK_FAIL_ENABLE": "1" if flags.get("fail_enable") else "0",
                    "DNF_MOCK_FAIL_DISABLE": "1" if flags.get("fail_disable") else "0",
                    "DNF_MOCK_FAIL_INSTALL": "1" if flags.get("fail_install") else "0",
                    "HOME": str(root),
                }
            )
            quoted = " ".join("'" + arg.replace("'", "'\\''") + "'" for arg in args)
            script = f'set -euo pipefail\nsource "{COPR}"\ncopr_install_isolated {quoted}\n'
            result = subprocess.run(
                ["bash", "-c", script],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            log = log_path.read_text() if log_path.exists() else ""
            return result, log, state_path.read_text()


class tempfile_dir:
    def __enter__(self):
        import tempfile

        self._temporary = tempfile.TemporaryDirectory()
        return Path(self._temporary.name)

    def __exit__(self, exc_type, exc, traceback):
        self._temporary.cleanup()


if __name__ == "__main__":
    unittest.main()
