"""Fedora 45 images are checked with bootc instead of ostree container commit."""

import unittest
from pathlib import Path


CONTAINERFILE = Path(__file__).resolve().parents[1] / "Containerfile"


class ContainerfileBootcTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = CONTAINERFILE.read_text()

    def test_build_does_not_run_ostree_container_commit(self):
        instructions = [
            line.strip()
            for line in self.text.splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        self.assertFalse(
            any("ostree container commit" in line for line in instructions)
        )

    def test_image_is_linted_with_bootc(self):
        self.assertIn("RUN bootc container lint\n", self.text)


if __name__ == "__main__":
    unittest.main()
