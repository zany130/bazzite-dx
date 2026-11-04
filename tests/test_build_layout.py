"""The sourced build keeps the previous transaction order and package lists."""

import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build_files"
BUILD = BUILD_DIR / "build.sh"
CONTAINERFILE = ROOT / "Containerfile"

SOURCE_ORDER = [
    "lib/common.sh",
    "lib/repositories.sh",
    "lib/copr.sh",
    "stages/01-repositories.sh",
    "stages/02-base-packages.sh",
    "stages/03-refind-gui.sh",
    "stages/04-third-party-packages.sh",
    "stages/05-dx-packages.sh",
    "stages/06-cockpit.sh",
    "stages/07-copr-punktfunk.sh",
    "stages/08-services.sh",
]

BASE_PACKAGES = [
    "beep",
    "btfs",
    "bsdtar",
    "google-authenticator",
    "kvantum",
    "liquidctl",
    "mpv",
    "python3-pygame",
    "rEFInd",
    "rEFInd-tools",
    "solaar",
    "tesseract",
    "tesseract-langpack-eng",
    "tesseract-langpack-spa",
    "tesseract-libs",
    "mosh",
    "nmap",
]

DX_GROUPS = {
    "dx_debug_packages": [
        "android-tools",
        "bcc",
        "bpftop",
        "bpftrace",
        "ccache",
        "nicstat",
        "numactl",
        "sysprof",
        "tiptop",
    ],
    "dx_editor_packages": [
        "flatpak-builder",
        "git-subtree",
        "google-noto-sans-fonts",
        "ramalama",
    ],
    "dx_workstation_packages": [
        "cockpit",
        "cockpit-machines",
        "cockpit-ostree",
        "cockpit-ws-selinux",
        "guestfs-tools",
    ],
    "dx_container_packages": ["podman-machine", "podman-tui"],
    "dx_virtualization_packages": [
        "libvirt",
        "python3-libvirt",
        "qemu",
        "qemu-kvm",
        "qemu-system-x86",
        "qemu-user-static-aarch64",
        "swtpm",
        "virt-manager",
        "virtiofsd",
        "virtualbox-guest-additions",
    ],
    "dx_remote_packages": ["rclone", "restic", "usbmuxd", "waypipe", "zsh"],
    "dx_acceleration_packages": ["rocm-clinfo", "rocm-hip", "rocm-opencl", "rocm-smi"],
}


def read(relative):
    return (BUILD_DIR / relative).read_text()


def bash_array(text, name):
    match = re.search(rf"^{name}=\((.*?)\)", text, re.M | re.S)
    if match is None:
        raise AssertionError(f"{name} is missing")
    return re.findall(r"[A-Za-z0-9_.+-]+", match.group(1))


class BuildLayoutTest(unittest.TestCase):
    def test_build_sh_sources_stages_in_order(self):
        sourced = re.findall(r'source "\$\{BUILD_ROOT\}/([^"]+)"', BUILD.read_text())
        self.assertEqual(sourced, SOURCE_ORDER)
        executable = "\n".join(
            line
            for line in BUILD.read_text().splitlines()
            if line.strip() and not line.strip().startswith("#")
        )
        self.assertNotIn("/ctx/stages", executable)
        self.assertNotRegex(executable, r"\bbash\b")
        self.assertIn("/ctx/build.sh", CONTAINERFILE.read_text())
        self.assertNotIn("/ctx/stages", CONTAINERFILE.read_text())

    def test_renovate_pins_stay_adjacent_in_build_sh(self):
        text = BUILD.read_text()
        self.assertRegex(
            text,
            r"# renovate: datasource=github-release-attachments depName=jlobue10/rEFInd_GUI\n"
            r'REFIND_GUI_VERSION="v[0-9]+\.[0-9]+\.[0-9]+"\n'
            r'REFIND_GUI_SHA256="[a-f0-9]{64}"',
        )
        self.assertRegex(
            text,
            r"# Updated on Renovate PRs by refind-checksums.yml before dispatching the image build.\n"
            r'REFIND_GUI_SOURCE_SHA256="[a-f0-9]{64}"',
        )
        for dep, version in [
            ("zany130/cockpit-probe", "COCKPIT_HARDWARE_PROBE_VERSION"),
            ("zany130/cockpit-diagnostics", "COCKPIT_DIAGNOSTICS_VERSION"),
            ("realmcuser/cockpit-nspawn", "COCKPIT_NSPAWN_VERSION"),
        ]:
            self.assertRegex(
                text,
                rf"# renovate: datasource=github-releases depName={re.escape(dep)}[^\n]*\n"
                rf'{version}="[^"]+"',
            )
        for name in [
            "REFIND_GUI_VERSION",
            "REFIND_GUI_SHA256",
            "REFIND_GUI_SOURCE_SHA256",
            "COCKPIT_HARDWARE_PROBE_VERSION",
            "COCKPIT_NSPAWN_VERSION",
        ]:
            self.assertEqual(len(re.findall(rf"^{name}=", text, re.M)), 1)

    def test_package_lists_and_transactions_are_unchanged(self):
        self.assertEqual(bash_array(read("stages/02-base-packages.sh"), "base_packages"), BASE_PACKAGES)
        dx = read("stages/05-dx-packages.sh")
        for name, packages in DX_GROUPS.items():
            self.assertEqual(bash_array(dx, name), packages, name)
        self.assertIn(
            'dnf5 install -y \\\n'
            '    "${dx_debug_packages[@]}" \\\n'
            '    "${dx_editor_packages[@]}" \\\n'
            '    "${dx_workstation_packages[@]}" \\\n'
            '    "${dx_container_packages[@]}" \\\n'
            '    "${dx_virtualization_packages[@]}" \\\n'
            '    "${dx_remote_packages[@]}" \\\n'
            '    "${dx_acceleration_packages[@]}"',
            dx,
        )
        third = read("stages/04-third-party-packages.sh")
        self.assertIn(
            "dnf5 --refresh --enable-repo=docker-ce-stable install -y \\\n"
            '    "${docker_packages[@]}"',
            third,
        )
        self.assertEqual(
            bash_array(third, "docker_packages"),
            [
                "containerd.io",
                "docker-buildx-plugin",
                "docker-ce",
                "docker-ce-cli",
                "docker-compose-plugin",
            ],
        )
        self.assertIn(
            'dnf5 --refresh "${rpmfusion_repo_args[@]}" install -y \\\n'
            "    dolphin-megasync \\\n"
            "    megasync",
            third,
        )
        cockpit = read("stages/06-cockpit.sh")
        self.assertIn(
            'dnf5 --refresh --enable-repo="${fortyfive_repo_id}" install -y \\\n'
            "    cockpit-file-sharing \\\n"
            "    cockpit-navigator \\\n"
            "    cockpit-benchmark",
            cockpit,
        )
        services = read("stages/08-services.sh")
        self.assertIn(
            "dnf5 remove -y \\\n    kate \\\n    kwrite \\\n    kfind\n",
            services,
        )
        self.assertIn("systemctl enable beep-startup.service\n", services)
        self.assertIn("# dnf5 -y copr enable ublue-os/bazzite-multilib\n", services)

    def test_repository_safeguards_stay_in_order(self):
        repos = read("stages/01-repositories.sh")
        self.assertLess(
            repos.index("dnf5 versionlock add 'qt6-*' 'plasma-*'"),
            repos.index("configure_terra_repository"),
        )
        self.assertIn('"${terra_repo_id}.enabled=0"', read("lib/repositories.sh"))
        self.assertIn("enabled=0\n", repos)
        self.assertIn("gpgcheck=1\n", repos)
        punkt = read("stages/07-copr-punktfunk.sh")
        self.assertIn("repo_gpgcheck=1\n", punkt)
        self.assertLess(
            punkt.index("copr_install_isolated rok/cdemu"),
            punkt.index("dnf5 --refresh --enable-repo=gitea-unom-bazzite install -y"),
        )
        self.assertLess(
            punkt.index("punktfunk-scripting"),
            punkt.index("systemctl --global disable punktfunk-scripting.service"),
        )

    def test_scripts_pass_bash_and_shellcheck(self):
        scripts = sorted(BUILD_DIR.rglob("*.sh"))
        self.assertGreaterEqual(len(scripts), len(SOURCE_ORDER) + 1)
        from shutil import which

        for script in scripts:
            syntax = subprocess.run(
                ["bash", "-n", str(script)],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(syntax.returncode, 0, syntax.stderr)
        if which("shellcheck") is None:
            return
        for script in scripts:
            checked = subprocess.run(
                ["shellcheck", str(script)],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        followed = subprocess.run(
            ["shellcheck", "-x", str(BUILD)],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(followed.returncode, 0, followed.stdout + followed.stderr)


if __name__ == "__main__":
    unittest.main()
