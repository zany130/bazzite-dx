"""Pull-request build steps stay validating without publish work."""

import unittest
from pathlib import Path


WORKFLOW = Path(__file__).resolve().parents[1] / ".github" / "workflows" / "build.yml"
PUBLISH_IF = (
    "github.event_name != 'pull_request' "
    "&& inputs.verified_head == '' "
    "&& github.ref == format('refs/heads/{0}', github.event.repository.default_branch)"
)
PR_SKIPPED = {
    "Rechunk with rpm-ostree",
    "Generate Build Tags",
    "Tag Image",
}
ALWAYS_ON_PR = {
    "Checkout",
    "Check Just Syntax",
    "Build Image",
}
PUBLISH_STEPS = {
    "Login to GitHub Container Registry",
    "Push To GHCR",
    "Install Cosign",
    "Sign container image",
}


def parse_steps(text):
    steps = []
    current = None
    for line in text.splitlines():
        if line.startswith("      - name: "):
            if current:
                steps.append(current)
            current = {"name": line.split(": ", 1)[1], "if": None, "body": []}
            continue
        if current is None:
            continue
        if line.startswith("        if: "):
            current["if"] = line.split(": ", 1)[1]
        current["body"].append(line)
    if current:
        steps.append(current)
    return steps


class PullRequestBuildWorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text()
        cls.steps = parse_steps(cls.text)
        cls.by_name = {step["name"]: step for step in cls.steps}

    def test_required_check_name_is_unchanged(self):
        self.assertIn("name: Build and push image\n", self.text)
        self.assertIn("build_push:\n", self.text)
        self.assertEqual(len(self.by_name), len(self.steps))

    def test_pull_requests_still_build_and_keep_existing_checks(self):
        for name in ALWAYS_ON_PR:
            self.assertIsNone(self.by_name[name]["if"], name)

    def test_pull_requests_skip_rechunk_and_registry_tags(self):
        for name in PR_SKIPPED:
            self.assertEqual(
                self.by_name[name]["if"],
                "github.event_name != 'pull_request'",
                name,
            )

    def test_main_still_publishes_and_signs(self):
        for name in PUBLISH_STEPS:
            self.assertEqual(self.by_name[name]["if"], PUBLISH_IF, name)

    def test_toolchain_cleanup_runs_only_on_small_disks(self):
        disk = self.by_name["Check free disk space"]
        cleanup = self.by_name["Maximize build space"]
        self.assertIsNone(disk["if"])
        self.assertEqual(cleanup["if"], "steps.disk.outputs.squeeze == 'true'")
        body = "\n".join(disk["body"])
        self.assertIn("threshold_kib=$((70 * 1024 * 1024))", body)
        self.assertIn('echo "squeeze=true"', body)
        self.assertIn('echo "squeeze=false"', body)
        cleanup_body = "\n".join(cleanup["body"])
        self.assertIn(
            "ublue-os/remove-unwanted-software@695eb75bc387dbcd9685a8e72d23439d8686cba6",
            cleanup_body,
        )

    def test_skipped_pull_request_steps_have_no_later_dependency(self):
        for step in self.steps:
            body = "\n".join(step["body"])
            uses_skipped_output = (
                "steps.gen-build-tags.outputs" in body or "steps.rechunk.outputs" in body
            )
            if not uses_skipped_output:
                continue
            self.assertIsNotNone(step["if"], step["name"])
            self.assertIn("github.event_name != 'pull_request'", step["if"], step["name"])


if __name__ == "__main__":
    unittest.main()
