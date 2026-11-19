# Upstream file checks

The Monday 06:00 UTC schedule and manual dispatch use upstream-sync.json.

- Default mode (`merge`): three-way merge actual upstream file changes using
  `base_sha`. Unchanged content leaves the baseline untouched, even when
  unrelated upstream commits advance the branch.
- `notify-only`: preserve the local file, including a locally absent file.
  Compare upstream content against `base_sha` and open an issue for each
  previously unreported content hash (or upstream absence). This mode requires
  an explicit baseline and never changes it automatically.

The customized 10-update.just and topgrade.toml entries use notify-only.
On the first run, changes since their existing baseline are reported once,
including the already known update-command change and missing Topgrade file.
Notifications link to the baseline, current upstream commit, and comparison.
Other tracked files retain their normal merge behavior.

Open and closed issues contain hidden receipt markers. Closing an issue
dismisses that upstream state permanently; do not delete the receipt or its
marker. Repeated content is intentionally not reported again, including
reversions to a previously reported state. Content matching the configured
baseline is always silent. A different state creates a new issue.

Issue enumeration is paginated and includes closed issues; PRs do not count
as receipts. API errors fail the job instead of recording a successful
notification. Existing workflow concurrency serializes scheduled/manual runs.
The workflow token needs issues: write in addition to existing permissions.
Notify-only changes do not create sync commits or dispatch image builds.

Run regression tests with:
`python3 -m unittest discover -s tests -p 'test_upstream_sync.py'`
