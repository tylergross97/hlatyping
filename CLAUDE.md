# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

nf-core/hlatyping is a Nextflow DSL2 bioinformatics pipeline for HLA typing from next-generation sequencing data. It supports two HLA typing tools: **OptiType** (open-source, default) and **HLA-HD** (licensed, optional). Built on the nf-core template (v3.5.1), requires Nextflow >=25.04.0.

## Common Commands

```bash
# Run all tests (Docker)
nf-test test --profile debug,test,docker --verbose

# Run a single test file
nf-test test tests/default.nf.test --profile debug,test,docker --verbose

# Run sharded tests (as CI does, 7 shards)
nf-test test --profile docker --shard 1/7 --tag '!hlahd'

# Lint
nf-core pipelines lint --dir .
pre-commit run --all-files

# Run pipeline directly
nextflow run . -profile test,docker --outdir results
```

## Architecture

**Entry point**: `main.nf` → initializes params and calls `workflows/hlatyping.nf`

**Pipeline flow**: Input (FastQ/BAM) → FastQC → Yara index/map → HLA typing (OptiType and/or HLA-HD) → MultiQC

**Key directories**:
- `workflows/hlatyping.nf` — Main workflow orchestration
- `modules/local/` — Custom modules: `check_paired`, `hlahd/install`, `hlahd/genotype`
- `modules/nf-core/` — Community modules: `optitype`, `yara`, `fastqc`, `samtools`, `multiqc`, etc.
- `subworkflows/` — Reusable workflow fragments
- `conf/` — Configuration files including `base.config` (resources), `modules.config`, and `test*.config` profiles
- `data/references/` — HLA reference FASTA files and allele database

**Config hierarchy**: `nextflow.config` → `conf/base.config` → `conf/modules.config` → profile-specific configs

**Test profiles**: `test`, `test_full`, `test_fastq`, `test_fastq_cat`, `test_rna`, `test_dna_rna`, `test_hlahd`, `test_optitype_hlahd`

## CI/CD

- **`nf-test.yml`** — Main test workflow with matrix (conda/docker/singularity × Nextflow versions), 7 shards, self-hosted runners. HLA-HD tests excluded (`!hlahd` tag).
- **`nf-test-hlahd.yml`** — Separate workflow for licensed HLA-HD tests; decrypts GPG-encrypted tarball using `GPG_PASSPHRASE` secret.
- **`linting.yml`** — Runs pre-commit hooks and `nf-core pipelines lint`.
- Custom composite action at `.github/actions/nf-test/action.yml` handles test setup and execution.

## Key Conventions

- Nextflow DSL2 module structure: each module in its own directory with `main.nf`
- nf-core modules are managed via `nf-core modules` CLI; versions tracked in `modules.json`
- Pipeline parameters defined in `nextflow_schema.json` and validated by nf-schema plugin
- Process resources configured by labels in `conf/base.config` (e.g., `process_single`, `process_low`)
- Test snapshots stored as `.nf.test.snap` files alongside test files