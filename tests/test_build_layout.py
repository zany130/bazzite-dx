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
    "stages/02-fedora-packages.sh",
    "stages/03-dx-packages.sh",
    "stages/04-third-party-packages.sh",
    "stages/05-copr-packages.sh",
    "stages/06-cockpit.sh",
    "stages/07-refind-gui.sh",
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
        self.assertEqual(bash_array(read("stages/02-fedora-packages.sh"), "fedora_packages"), BASE_PACKAGES)
        dx = read("stages/03-dx-packages.sh")
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
        self.assertIn(
            "dnf5 --refresh --enable-repo=docker-ce-stable install -y \\\n"
            '    "${docker_packages[@]}"',
            dx,
        )
        self.assertLess(
            dx.index("dnf5 --refresh --enable-repo=docker-ce-stable install -y"),
            dx.index('"${dx_debug_packages[@]}"'),
        )
        self.assertEqual(
            bash_array(dx, "docker_packages"),
            [
                "containerd.io",
                "docker-buildx-plugin",
                "docker-ce",
                "docker-ce-cli",
                "docker-compose-plugin",
            ],
        )
        self.assertNotIn("cockpit-machines", dx)
        third = read("stages/04-third-party-packages.sh")
        self.assertNotIn("docker-ce", third)
        self.assertIn(
            'dnf5 --refresh "${rpmfusion_repo_args[@]}" install -y \\\n'
            "    dolphin-megasync \\\n"
            "    megasync",
            third,
        )
        cockpit = read("stages/06-cockpit.sh")
        self.assertIn("dnf5 install -y cockpit-machines\n", cockpit)
        self.assertLess(
            cockpit.index("dnf5 install -y cockpit-machines"),
            cockpit.index('dnf5 --refresh --enable-repo="${fortyfive_repo_id}" install -y'),
        )
        self.assertIn(
            'dnf5 --refresh --enable-repo="${fortyfive_repo_id}" install -y \\\n'
            "    cockpit-file-sharing \\\n"
            "    cockpit-navigator \\\n"
            "    cockpit-benchmark",
            cockpit,
        )
        machines = cockpit.split("dnf5 install -y cockpit-machines", 1)[0]
        self.assertNotIn("--enable-repo", machines)
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
        self.assertIn("repo_gpgcheck=1\n", repos)
        self.assertLess(
            repos.index('dnf5 config-manager setopt "${fortyfive_repo_id}.enabled=0"'),
            repos.index("dnf5 --refresh makecache"),
        )
        self.assertLess(repos.index("enabled=0\ngpgcheck=1\nrepo_gpgcheck=1\n"), repos.index("dnf5 --refresh makecache"))
        self.assertIn(
            "dnf5 --refresh --enable-repo=gitea-unom-bazzite install -y \\\n"
            "    punktfunk \\\n"
            "    punktfunk-web \\\n"
            "    punktfunk-scripting",
            read("stages/04-third-party-packages.sh"),
        )
        copr = read("stages/05-copr-packages.sh")
        self.assertIn("copr_install_isolated rok/cdemu", copr)
        self.assertNotIn("punktfunk", copr)
        self.assertIn(
            "systemctl --global disable punktfunk-scripting.service\n",
            read("stages/08-services.sh"),
        )

    def test_stage_03_is_optional_for_later_custom_stages(self):
        names = {path.name for path in (BUILD_DIR / "stages").iterdir()}
        self.assertEqual(
            names,
            {
                "01-repositories.sh",
                "02-fedora-packages.sh",
                "03-dx-packages.sh",
                "04-third-party-packages.sh",
                "05-copr-packages.sh",
                "06-cockpit.sh",
                "07-refind-gui.sh",
                "08-services.sh",
            },
        )
        dx = read("stages/03-dx-packages.sh")
        self.assertIsNone(re.search(r"^[A-Za-z_][A-Za-z0-9_]*\(\)", dx, re.M))
        later = "\n".join(
            read(name)
            for name in SOURCE_ORDER
            if name.startswith("stages/") and name.split("/")[1] > "03-dx-packages.sh"
        )
        for owned in (
            "docker_packages",
            "dx_debug_packages",
            "dx_editor_packages",
            "dx_workstation_packages",
            "dx_container_packages",
            "dx_virtualization_packages",
            "dx_remote_packages",
            "dx_acceleration_packages",
        ):
            self.assertNotIn(owned, later, owned)
        services = read("stages/08-services.sh")
        self.assertIn("docker.socket          requires docker-ce from Stage 03", services)
        self.assertIn("virt*.socket           requires libvirt from Stage 03", services)
        cockpit = read("stages/06-cockpit.sh")
        self.assertIn("Skipping Stage 03 can let this install bring them back", cockpit)

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
