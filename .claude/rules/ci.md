# CI Rules for nf-core/hlatyping

## Key Files

- `.github/workflows/nf-test.yml` — Single test workflow with jobs: `nf-test-changes`, `nf-test`, `hlahd`, `confirm-pass`
- `.github/actions/nf-test/action.yml` — Shared composite action for running nf-test
- `.github/actions/get-shards/action.yml` — Dynamic shard calculation
- `nf-test.config` — nf-test framework configuration
- `tests/*.nf.test` — Test definitions
- `tests/*.nf.test.snap` — Snapshot baselines

## TEMPLATE Branch Alignment

The workflow and action files should stay as close as possible to the nf-core TEMPLATE to minimize merge conflicts. Pipeline-specific behavior is controlled via input parameters with backwards-compatible defaults.

Compare with TEMPLATE:
```bash
git fetch origin TEMPLATE
git diff origin/TEMPLATE -- .github/actions/nf-test/action.yml
git diff origin/TEMPLATE -- .github/workflows/nf-test.yml
git diff origin/TEMPLATE -- .github/actions/get-shards/action.yml
```

Pipeline-specific divergences from TEMPLATE (preserve during template sync):
- `shard`, `total_shards`, `paths` inputs made optional with defaults (required in TEMPLATE)
- `changed_since` input in action.yml (default: `HEAD^`, empty = run all tests) — not in TEMPLATE
- `tags: "pipeline"` in nf-test job — TEMPLATE has no tags
- `hlahd` job — entirely pipeline-specific
- `confirm-pass` needs includes `hlahd`

## nf-test Workflow Jobs

1. **nf-test-changes** — Calculates test shards via `get-shards` action (max 7)
2. **nf-test** — Runs pipeline tests in parallel shards with `tags: "pipeline"`. Matrix: profile × NXF_VER. Excludes conda/singularity on dev branches.
3. **hlahd** — Runs HLA-HD tests with `tags: hlahd`. Only on internal PRs/pushes (secret access). Downloads + decrypts HLA-HD tarball. Uses `changed_since: ""` to run all tests.
4. **confirm-pass** — Aggregates results from `nf-test` and `hlahd`. Fails if any non-latest-everything job failed.

## Tag-based Test Separation (CRITICAL)

Following the pattern from nf-core/epitopeprediction (netmhcpan):

- **Standard tests**: Use `tag "pipeline"` — selected by `--tag pipeline` in `nf-test` job
- **HLA-HD tests**: Use ONLY `tag "hlahd"` (NOT `"pipeline"`) — selected by `--tag hlahd` in `hlahd` job

This ensures HLA-HD tests never run in the main sharded job where the software isn't available.

## nf-test 0.9.3 Known Behaviors

1. **Tag negation does NOT work** — `--tag !hlahd` causes "Found tests" but "No tests to execute". Always use positive tag matching (`--tag pipeline`).
2. **`--dry-run` + `--tag` incompatibility** — `get-shards` should NOT pass `--tag` to nf-test dry-run.
3. **`--changed-since HEAD^` + triggers** — Non-trigger file changes show "found" but "not executed".
4. **get-shards output parsing** — Looks for `Executed N tests`; returns 0 shards if `No tests to execute`.

## External Tool CI Pattern

For tools requiring download/decryption (HLA-HD, or future licensed tools):

1. Create `conf/test_<tool>.config` with tool-specific params and resource limits
2. Create `tests/<tool>.nf.test` with ONLY `tag "<tool>"` (NOT `"pipeline"`)
3. Add job in `nf-test.yml` with:
   - `if:` condition restricting to internal PRs (fork PRs cannot access secrets)
   - Download and GPG decrypt steps using `secrets.GPG_PASSPHRASE`
   - nf-test action call with `tags: <tool>` and `changed_since: ""`
4. Add the job to `confirm-pass` `needs:` list

## Action Parameters (`.github/actions/nf-test/action.yml`)

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `profile` | Yes | — | Nextflow profile (docker, singularity, conda) |
| `shard` | No | `"1"` | Current shard number |
| `total_shards` | No | `"1"` | Total number of shards |
| `paths` | No | `""` | Test paths |
| `tags` | No | — | Tags for `--tag` (positive matching only!) |
| `changed_since` | No | `"HEAD^"` | Git ref for `--changed-since` (empty = run all) |

## Environment Variables

```yaml
NFT_VER: "0.9.3"
NFT_WORKDIR: "~"
NXF_ANSI_LOG: false
```

## nf-test.config Triggers

Changes to these files trigger a full test run (not just changed tests):
```
nextflow.config, nf-test.config, conf/test.config, tests/nextflow.config, tests/.nftignore
```

## Snapshot Testing

- Snapshots stored as `.nf.test.snap` JSON files alongside test files
- Files in `tests/.nftignore` excluded from content comparison
- Update snapshots: `nf-test test --update-snapshot`
- External tool outputs may need explicit exclusion from snapshots if non-deterministic
