# CI Skills for nf-core/hlatyping

## Skill: `/ci-status`

Check current CI status for a branch or PR.

### Steps:
1. Determine current branch: `git branch --show-current`
2. Check PR status: `gh pr checks` or `gh run list --branch <branch>`
3. Report status of each job in the "Run nf-test" workflow:
   - **nf-test** (main pipeline tests, sharded)
   - **hlahd** (HLA-HD licensed tests)
   - **confirm-pass** (aggregated result)
4. For failures, provide links to logs: `gh run view <run-id> --log-failed`

---

## Skill: `/ci-debug`

Debug failing CI tests by analyzing logs, test files, snapshots, and configs.

### Steps:
1. Identify the failing job:
   - `gh pr checks` to see which job failed
   - `gh run view <run-id> --log-failed` for error details

2. **For nf-test job failures**, check:
   - Snapshot mismatches: compare `tests/*.nf.test.snap` with CI output
   - Test config correctness: `conf/test*.config` params
   - nf-test.config triggers list — did a trigger file change cause unexpected full runs?
   - Resource limits in test configs vs runner capacity

3. **For hlahd job failures**, check:
   - Is the PR from within `nf-core/hlatyping`? Fork PRs cannot access `GPG_PASSPHRASE` secret — hlahd job will be skipped
   - GPG decryption: verify the tarball URL and decryption command
   - HLA-HD path parameter: must match `conf/test_hlahd.config` `hlahd_path`

4. **Common failure patterns**:
   - `--tag !hlahd` used somewhere → nf-test 0.9.3 does NOT support tag negation. Fix: use `--tag pipeline` with positive matching
   - `get-shards` returns 0 → check if `--tag` was passed to dry-run (breaks in 0.9.3)
   - `--changed-since HEAD^` shows "found" but "not executed" → file is not in triggers list, expected behavior
   - Snapshot mismatch → update with `nf-test test --update-snapshot --profile debug,test,docker`
   - hlahd job skipped → check `if:` condition — must be internal PR, not fork

---

## Skill: `/ci-template-sync`

Compare CI files against the nf-core TEMPLATE branch and identify pipeline-specific customizations to preserve during template updates.

### Steps:
1. Fetch TEMPLATE: `git fetch origin TEMPLATE`
2. Compare key files:
   ```bash
   git diff origin/TEMPLATE -- .github/actions/nf-test/action.yml
   git diff origin/TEMPLATE -- .github/workflows/nf-test.yml
   git diff origin/TEMPLATE -- .github/actions/get-shards/action.yml
   ```
3. **Pipeline-specific customizations to preserve** (not in TEMPLATE):
   - `changed_since` input in `action.yml`
   - Optional `shard`/`total_shards`/`paths` inputs (required in TEMPLATE)
   - `tags: "pipeline"` in nf-test job
   - `hlahd` job (entirely pipeline-specific)
   - `confirm-pass` needs includes `hlahd`
   - `NFT_WORKDIR` value if different from TEMPLATE default

4. Report which customizations exist and whether they conflict with TEMPLATE updates.

---

## Skill: `/add-external-tool-test`

Guide adding a new external/licensed tool to CI tests (following the HLA-HD / NetMHCpan pattern from epitopeprediction).

### Steps:

1. **Create test config** `conf/test_<tool>.config`:
   - Set `resourceLimits` appropriate for CI runners (4 CPUs, 15GB memory typical)
   - Set tool-specific params (input samplesheet, tool path, options)
   - Tool path should reference `${projectDir}/<tarball>` (downloaded in CI)

2. **Create test file** `tests/<tool>.nf.test`:
   - Add ONLY `tag "<tool>"` — do NOT add `tag "pipeline"`
   - Use `profile "test_<tool>"`
   - Exclude non-deterministic tool outputs from snapshot comparison if needed:
     ```groovy
     stable_name = stable_name.findAll { !it.startsWith('<tool>') }
     stable_path = stable_path.findAll { !it.toString().contains('/<tool>/') }
     ```

3. **Add job in `nf-test.yml`** (NOT a separate workflow file):
   - `if:` condition for internal PRs only:
     ```yaml
     if: ${{ ( github.event_name == 'push' && github.repository == 'nf-core/hlatyping' ) || github.event.pull_request.head.repo.full_name == 'nf-core/hlatyping' }}
     ```
   - Download step: fetch encrypted tarball from test-datasets or S3
   - Decrypt step: `gpg --batch --yes --pinentry-mode=loopback --passphrase "${{ secrets.GPG_PASSPHRASE }}" --output <output> --decrypt <input.gpg>`
   - Run nf-test action with `tags: <tool>` and `changed_since: ""`

4. **Add to `confirm-pass`** `needs:` list so overall CI status reflects the tool test.

### Critical rules:
- External tool tests must NOT have `tag "pipeline"` — this ensures they don't run in the main sharded job where the tool isn't available
- Use `changed_since: ""` (empty) to always run all tests, not just changed files
- nf-test 0.9.3 does NOT support tag negation (`--tag !X`) — only positive matching works
- Keep everything in one workflow file (`nf-test.yml`) — do NOT create separate workflow files for external tools
